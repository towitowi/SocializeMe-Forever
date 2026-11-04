local ADDON, SM = ...
local M = SM.Media

-- Der Zettel (test8b): EIN kleines Fenster unten rechts für alles, was von selbst kommt -
-- Musik-Angebot, Antwort auf Winken oder Gruß, Lagerfeuer-Pin, Geschichte am Feuer.
-- * Nie zwei gleichzeitig: kommt ein zweiter, wartet er, bis der erste weg ist
--   (derselbe Anlass ersetzt den alten statt sich anzustellen).
-- * Normale Zettel verschwinden nach 20 Sekunden von selbst (Maus darauf hält sie);
--   "sticky" bleiben, bis man sie wegklickt (z. B. jemand winkt dir zu).
-- * Er steht unten rechts (ca. 2 cm vom rechten, 4 cm vom unteren Rand); läuft gerade die Musikzeile, direkt
--   darüber. Verschiebbar - dann merkt er sich die Stelle (test8b).
-- * Läuft über SM:Popup: im Kampf / in Instanzen wartet er, und wer einen Zettel dreimal gleich
--   wieder zumacht, bekommt ihn nur noch als Chatzeile.
--   SM.Note:Ask(key, text, { { Beschriftung, Funktion }, ... }, { sticky, icon, hint, tip, chat, sound })
local Note = {}
SM.Note = Note

local WIDTH, SECONDS, FADE = 320, 20, 1.5
local BTN_W, BTN_H, BTN_GAP = 132, 22, 6
local LEFT = 38
local ICON = "Interface\\AddOns\\SocializeMeForever\\Media\\pin_campfire"
Note.queue = {}

function Note:Build()
    if self.frame then return self.frame end
    local UI = SM.UI
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "SocializeMeForeverNote", UIParent, template)
    self.frame = f
    f:SetSize(WIDTH, 70)
    -- test8f: eine Ebene höher - unten rechts liegen oft unsichtbare Fenster (Taschen-/Leisten-
    -- Bereich, andere Addons), die sonst die Klicks auf X und die Knöpfe abfangen
    f:SetFrameStrata("HIGH")
    if f.SetToplevel then f:SetToplevel(true) end
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    SM:MakeMovable(f, function() return SM.db.note end)
    if f.SetBackdrop then
        f:SetBackdrop({ edgeFile = M.tex.border, edgeSize = 16, insets = { left = 5, right = 5, top = 5, bottom = 5 } })
    end
    local paper = f:CreateTexture(nil, "BACKGROUND")
    paper:SetPoint("TOPLEFT", 5, -5)
    paper:SetPoint("BOTTOMRIGHT", -5, 5)
    paper:SetColorTexture(unpack(M.colors.parchment))
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(20, 20)
    f.icon:SetPoint("TOPLEFT", 12, -10)
    f.icon:SetTexture(ICON)
    local ink, soft = M.colors.ink, M.colors.soft
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("TOPLEFT", LEFT, -12)
    f.text:SetWidth(WIDTH - LEFT - 26)
    f.text:SetJustifyH("LEFT")
    f.text:SetJustifyV("TOP")
    f.text:SetTextColor(ink[1], ink[2], ink[3])
    f.text:SetShadowOffset(0, 0)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.hint:SetWidth(WIDTH - LEFT - 14)
    f.hint:SetJustifyH("LEFT")
    f.hint:SetJustifyV("TOP")
    f.hint:SetTextColor(soft[1], soft[2], soft[3])
    f.hint:SetShadowOffset(0, 0)
    f.buttons = {}
    for i = 1, 4 do
        local b = UI.Button(f, "SocializeMeForeverNoteBtn" .. i, BTN_W, BTN_H, "")
        b:SetScript("OnClick", function(btn)
            local fn = btn.action
            Note:Hide()
            if fn then SM.SafeCall(fn) end
        end)
        f.buttons[i] = b
    end
    local close = UI.CloseButton(f, function() Note:Hide() end)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -7, -7)
    f:SetScript("OnEnter", function(fr)
        local tip = Note.current and Note.current.tip
        if not tip then return end
        GameTooltip:SetOwner(fr, "ANCHOR_TOP")
        GameTooltip:AddLine(tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- verschwindet von selbst (nicht "sticky"); mit der Maus darauf bleibt er stehen
    f:SetScript("OnUpdate", function(fr)
        if not fr.hideAt then return end
        local now = GetTime()
        if fr.IsMouseOver and fr:IsMouseOver() then
            fr.hideAt = math.max(fr.hideAt, now + 3)
            fr:SetAlpha(1)
            return
        end
        local left = fr.hideAt - now
        if left <= 0 then Note:Hide() return end
        fr:SetAlpha(left < FADE and left / FADE or 1)
    end)
    -- weg ist weg (auch per Escape): der nächste wartende Zettel kommt kurz danach
    f:HookScript("OnHide", function()
        if not Note.current then return end -- schon über Note:Hide erledigt
        Note.current = nil
        if #Note.queue > 0 then C_Timer.After(0.3, function() Note:Next() end) end
    end)
    tinsert(UISpecialFrames, "SocializeMeForeverNote")
    f:Hide()
    -- frühere Namen (Tests, Probe): derselbe Zettel
    if SM.Chill then SM.Chill.note = f end
    if SM.Social then SM.Social.reply = f end
    return f
end

---------------------------------------------------------------------------
-- Platz unten rechts: ca. 2 cm vom rechten und 4 cm vom unteren Rand (test8d: über den
-- Aktionsleisten). WoW kennt keine cm - 2 cm sind auf üblichen Bildschirmen (24-27 Zoll) etwa
-- 6,5 % der Bildschirmhöhe.
---------------------------------------------------------------------------
function SM:CornerGap()
    local h = type(GetScreenHeight) == "function" and tonumber(GetScreenHeight()) or 768
    return math.floor(h * 0.065 + 0.5)
end

-- Rechte Aktionsleisten von WoW (MultiBarRight / MultiBarLeft): ihre leeren Plätze sind
-- unsichtbar, fangen aber Klicks ab. Wie weit reichen sie von rechts herein? (0 = keine)
local function RightBarsInset()
    local uiRight, uiTop = UIParent:GetRight(), UIParent:GetTop()
    if not (uiRight and uiTop) then return 0 end
    local uiScale = UIParent:GetEffectiveScale() or 1
    local inset = 0
    for _, name in ipairs({ "MultiBarRight", "MultiBarLeft" }) do
        local bar = _G[name]
        if bar and bar.IsShown and bar:IsShown() and bar.GetLeft then
            local left, bottom = bar:GetLeft(), bar:GetBottom()
            if left and bottom then
                local s = (bar:GetEffectiveScale() or uiScale) / uiScale
                left, bottom = left * s, bottom * s
                -- nur Leisten am rechten Rand, die bis in die untere Bildschirmhälfte reichen
                if left > uiRight * 0.75 and bottom < uiTop * 0.5 then
                    inset = math.max(inset, uiRight - left)
                end
            end
        end
    end
    return inset
end
SM.RightBarsInset = RightBarsInset

-- test8g: sind rechts Aktionsleisten an, links daneben statt 2 cm vom Rand
function SM:PlaceCorner(f)
    local gap = self:CornerGap()
    local inset = RightBarsInset()
    local x = (inset > 0) and math.floor(inset + 10 + 0.5) or gap
    f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -x, gap * 2)
end

-- Verschiebbar machen und die Stelle merken (store() = Tabelle in SM.db mit point/relPoint/x/y)
function SM:MakeMovable(f, store)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(fr) SM.UI.DragStart(fr) end)
    f:SetScript("OnDragStop", function(fr)
        fr:StopMovingOrSizing()
        local t = store()
        local point, _, relPoint, x, y = fr:GetPoint()
        if t and point then t.point, t.relPoint, t.x, t.y = point, relPoint, x, y end
    end)
end

-- Wohin? Selbst verschoben: dorthin. Sonst unten rechts - läuft die Musikzeile, direkt darüber.
function Note:Place()
    local f = self.frame
    if not f then return end
    f:ClearAllPoints()
    local t = SM.db and SM.db.note or {}
    local mini = SM.Chill and SM.Chill.mini
    if t.point then
        f:SetPoint(t.point, UIParent, t.relPoint or t.point, t.x or 0, t.y or 0)
    elseif mini and mini:IsShown() then
        f:SetPoint("BOTTOMRIGHT", mini, "TOPRIGHT", 0, 4)
    else
        SM:PlaceCorner(f)
    end
end

-- Einen Zettel jetzt zeigen (ohne Warteschlange)
function Note:Display(item)
    local f = self:Build()
    self.current = item
    f.icon:SetTexture(item.icon or ICON)
    f.text:SetText(item.text or "")
    local th = math.max(14, math.ceil(f.text:GetStringHeight() or 14))
    local y = -12 - th - 8
    local buttons = item.buttons or {}
    local rows = 0
    for i, b in ipairs(f.buttons) do
        local o = buttons[i]
        b:ClearAllPoints()
        if o then
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            b:SetText(o[1])
            b.action = o[2]
            b:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT + col * (BTN_W + BTN_GAP), y - row * (BTN_H + 4))
            b:Show()
            rows = row + 1
        else
            b.action = nil
            b:Hide()
        end
    end
    y = y - rows * (BTN_H + 4)
    f.hint:ClearAllPoints()
    if item.hint and item.hint ~= "" then
        f.hint:SetText(item.hint)
        f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT, y - 2)
        f.hint:Show()
        y = y - 2 - math.max(12, math.ceil(f.hint:GetStringHeight() or 12))
    else
        f.hint:SetText("")
        f.hint:Hide()
    end
    f:SetHeight(-y + 12)
    self:Place()
    f.hideAt = (not item.sticky) and (GetTime() + (item.seconds or SECONDS)) or nil
    f:SetAlpha(1)
    f:Show()
    SM:WatchPopup(item.learn or item.key, f)
    if item.sound and SM:SoundsOn() and type(PlaySound) == "function" then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081)
    end
    return f
end

-- Zeigen oder anstellen. Derselbe Anlass (key) ersetzt den alten.
function Note:Push(item)
    local f = self.frame
    if f and f:IsShown() and self.current then
        if self.current.key == item.key then
            f.smUsed = true -- vom Addon ersetzt, zählt nicht als "gleich wieder zu"
            self:Display(item)
            return "replaced"
        end
        for i, q in ipairs(self.queue) do
            if q.key == item.key then self.queue[i] = item return "queued" end
        end
        self.queue[#self.queue + 1] = item
        return "queued"
    end
    self:Display(item)
    return "shown"
end

function Note:Next()
    if self.frame and self.frame:IsShown() then return end
    local item = table.remove(self.queue, 1)
    if item then self:Display(item) end
end

-- Weg damit (X, Knopf, Zeit um). by = "addon": nicht als "gleich wieder zu" zählen.
function Note:Hide(by)
    local f = self.frame
    self.current = nil -- vor dem Hide: dann macht der OnHide-Haken nichts doppelt
    if f and f:IsShown() then
        if by == "addon" then f.smUsed = true end
        f:Hide()
    end
    if #self.queue > 0 then C_Timer.After(0.3, function() Note:Next() end) end
end

-- Einen bestimmten Zettel wegnehmen (gezeigt oder wartend)
function Note:Drop(key)
    for i = #self.queue, 1, -1 do
        if self.queue[i].key == key then table.remove(self.queue, i) end
    end
    if self.current and self.current.key == key then self:Hide("addon") end
end

-- Der übliche Weg: über SM:Popup (Ruhe im Kampf, Mitlernen)
function Note:Ask(key, text, buttons, opts)
    opts = opts or {}
    local learn = opts.learn or key -- Mitlernen je Art (z. B. alle Antwort-Zettel zusammen)
    local item = { key = key, learn = learn, text = text, buttons = buttons, sticky = opts.sticky, icon = opts.icon,
                   hint = opts.hint, tip = opts.tip, sound = opts.sound, seconds = opts.seconds }
    return SM:Popup(learn, function() Note:Push(item) end, opts.chat or (tostring(text or ""):gsub("\n", " ")))
end

SM:RegisterPosition(function() return SM.db.note end, function() return Note.frame end,
    function() Note:Place() end)
