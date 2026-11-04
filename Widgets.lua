local ADDON, SM = ...
local M = SM.Media

-- Eigene Bedienelemente im Holz-Look. Alles wird aus einfachen Farbflächen
-- gezeichnet (keine Blizzard-Vorlage, keine Bilddateien), deshalb sieht es auf
-- jedem Client gleich aus und wirkt auf dem Pergament nicht wie ein roter Fremdkörper.
local UI = {}
SM.UI = UI

local C = M.wood

local function Paint(tex, c, a)
    tex:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1)
end

-- Ein paar dezente Maserungs-Linien, pro Knopf leicht verschieden (fester Startwert,
-- damit nichts bei jedem Öffnen flackert).
local grainSeed = 7
local function Rand()
    grainSeed = (grainSeed * 1103515245 + 12345) % 2147483648
    return grainSeed / 2147483648
end

function UI.AddGrain(frame, width, height, layer)
    local lines = math.max(2, math.floor(height / 9))
    for _ = 1, lines do
        local t = frame:CreateTexture(nil, layer or "ARTWORK")
        local y = -(2 + Rand() * (height - 5))
        local x1 = 2 + Rand() * (width * 0.4)
        local x2 = -(2 + Rand() * (width * 0.4))
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", x1, y)
        t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x2, y)
        t:SetHeight(1)
        t:SetColorTexture(0.10, 0.05, 0.02, 0.10 + Rand() * 0.10)
    end
end

local function Look(self)
    local fill = C.normal
    local txt = C.text
    if not self.isEnabled then
        fill, txt = C.disabled, C.textOff
    elseif self.down then
        fill = C.down
    elseif self.selected then
        fill = C.selected
    elseif self.hover then
        fill = self.hoverColor or C.hover
    end
    Paint(self.fill, fill)
    self.label:SetTextColor(txt[1], txt[2], txt[3])
    if self.selected and self.isEnabled then self.accent:Show() else self.accent:Hide() end
    self.label:ClearAllPoints()
    self.label:SetPoint("CENTER", self, "CENTER", self.down and 1 or 0, self.down and -1 or 0)
end

-- Holz-Knopf. API wie bei Blizzard-Knöpfen:
--   SetText / GetText / Enable / Disable / LockHighlight (= gewählt) / UnlockHighlight
-- Verschieben nur, wenn die Fenster nicht festgesetzt sind (Einstellungen: "Fenster festsetzen")
function UI.DragStart(frame)
    if SM.db and SM.db.ui and SM.db.ui.locked then return end
    frame:StartMoving()
end

-- Ein Eingabefeld behält in WoW den Fokus, bis man Enter/Escape drückt - dann landen Tasten
-- wie M (Karte) im Feld. Bei Klicks woanders im Fenster geben wir den Fokus deshalb ab.
function UI.DropFocus()
    local fb = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if fb and fb.ClearFocus then fb:ClearFocus() end
end

function UI.Button(parent, name, width, height, text)
    local b = CreateFrame("Button", name, parent)
    b:SetSize(width, height)
    b.isEnabled, b.hover, b.down, b.selected, b.hoverColor = true, false, false, false, false

    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(b)
    Paint(border, C.border)

    local fill = b:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.fill = fill

    UI.AddGrain(b, width, height)

    local top = b:CreateTexture(nil, "OVERLAY")
    top:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
    top:SetHeight(1)
    Paint(top, C.light, 0.55)

    local bottom = b:CreateTexture(nil, "OVERLAY")
    bottom:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
    bottom:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    bottom:SetHeight(1)
    Paint(bottom, C.dark, 0.60)

    local accent = b:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 2)
    accent:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    accent:SetHeight(3)
    Paint(accent, C.accent)
    accent:Hide()
    b.accent = accent

    local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetWidth(width - 8)
    label:SetHeight(height)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    label:SetShadowColor(0, 0, 0, 0.9)
    label:SetShadowOffset(1, -1)
    b.label = label

    -- Methoden des Blizzard-Knopfes so überschreiben, dass das Aussehen mitzieht
    local origEnable, origDisable = b.Enable, b.Disable
    function b:Enable() origEnable(self); self.isEnabled = true; Look(self) end
    function b:Disable() origDisable(self); self.isEnabled = false; self.down = false; Look(self) end
    function b:LockHighlight() self.selected = true; Look(self) end
    function b:UnlockHighlight() self.selected = false; Look(self) end
    function b:SetText(t) self.caption = tostring(t or ""); self.label:SetText(self.caption) end
    function b:GetText() return self.caption or "" end

    -- Hover-Look bleibt, auch wenn ein Aufrufer später eigene OnEnter/OnLeave setzt (z. B. ein
    -- Tooltip): SetScript für diese beiden wird umhüllt.
    local origSetScript = b.SetScript
    function b:SetScript(event, fn)
        if event == "OnEnter" then
            return origSetScript(self, event, function(btn, ...)
                btn.hover = true; Look(btn)
                if fn then fn(btn, ...) end
            end)
        elseif event == "OnLeave" then
            return origSetScript(self, event, function(btn, ...)
                btn.hover = false; btn.down = false; Look(btn)
                if fn then fn(btn, ...) end
            end)
        end
        return origSetScript(self, event, fn)
    end
    b:SetScript("OnEnter")
    b:SetScript("OnLeave")
    b:SetScript("OnMouseDown", function(self) if self.isEnabled then self.down = true; Look(self) end end)
    b:SetScript("OnMouseUp", function(self) self.down = false; Look(self) end)

    b:SetText(text or "")
    Look(b)
    return b
end

-- Schließen-Knopf (X) im selben Stil, beim Überfahren dunkelrot.
function UI.CloseButton(parent, onClick)
    local b = UI.Button(parent, nil, 22, 22, "X")
    b.isClose = true -- zählt beim Mitlernen der Fenster als "zugemacht", nicht als "benutzt"
    b.hoverColor = C.closeHover
    b:SetScript("OnClick", onClick or function() parent:Hide() end)
    return b
end

-- Flache Fläche mit dunklem Rand (z. B. für das Quest-Auswahlfenster).
function UI.Panel(parent, name, fillColor)
    local f = CreateFrame("Frame", name, parent)
    local border = f:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(f)
    Paint(border, C.border)
    local fill = f:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    Paint(fill, fillColor or M.colors.parchment)
    f.fill = fill
    return f
end

---------------------------------------------------------------------------
-- Rechtsklick-Menü auf Pergament: UI.Menu(owner, title, entries)
--   entries = { { text = "...", fn = function() end, disabled = true/false, tip = "..." }, ... }
-- Erscheint an der Maus, schließt sich bei einem Klick daneben, mit Escape oder wenn das Fenster
-- darunter zugeht. Ein Eintrag schließt das Menü und führt dann seine Aufgabe aus.
---------------------------------------------------------------------------
local MENU_ROW, MENU_PAD = 20, 6
function UI.Menu(owner, title, entries)
    local m = UI.menu
    if not m then
        m = UI.Panel(UIParent, "SocializeMeForeverMenu")
        UI.menu = m
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetClampedToScreen(true)
        m:EnableMouse(true)
        m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        m.title:SetPoint("TOPLEFT", MENU_PAD + 2, -MENU_PAD)
        m.title:SetJustifyH("LEFT")
        m.title:SetWordWrap(false)
        m.title:SetTextColor(M.colors.soft[1], M.colors.soft[2], M.colors.soft[3])
        m.title:SetShadowOffset(0, 0)
        m.rows = {}
        -- Klick irgendwo daneben schließt das Menü. Sicher ist sicher: das Ereignis und zusätzlich
        -- ein Blick auf die Maustasten (falls ein Client das Ereignis nicht kennt).
        pcall(m.RegisterEvent, m, "GLOBAL_MOUSE_DOWN")
        m:SetScript("OnEvent", function(fr)
            if fr:IsShown() and not fr:IsMouseOver() then fr:Hide() end
        end)
        m:SetScript("OnUpdate", function(fr)
            if fr.owner and not fr.owner:IsVisible() then fr:Hide() return end
            if IsMouseButtonDown and not fr:IsMouseOver()
                and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
                fr:Hide()
            end
        end)
        tinsert(UISpecialFrames, "SocializeMeForeverMenu")
    end
    m.owner = owner
    local hasTitle = title and title ~= ""
    m.title:SetText(hasTitle and title or "")
    local top = MENU_PAD + (hasTitle and 16 or 0)
    local width = hasTitle and (m.title:GetStringWidth() or 0) + 2 * MENU_PAD + 4 or 0
    for i, e in ipairs(entries) do
        local r = m.rows[i]
        if not r then
            r = CreateFrame("Button", nil, m)
            r:SetHeight(MENU_ROW)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT")
            r.hl:SetAllPoints(r)
            r.hl:SetColorTexture(unpack(M.colors.hover))
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            r.text:SetPoint("LEFT", 8, 0)
            r.text:SetJustifyH("LEFT")
            r.text:SetShadowOffset(0, 0)
            r:SetScript("OnClick", function(btn)
                local fn = btn.entry and not btn.entry.disabled and btn.entry.fn
                m:Hide()
                if fn then fn() end
            end)
            r:SetScript("OnEnter", function(btn)
                local tip = btn.entry and btn.entry.tip
                if not tip then return end
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                GameTooltip:AddLine(tip, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            m.rows[i] = r
        end
        r.entry = e
        r.text:SetText(e.text or "")
        local c = e.disabled and M.colors.off or M.colors.ink
        r.text:SetTextColor(c[1], c[2], c[3])
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -(top + (i - 1) * MENU_ROW))
        r:SetPoint("TOPRIGHT", m, "TOPRIGHT", -1, -(top + (i - 1) * MENU_ROW))
        r:Show()
        width = math.max(width, (r.text:GetStringWidth() or 0) + 24)
    end
    for i = #entries + 1, #m.rows do m.rows[i]:Hide(); m.rows[i].entry = nil end
    m.entries = entries
    m:SetSize(math.max(140, math.ceil(width)), top + #entries * MENU_ROW + MENU_PAD)
    -- an der Maus öffnen
    local x, y = 0, 0
    if GetCursorPosition then x, y = GetCursorPosition() end
    local sc = UIParent:GetEffectiveScale() or 1
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / sc - 4, y / sc + 4)
    m:Show()
    m:Raise()
    return m
end

---------------------------------------------------------------------------
-- Eingabefeld: heller Grund, dunkler Holzrand, beim Tippen goldener Rand
---------------------------------------------------------------------------
function UI.EditBox(parent, name, width, height)
    local e = CreateFrame("EditBox", name, parent)
    e:SetSize(width, height or 24)
    e:SetAutoFocus(false)
    e:SetFontObject(ChatFontNormal)
    e:SetTextInsets(6, 6, 0, 0)
    local ink = M.colors.ink
    e:SetTextColor(ink[1], ink[2], ink[3])

    local border = e:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(e)
    Paint(border, C.border)
    local fill = e:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", e, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", -1, 1)
    Paint(fill, M.colors.field)
    -- feine Innenkante oben, wie bei den Knöpfen
    local shade = e:CreateTexture(nil, "ARTWORK")
    shade:SetPoint("TOPLEFT", e, "TOPLEFT", 1, -1)
    shade:SetPoint("TOPRIGHT", e, "TOPRIGHT", -1, -1)
    shade:SetHeight(2)
    shade:SetColorTexture(unpack(M.colors.shade))
    e.border = border

    -- HookScript, damit Skripte der Aufrufer (SetScript) nicht überschrieben werden
    e:HookScript("OnEditFocusGained", function() Paint(border, C.accent) end)
    e:HookScript("OnEditFocusLost", function() Paint(border, C.border) end)
    return e
end

---------------------------------------------------------------------------
-- Häkchen: Holzquadrat, gewählt = goldene Füllung. Das Label steht rechts daneben.
---------------------------------------------------------------------------
function UI.CheckBox(parent, name, labelText)
    local cb = CreateFrame("CheckButton", name, parent)
    cb:SetSize(20, 20)

    local border = cb:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(cb)
    Paint(border, C.border)
    local fill = cb:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", cb, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -1, 1)
    Paint(fill, C.normal)
    UI.AddGrain(cb, 20, 20)
    local mark = cb:CreateTexture(nil, "OVERLAY")
    mark:SetPoint("TOPLEFT", cb, "TOPLEFT", 5, -5)
    mark:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -5, 5)
    Paint(mark, C.accent)
    mark:Hide()
    cb.fill, cb.mark = fill, mark

    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    label:SetJustifyH("LEFT")
    label:SetShadowOffset(0, 0) -- schwarzer Schatten verwischt dunklen Text auf Pergament
    local ink = M.colors.ink
    label:SetTextColor(ink[1], ink[2], ink[3])
    cb.label = label

    function cb:Sync()
        local on = self:GetChecked() and true or false
        if on then self.mark:Show() else self.mark:Hide() end
        Paint(self.fill, self.hover and C.hover or C.normal)
    end
    local origSetChecked = cb.SetChecked
    function cb:SetChecked(v) origSetChecked(self, v); self:Sync() end

    function cb:SetLabel(text)
        self.label:SetText(text or "")
        -- Klick auf den Text zählt auch (wie bei der Blizzard-Vorlage)
        local w = self.label.GetStringWidth and self.label:GetStringWidth()
        if type(w) == "number" then self:SetHitRectInsets(0, -(w + 8), 0, 0) end
    end

    cb.hover = false
    cb:HookScript("OnClick", function(self) self:Sync() end)
    -- Setzt jemand später ein eigenes OnClick, soll das Häkchen trotzdem mitziehen
    -- (SetScript würde den Hook sonst ersetzen).
    local origSetScript = cb.SetScript
    function cb:SetScript(name, fn)
        if name == "OnClick" and fn then
            return origSetScript(self, name, function(btn, ...) btn:Sync(); return fn(btn, ...) end)
        end
        return origSetScript(self, name, fn)
    end
    cb:HookScript("OnEnter", function(self) self.hover = true; self:Sync() end)
    cb:HookScript("OnLeave", function(self) self.hover = false; self:Sync() end)

    cb:SetLabel(labelText)
    cb:Sync()
    return cb
end

---------------------------------------------------------------------------
-- Regler: schmale Holzschiene, Griff aus hellerem Holz. Text oben, Grenzwerte unten.
---------------------------------------------------------------------------
function UI.Slider(parent, name, width)
    local s = CreateFrame("Slider", name, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 16)

    local trackBorder = s:CreateTexture(nil, "BACKGROUND")
    trackBorder:SetPoint("LEFT", s, "LEFT", 0, 0)
    trackBorder:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    trackBorder:SetHeight(6)
    Paint(trackBorder, C.border)
    local track = s:CreateTexture(nil, "BORDER")
    track:SetPoint("TOPLEFT", trackBorder, "TOPLEFT", 1, -1)
    track:SetPoint("BOTTOMRIGHT", trackBorder, "BOTTOMRIGHT", -1, 1)
    Paint(track, C.normal)

    local thumb = s:CreateTexture(nil, "OVERLAY")
    Paint(thumb, C.accent)
    thumb:SetSize(10, 18)
    s:SetThumbTexture(thumb)
    s.thumb = thumb

    local ink = M.colors.ink
    local function Text(point, rel, relPoint, x, y)
        local fs = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint(point, s, relPoint, x, y)
        fs:SetTextColor(ink[1], ink[2], ink[3])
        fs:SetShadowOffset(0, 0)
        return fs
    end
    s.label = Text("BOTTOM", s, "TOP", 0, 4)
    s.lowText = Text("TOPLEFT", s, "BOTTOMLEFT", 0, -2)
    s.highText = Text("TOPRIGHT", s, "BOTTOMRIGHT", 0, -2)
    return s
end

---------------------------------------------------------------------------
-- Bereich zum Scrollen mit dem Mausrad, rechts eine schmale Holzleiste als Anzeige.
-- Gibt scroll (ScrollFrame) und child (Inhalt) zurück. Höhe des Inhalts: child:SetHeight().
-- Die Leiste erscheint nur, wenn der Inhalt nicht ganz hineinpasst.
---------------------------------------------------------------------------
local WHEEL_STEP = 40

function UI.ScrollArea(parent, name)
    local scroll = CreateFrame("ScrollFrame", name, parent)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(10, 10)
    scroll:SetScrollChild(child)
    scroll.child = child

    local track = CreateFrame("Frame", nil, parent)
    track:SetWidth(6)
    track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
    track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
    local trackTex = track:CreateTexture(nil, "BACKGROUND")
    trackTex:SetAllPoints(track)
    Paint(trackTex, C.border, 0.30)
    local thumb = track:CreateTexture(nil, "ARTWORK")
    thumb:SetWidth(6)
    Paint(thumb, C.normal)
    scroll.track, scroll.thumb = track, thumb

    local function Num(v) return type(v) == "number" and v or 0 end

    function scroll:MaxScroll()
        return math.max(0, Num(child:GetHeight()) - Num(self:GetHeight()))
    end

    function scroll:UpdateThumb()
        local max = self:MaxScroll()
        if max <= 0 then
            track:Hide()
            if Num(self:GetVerticalScroll()) > 0 then self:SetVerticalScroll(0) end
            return
        end
        track:Show()
        local h = Num(self:GetHeight())
        local th = math.max(20, h * h / (h + max))
        local pos = math.min(1, Num(self:GetVerticalScroll()) / max)
        thumb:ClearAllPoints()
        thumb:SetHeight(th)
        thumb:SetPoint("TOPLEFT", track, "TOPLEFT", 0, -pos * (h - th))
    end

    function scroll:ScrollTo(value)
        self:SetVerticalScroll(math.max(0, math.min(value, self:MaxScroll())))
        self:UpdateThumb()
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        self:ScrollTo(Num(self:GetVerticalScroll()) - (delta or 0) * WHEEL_STEP)
    end)
    scroll:SetScript("OnSizeChanged", function(self) self:UpdateThumb() end)
    scroll:SetScript("OnShow", function(self) self:UpdateThumb() end)
    return scroll, child
end
