local ADDON, SM = ...
local L = SM.L
local M = SM.Media
local UI = SM.UI
local Q = SM.QuestInfo
local Tip = SM.BeaconTip

local Window = {}
SM.Window = Window

local ROWS, ROW_H = 5, 36
local PICK_ROWS, PICK_H = 6, 22
local WIDTH, HEIGHT = 520, 572   -- test8b: Formular kompakter, Fenster niedriger
local KIND_ORDER = { "quest", "campfire" }
-- Fünf Tabs: zusammen spielen (Treffpunkte), spontan plaudern (Instant), Zeit schön verbringen
-- (Orte), Leute wiederfinden (Kontakte), zuletzt die Optionen (mit der Hilfe).
-- "Nicht stören" und "Offenes Ohr" sitzen in der Titelleiste.
local TABS = { "beacons", "instant", "places", "contacts", "settings" }
local TAB_ROW, TAB_GAP, TAB_PAD = 476, 4, 22
local TIP_H = 58                -- Erst-Tipp über dem Inhalt (das Fenster wird so lange höher)
local ink, good, bad = M.colors.ink, M.colors.good, M.colors.bad

Window.offset = 0
Window.kind = "quest"

---------------------------------------------------------------------------
-- Kleine Bausteine
---------------------------------------------------------------------------
local uid = 0
local function Name(prefix)
    uid = uid + 1
    return "SMForever" .. prefix .. uid
end

local function MakeText(parent, font, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    color = color or ink
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    fs:SetShadowOffset(0, 0) -- schwarzer Schatten verwischt dunklen Text auf Pergament
    return fs
end

-- Name in der Sprache des Addons (ZoneNames.lua), sonst wie im Spiel
local function MapName(mapID)
    return SM:MapName(mapID)
end

local function SetHex(tex, hex, alpha)
    tex:SetColorTexture(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255, alpha or 1)
end

local function Header(parent, text, x, y)
    local fs = MakeText(parent, "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Separator(parent, y)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    t:SetHeight(1)
    t:SetColorTexture(unpack(M.colors.line))
    return t
end

-- Häkchen im Holz-Look. getter() liefert den Zustand, setter(v) speichert.
local function MakeCheck(parent, label, x, y, getter, setter)
    local cb = UI.CheckBox(parent, Name("Check"), label)
    cb:SetPoint("TOPLEFT", x + 2, y - 2)
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
    end)
    function cb:Refresh() self:SetChecked(getter() and true or false) end
    return cb
end

-- Gibt es nur in WoW Forever: in Classic ausgegraut, mit "Nur in WoW Forever" und Erklärung
local GREY = M.colors.grey
local function ForeverOnly(cb, tip)
    local base, label = cb.Refresh, cb.label:GetText() or ""
    function cb:Refresh()
        if base then base(self) end
        local on = SM:IsForever()
        if on then self:Enable() else self:Disable() end
        self:SetAlpha(on and 1 or 0.6)
        local c = on and M.colors.ink or GREY
        self.label:SetTextColor(c[1], c[2], c[3])
        self:SetLabel(on and label or (label .. " - " .. L.FOREVER_ONLY))
    end
    -- auch ausgegraut soll der Tooltip erscheinen (sonst sieht man nicht, warum)
    if cb.SetMotionScriptsWhileDisabled then cb:SetMotionScriptsWhileDisabled(true) end
    -- HookScript, damit der Hover-Effekt des Kästchens bleibt
    cb:HookScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:AddLine(SM:IsForever() and label or L.FOREVER_ONLY_TITLE, 1, 0.82, 0)
        if tip then GameTooltip:AddLine(tip, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    cb:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return cb
end

local function MakeSlider(parent, x, y, minV, maxV, step, labelKey, tbl, key, onChange)
    local s = UI.Slider(parent, Name("Slider"), 210)
    s:SetPoint("TOPLEFT", x, y)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s.lowText:SetText(minV)
    s.highText:SetText(maxV)

    local function Show(value) s.label:SetText(L[labelKey]:format(value)) end

    s:SetScript("OnValueChanged", function(self, value)
        if self.updating then return end
        value = math.floor(value / step + 0.5) * step
        tbl[key] = value
        Show(value)
        if onChange then onChange(value) end
    end)
    function s:Refresh()
        self.updating = true
        self:SetValue(tbl[key])
        Show(tbl[key])
        self.updating = false
    end
    return s
end

-- Bausteine auch für UI/InstantPanel.lua, UI/ContactsPanel.lua und UI/PlacesPanel.lua
Window.H = { Name = Name, MakeText = MakeText, Header = Header, Separator = Separator,
             MakeCheck = MakeCheck, SetHex = SetHex, MapName = MapName, ForeverOnly = ForeverOnly }

---------------------------------------------------------------------------
-- Tab „Beacons“
---------------------------------------------------------------------------
local LIST_TOP = 30 -- Platz für die Filterleiste über der Liste

-- Haupttext einer Zeile: Quest-Name (in deiner Sprache, wenn dein Spiel ihn kennt) und Freitext.
local QuestName = Tip.QuestName

local function RowTitle(b, byID)
    if b.questID then
        local qn = QuestName(b, byID)
        if qn and qn ~= "" then
            if b.title ~= "" and b.title ~= b.questName and b.title ~= qn then
                return qn .. "  " .. SM.Hex("5A3A10") .. "- " .. b.title .. "|r"
            end
            return qn
        end
    end
    return b.title
end

local ProgressColored = Tip.ProgressColored

function Window:ShowBeaconTooltip(row)
    if not row.beacon then return end
    self.tipRow = row
    Tip:Show(row, row.beacon, "ANCHOR_RIGHT", "row")
end

-- Klick (links oder rechts) = Auswahl mit "Weg zeigen" ganz oben (wie auf der Karte; UI/BeaconTip.lua)
local function RowStatus(text, ok) Window:SetStatus(text, ok and good or ink) end
local function RowClick(row)
    local b = row.beacon
    if not b then return end
    Tip:Menu(row, b, RowStatus)
end

function Window:BuildBeaconPanel(parent)
    local P = CreateFrame("Frame", nil, parent)
    P:SetAllPoints(parent)
    P:Hide()
    self.beaconPanel = P

    -- Filterleiste: nur meine Zone <-> alle Zonen
    self.filterBtn = UI.Button(P, Name("Filter"), 300, 24, "")
    self.filterBtn:SetPoint("TOPLEFT", P, "TOPLEFT", 0, 0)
    self.filterBtn:SetScript("OnClick", function()
        local db = SM.db.beacon
        db.zoneFilter = (db.zoneFilter == "own") and "all" or "own"
        Window.offset = 0
        Window:RefreshList()
    end)

    -- Liste
    self.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, P)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", P, "TOPLEFT", 0, -LIST_TOP - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", P, "TOPRIGHT", 0, -LIST_TOP - (i - 1) * ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(row)
        hl:SetColorTexture(unpack(M.colors.hover))

        -- Farbbalken links: bei Quests dein eigener Stand, sonst die Farbe der Art
        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
        row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
        row.bar:SetWidth(4)

        row.prog = MakeText(row, "GameFontNormal")
        row.prog:SetPoint("TOPRIGHT", -6, -3)
        row.prog:SetWidth(130)
        row.prog:SetHeight(14)
        row.prog:SetJustifyH("RIGHT")
        row.prog:SetWordWrap(false)

        row.line1 = MakeText(row, "GameFontNormal")
        row.line1:SetPoint("TOPLEFT", 12, -3)
        row.line1:SetPoint("TOPRIGHT", row.prog, "TOPLEFT", -6, 0)
        row.line1:SetHeight(14)
        row.line1:SetWordWrap(false)
        row.line2 = MakeText(row, "GameFontNormalSmall")
        row.line2:SetPoint("TOPLEFT", 12, -19)
        row.line2:SetPoint("TOPRIGHT", -6, -19)
        row.line2:SetHeight(12)
        row.line2:SetWordWrap(false)

        local sep = row:CreateTexture(nil, "ARTWORK")
        sep:SetPoint("BOTTOMLEFT", 0, 0)
        sep:SetPoint("BOTTOMRIGHT", 0, 0)
        sep:SetHeight(1)
        sep:SetColorTexture(unpack(M.colors.line))

        row:SetScript("OnEnter", function(self) Window:ShowBeaconTooltip(self) end)
        row:SetScript("OnLeave", function() Window.tipRow = nil; Tip:Hide() end)
        row:SetScript("OnClick", RowClick)
        row:Hide()
        self.rows[i] = row
    end

    self.emptyText = MakeText(P, "GameFontNormal")
    self.emptyText:SetPoint("TOP", P, "TOP", 0, -LIST_TOP - 50)
    self.emptyText:SetWidth(400)
    self.emptyText:SetJustifyH("CENTER")
    self.emptyText:SetText(L.LIST_EMPTY)

    local listBottom = LIST_TOP + ROWS * ROW_H
    -- Seitenangabe oben rechts neben dem Filter, darunter bleibt Platz für die Bedienung
    self.pageText = MakeText(P, "GameFontNormalSmall")
    self.pageText:SetPoint("TOPRIGHT", P, "TOPRIGHT", -4, -7)
    self.pageText:SetWidth(170)
    self.pageText:SetJustifyH("RIGHT")

    -- Während du wartest (test8b, statt des Warte-Tipp-Fensters): unter der Liste eine Idee mit
    -- "Weg zeigen" - nur solange dein Treffpunkt läuft und noch niemand kommt. Klick auf die Zeile
    -- zeigt die nächste Idee. (Die Bedienung der Liste steht im Tooltip jeder Zeile.)
    local wl = CreateFrame("Button", nil, P)
    wl:SetPoint("TOPLEFT", P, "TOPLEFT", 0, -listBottom - 1)
    wl:SetSize(470, 25)
    wl.icon = wl:CreateTexture(nil, "ARTWORK")
    wl.icon:SetSize(16, 16)
    wl.icon:SetPoint("LEFT", wl, "LEFT", 2, 0)
    wl.text = MakeText(wl, "GameFontNormalSmall", M.colors.soft)
    wl.text:SetPoint("LEFT", wl, "LEFT", 22, 0)
    wl.text:SetWidth(334)
    wl.go = UI.Button(wl, Name("WaitGo"), 104, 20, L.WAIT_GO)
    wl.go:SetPoint("RIGHT", wl, "RIGHT", 0, 0)
    wl.go:SetScript("OnClick", function() Window:WaitGo() end)
    wl:SetScript("OnClick", function()
        if SM.Chill then SM.Chill:NextWaitIdea() end
        Window:RefreshWaitLine()
    end)
    wl:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:AddLine(L.WAIT_TITLE, 1, 0.82, 0)
        GameTooltip:AddLine(L.WAIT_LINE_TT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    wl:SetScript("OnLeave", function() GameTooltip:Hide() end)
    wl:Hide()
    self.waitLine = wl

    P:EnableMouseWheel(true)
    P:SetScript("OnMouseWheel", function(_, delta)
        Window.offset = math.max(0, Window.offset - delta)
        Window:RefreshList()
    end)

    Separator(P, -listBottom - 28)

    -- Formular
    local y0 = -listBottom - 38
    Header(P, L.FORM_TITLE, 0, y0)

    self.kindButtons = {}
    for i, kind in ipairs(KIND_ORDER) do
        local kw = math.floor((468 - (#KIND_ORDER - 1) * 5) / #KIND_ORDER)
        local b = UI.Button(P, Name("Kind"), kw, 24, L["KIND_" .. kind])
        b:SetPoint("TOPLEFT", (i - 1) * (kw + 5), y0 - 26)
        b:SetScript("OnClick", function() Window:SelectKind(kind) end)
        b:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:AddLine(L["KIND_" .. kind], 1, 0.82, 0)
            GameTooltip:AddLine(L["KIND_TT_" .. kind], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.kindButtons[kind] = b
    end

    -- Quest aus dem eigenen Questlog (nur bei Quest-Beacons)
    local ql = MakeText(P, "GameFontNormal")
    ql:SetPoint("TOPLEFT", 0, y0 - 62)
    ql:SetText(L.FORM_QUEST)
    self.questBtn = UI.Button(P, Name("Quest"), 410, 24, L.QUEST_BTN)
    self.questBtn:SetPoint("TOPLEFT", 60, y0 - 56)
    self.questBtn:SetScript("OnClick", function() Window:ToggleQuestPicker() end)

    local lbl = MakeText(P, "GameFontNormal")
    lbl:SetPoint("TOPLEFT", 0, y0 - 94)
    lbl:SetText(L.FORM_TEXT)

    local eb = UI.EditBox(P, Name("Edit"), 404, 24)
    eb:SetPoint("TOPLEFT", 62, y0 - 87)
    eb:SetMaxLetters(40)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Window:Submit() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    self.editBox = eb

    -- Sprachchat und "Das passt zu mir" als zwei Auswahl-Knöpfe in einer Zeile (test8b, kompakter).
    -- Sprachchat nur dort, wo es den Blizzard-Sprachchat gibt; beides wird gemerkt.
    self.voiceLevel = 0
    local yRow = y0 - 116
    local vb = UI.Button(P, Name("VoiceSel"), 206, 22, "")
    vb:SetPoint("TOPLEFT", 0, yRow)
    vb:SetScript("OnClick", function(btn) Window:VoiceMenu(btn) end)
    vb:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:AddLine(L.FORM_VOICE, 1, 0.82, 0)
        GameTooltip:AddLine(L["TT_VOICE_" .. (Window.voiceLevel or 0)], 1, 1, 1, true)
        GameTooltip:AddLine(L.FORM_VOICE_DISCORD, 0.7, 0.7, 0.7, true) -- 1.3.0: Discord gibt es bei Instant
        GameTooltip:Show()
    end)
    vb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.voiceBtn = vb
    local tb = UI.Button(P, Name("TagsSel"), 264, 22, "")
    tb:SetScript("OnClick", function(btn) Window:TagsMenu(btn) end)
    tb:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:AddLine(L.FORM_TAGS, 1, 0.82, 0)
        GameTooltip:AddLine(L.FORM_TAGS_TT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.tagsBtn = tb
    if C_VoiceChat then
        tb:SetPoint("TOPLEFT", 212, yRow)
        self:SelectVoice(SM.Social.VoiceLevel(SM.db.beacon.voice))
    else
        vb:Hide()
        tb:SetPoint("TOPLEFT", 0, yRow)
    end
    self:RefreshTags()
    yRow = yRow - 30

    self.lightBtn = UI.Button(P, Name("Light"), 170, 26, L.FORM_LIGHT)
    self.lightBtn:SetPoint("TOPLEFT", 0, yRow)
    self.lightBtn:SetScript("OnClick", function() Window:Submit() end)
    self.lightBtn:SetScript("OnEnter", function(btn)
        if SM.Beacon:LevelOK() then return end
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:AddLine(L.FORM_LEVEL:format(SM.Guard.MIN_BEACON_LEVEL), 1, 0.82, 0)
        GameTooltip:AddLine(L.FORM_LEVEL_TT:format(SM.Guard.MIN_BEACON_LEVEL), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.lightBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.cancelBtn = UI.Button(P, Name("Cancel"), 190, 26, L.FORM_CANCEL)
    self.cancelBtn:SetPoint("TOPLEFT", 176, yRow)

    -- Spickzettel für den Sprachchat (Sätze zum Vorlesen + Benimmregeln)
    self.voiceCardBtn = UI.Button(P, Name("VoiceCard"), 104, 26, L.VOICE_CARD_BTN)
    self.voiceCardBtn:SetPoint("TOPLEFT", 370, yRow)
    self.voiceCardBtn:SetScript("OnClick", function() SM.VoiceCard:Toggle() end)
    self.voiceCardBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:AddLine(L.VOICE_CARD_TITLE, 1, 0.82, 0)
        GameTooltip:AddLine(L.VOICE_CARD_TT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.voiceCardBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.cancelBtn:SetScript("OnClick", function()
        local n = SM.Beacon:CancelOwn()
        Window:SetStatus(n > 0 and L.BEACON_CANCELLED or L.BEACON_NOCANCEL, good)
    end)

    self.status = MakeText(P, "GameFontNormal")
    self.status:SetPoint("TOPLEFT", 0, yRow - 36)
    self.status:SetWidth(470)
    self.status:SetHeight(30)
    self.status:SetJustifyV("TOP")
    self.status:SetText("")

    self:BuildQuestPicker()
    self:SelectKind("quest")
end

---------------------------------------------------------------------------
-- Quest-Auswahl: kleine Liste mit den Quests aus dem eigenen Questlog
---------------------------------------------------------------------------
function Window:BuildQuestPicker()
    local pop = UI.Panel(self.frame, "SocializeMeForeverQuestPicker", M.colors.panel)
    pop:SetSize(410, PICK_ROWS * PICK_H + 8)
    pop:SetPoint("TOPLEFT", self.questBtn, "BOTTOMLEFT", 0, -2)
    pop:SetFrameLevel(self.frame:GetFrameLevel() + 40)
    pop:EnableMouse(true)
    pop:EnableMouseWheel(true)
    pop:Hide()
    self.picker = pop
    pop.offset = 0
    pop.rows = {}

    for i = 1, PICK_ROWS do
        local row = CreateFrame("Button", nil, pop)
        row:SetHeight(PICK_H)
        row:SetPoint("TOPLEFT", pop, "TOPLEFT", 4, -4 - (i - 1) * PICK_H)
        row:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -4, -4 - (i - 1) * PICK_H)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(row)
        hl:SetColorTexture(unpack(M.colors.hover))
        row.text = MakeText(row, "GameFontNormal")
        row.text:SetPoint("LEFT", 6, 0)
        row.text:SetPoint("RIGHT", -6, 0)
        row.text:SetHeight(PICK_H)
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", function(self) if self.entry then Window:PickQuest(self.entry) end end)
        row:Hide()
        pop.rows[i] = row
    end

    pop:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, #(self.list or {}) - PICK_ROWS)
        self.offset = math.min(max, math.max(0, self.offset - delta))
        Window:RefreshPicker()
    end)
end

function Window:RefreshPicker()
    local pop = self.picker
    if not pop then return end
    for i = 1, PICK_ROWS do
        local row, e = pop.rows[i], (pop.list or {})[pop.offset + i]
        row.entry = e
        if e then
            if e.none then
                row.text:SetText(L.QUEST_NONE_ENTRY)
            else
                local progress = Q.ProgressText(e.done, e.total, e.state)
                local col = SM.Hex((e.state == Q.STATE_READY) and "2A6F2A" or "5A3A10")
                row.text:SetText(("[%d] %s  %s(%s)|r"):format(e.level or 0, e.title, col, progress))
            end
            row:Show()
        else
            row:Hide()
        end
    end
end

function Window:ToggleQuestPicker()
    local pop = self.picker
    if pop:IsShown() then pop:Hide() return end
    local list = Q:ScanLog()
    if #list == 0 then
        self:SetStatus(L.QUEST_LOG_EMPTY, ink)
        return
    end
    pop.list = { { none = true } }
    for _, e in ipairs(list) do pop.list[#pop.list + 1] = e end
    pop.offset = 0
    self:RefreshPicker()
    pop:Show()
end

function Window:PickQuest(entry)
    self.questChosen = true -- selbst gewählt (auch "keine Quest"): nicht mehr von selbst vorbelegen
    if entry.none then
        self.questID, self.questName = nil, nil
    else
        self.questID, self.questName = entry.questID, entry.title
    end
    self.picker:Hide()
    self:UpdateQuestButton()
end

function Window:UpdateQuestButton()
    if not self.questBtn then return end
    if self.kind ~= "quest" then
        self.questBtn:Disable()
        self.questBtn:SetText(L.QUEST_ONLY)
    else
        self.questBtn:Enable()
        self.questBtn:SetText(self.questName or L.QUEST_BTN)
    end
end

function Window:SelectKind(kind)
    self.kind = kind
    for k, b in pairs(self.kindButtons) do
        if k == kind then b:LockHighlight() else b:UnlockHighlight() end
    end
    if kind ~= "quest" then self.questID, self.questName = nil, nil end
    if self.picker then self.picker:Hide() end
    self:UpdateQuestButton()
    if kind == "quest" and self.frame and self.frame:IsShown() then self:PrefillQuest() end
end

-- Formular: die Quest mit dem letzten Fortschritt vorschlagen (solange du nichts selbst gewählt hast)
function Window:PrefillQuest()
    if self.kind ~= "quest" or self.questChosen or self.questID then return end
    local e = Q:LastProgress()
    if e then
        self.questID, self.questName = e.questID, e.title
        self:UpdateQuestButton()
    end
end

function Window:SelectVoice(level)
    self.voiceLevel = level
    if SM.db then SM.db.beacon.voice = level end
    if self.voiceBtn then self.voiceBtn:SetText(L.FORM_VOICE_SEL:format(L["FORM_VOICE_SHORT_" .. level] or "")) end
end

-- Auswahl Sprachchat: Nur Text / Zuhören reicht / Sprachchat (der gewählte mit Punkt davor)
local VOICE_ORDER = { 0, 2, 1 }
function Window:VoiceMenu(btn)
    local entries = {}
    for _, level in ipairs(VOICE_ORDER) do
        entries[#entries + 1] = {
            text = ((self.voiceLevel == level) and "• " or "   ") .. L["FORM_VOICE_" .. level],
            tip = (level == 1) and (L.TT_VOICE_1 .. "\n" .. L.FORM_VOICE_DISCORD) or L["TT_VOICE_" .. level],
            fn = function()
                Window:SelectVoice(level)
                -- läuft schon ein eigener Treffpunkt, ändert sich seine Stufe gleich mit
                local ok, msg = SM.Beacon:SetOwnVoice(level)
                if msg then Window:SetStatus(msg, ok and good or ink) end
            end,
        }
    end
    return SM.UI.Menu(btn, L.FORM_VOICE, entries)
end

-- "Das passt zu mir": eher ruhig, neu, hilft gern - jeder Klick schaltet einen um, die Auswahl
-- bleibt dafür offen
local TAGS = { { "quiet", "QUIET_SHORT", "SET_QUIET" }, { "newbie", "NEW_SHORT", "SET_NEWBIE" }, { "helper", "HELPER_SHORT", "SET_HELPER" } }
Window.TAGS = TAGS
function Window:RefreshTags()
    if not self.tagsBtn then return end
    local soc, on = SM.db.social, {}
    for _, t in ipairs(TAGS) do if soc[t[1]] then on[#on + 1] = L[t[2]] end end
    self.tagsBtn:SetText(L.FORM_TAGS_SEL:format(#on > 0 and table.concat(on, ", ") or L.FORM_TAGS_NONE))
end

function Window:TagsMenu(btn)
    local soc = SM.db.social
    local entries = {}
    for _, t in ipairs(TAGS) do
        entries[#entries + 1] = {
            text = (soc[t[1]] and "• " or "   ") .. L[t[2]],
            tip = L[t[3]],
            fn = function()
                soc[t[1]] = not soc[t[1]]
                Window:RefreshTags()
                Window:TagsMenu(btn)
            end,
        }
    end
    return SM.UI.Menu(btn, L.FORM_TAGS, entries)
end

-- Während du wartest: die Zeile unter der Liste
function Window:RefreshWaitLine()
    local wl = self.waitLine
    if not wl then return end
    local idea = SM.Chill and SM.Chill.enabled and SM.Chill:CurrentWaitIdea()
    if not idea then wl:Hide() return end
    wl.icon:SetTexture(idea.icon)
    wl.text:SetText(L.WAIT_LINE:format(idea.text or ""))
    if idea.point and SM.Eta and SM.Eta.enabled then wl.go:Show() else wl.go:Hide() end
    wl:Show()
end

function Window:WaitGo()
    local idea = SM.Chill and SM.Chill:CurrentWaitIdea()
    if not (idea and idea.point and SM.Eta) then return false end
    local p = idea.point
    local ok, msg = SM.Eta:GoTo({ mapID = p.mapID, x = p.x, y = p.y, title = p.title })
    self:SetStatus(msg, ok and good or bad)
    return ok
end

function Window:SetStatus(text, color)
    color = color or ink
    self.status:SetTextColor(color[1], color[2], color[3])
    self.status:SetText(text or "")
end

function Window:Submit()
    local voice = self.voiceLevel or 0
    local ok, msg = SM.Beacon:Create(self.kind, self.editBox:GetText(), voice, self.questID, nil, self.beaconAt)
    self:SetStatus(msg, ok and good or bad)
    -- Gründe, warum kein Beacon rausging (z. B. "Nicht stören ist an"), auch in den Chat:
    -- die Statuszeile übersieht man leicht
    if not ok and msg and msg ~= "" then SM:Print(msg) end
    if ok then
        self.editBox:SetText("")
        self.beaconAt = nil
        self.questID, self.questName, self.questChosen = nil, nil, nil
        self:UpdateQuestButton()
        self.offset = 0
        -- erstes Beacon mit Sprachchat: einmal den Spickzettel anbieten
        if voice > 0 and SM.VoiceCard then SM.VoiceCard:OfferOnce() end
    end
    self:RefreshList()
    self:UpdateCreateButton()
end

function Window:UpdateCreateButton()
    if not self.lightBtn then return end
    local B = SM.Beacon
    local wait = math.ceil(B:Cooldown() - (GetTime() - B.lastSent))
    if not B.enabled then
        self.lightBtn:Disable()
        self.lightBtn:SetText(L.FORM_LIGHT)
    elseif not B:LevelOK() then
        self.lightBtn:Disable()
        self.lightBtn:SetText(L.FORM_LEVEL:format(SM.Guard.MIN_BEACON_LEVEL))
    elseif wait > 0 then
        self.lightBtn:Disable()
        self.lightBtn:SetText(L.FORM_WAIT:format(wait))
    else
        self.lightBtn:Enable()
        self.lightBtn:SetText(L.FORM_LIGHT)
    end
end

function Window:RefreshList()
    if not self.frame or not self.beaconPanel:IsShown() then return end
    local B = SM.Beacon
    local all = B.enabled and B:GetAll() or {}

    -- Zonenfilter
    local db = SM.db.beacon
    local mapID = B:PlayerMapID()
    local zoneOnly = (db.zoneFilter == "own") and mapID ~= nil
    local list = {}
    for _, b in ipairs(all) do
        if not zoneOnly or b.own or B:InPlayerZone(b, mapID) then list[#list + 1] = b end
    end
    local hidden = #all - #list
    if db.zoneFilter == "own" then
        self.filterBtn:SetText(L.FILTER_OWN:format(mapID and MapName(mapID) or "?"))
        self.filterBtn:LockHighlight()
    else
        self.filterBtn:SetText(L.FILTER_ALL)
        self.filterBtn:UnlockHighlight()
    end

    -- Spieler, die du schon kennst, stehen oben (Wiedersehen); sonst neueste zuerst
    for _, b in ipairs(list) do b.known = (not b.own) and SM.Social:Known(b.sender) and true or false end
    table.sort(list, function(a, b)
        if a.known ~= b.known then return a.known end
        if a.created ~= b.created then return a.created > b.created end
        return a.key < b.key
    end)

    local maxOffset = math.max(0, #list - ROWS)
    if self.offset > maxOffset then self.offset = maxOffset end

    local _, byID = Q:ScanLog()
    local now = GetTime()
    for i = 1, ROWS do
        local row, b = self.rows[i], list[self.offset + i]
        row.beacon = b
        if b then
            local mins = math.max(1, math.ceil((b.expires - now) / 60))
            local tag = SM.Social.VoiceTag(b.voice)
            local voice = (tag and ("  " .. SM.Hex("2F5D1F") .. "[" .. tag .. "]|r") or "")
                .. SM.Social.FlagTags(b) .. (b.known and SM.Social.KnownTag(true) or "")
            row.line1:SetText(("|cff%s[%s]|r %s%s"):format(
                M.colors.kind[b.kind], L["KIND_" .. b.kind], RowTitle(b, byID), voice))
            -- Der Ort steht vorn: bei Quests die Zone, in der sie zu machen ist (Treffpunkt in Klammern, falls anders)
            local place, mapName, differs = B:Where(b, byID)
            if differs then place = L.ROW_PLACE_MEET:format(place, mapName) end
            local meta = L.ROW_META:format(place, b.own and L.ROW_OWN or b.sender, mins)

            if b.questID then
                row.prog:SetText((ProgressColored(b)))
                local stand = Q:OwnStand(b.questID, byID)
                SetHex(row.bar, M.colors.stand[stand] or M.colors.kind[b.kind])
                if not b.own and stand then
                    meta = meta .. "  |  " .. L.ROW_YOU:format("|cff" .. M.colors.standText[stand] .. L["STAND_" .. stand] .. "|r")
                end
            else
                row.prog:SetText("")
                SetHex(row.bar, M.colors.kind[b.kind])
            end
            row.line2:SetText(meta)
            row:Show()
        else
            row:Hide()
        end
    end

    self:RefreshWaitLine()

    if #list == 0 then
        self.emptyText:SetText(hidden > 0 and L.LIST_EMPTY_ZONE:format(hidden) or L.LIST_EMPTY)
        self.emptyText:Show()
        self.pageText:SetText("")
    else
        self.emptyText:Hide()
        if #list > ROWS then
            self.pageText:SetText(L.LIST_PAGE:format(self.offset + 1, math.min(self.offset + ROWS, #list), #list))
        else
            self.pageText:SetText("")
        end
    end
end

---------------------------------------------------------------------------
-- Tab „Optionen“: zwei Seiten - "Einstellungen" (eine Seite mit dem Nötigsten, darunter "Mehr")
-- und "Hilfe" (alles ausführlich, Regeln, Tasten, Karten-Symbole, Community, Feedback).
-- Alles andere läuft von selbst: Hinweise kommen nur für deine Zone oder Quests in deinem Log,
-- Fenster, die du immer gleich zumachst, kommen nur noch im Chat (SM:Popup) ...
---------------------------------------------------------------------------
local SETTINGS_W = 452 -- Breite des Inhalts (rechts bleibt Platz für die Scroll-Leiste)
local CATS = { "general", "help" }
local SOFT = M.colors.soft
local LANG_CYCLE = { "auto", "deDE", "enUS", "zhCN" }

local function Small(parent, x, y, text, width)
    local fs = MakeText(parent, "GameFontNormalSmall", SOFT)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width or (SETTINGS_W - 4))
    fs:SetJustifyV("TOP")
    fs:SetText(text)
    return fs
end

-- Höhe eines Textes (mindestens eine Zeile) - damit lange Übersetzungen nichts überdecken
local function TextH(fs, minH)
    local h = fs.GetStringHeight and fs:GetStringHeight() or 0
    return math.max(minH or 12, math.ceil(tonumber(h) or 0))
end

-- Knöpfe einer Reihe nach Textlänge aufteilen: lange Namen bekommen mehr Platz, kurze weniger.
-- So passt jeder Name ganz hinein (auch "Treffpunkte" oder chinesische Namen).
local function TextWidth(fs)
    local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
    if not w or w <= 0 then w = fs:GetStringWidth() end
    return w or 0
end

local function FitRow(buttons, order, rowW, gap, pad, anchorFn)
    local want, sum = {}, 0
    for i, key in ipairs(order) do
        want[i] = TextWidth(buttons[key].label) + pad
        sum = sum + want[i]
    end
    local room = rowW - (#order - 1) * gap
    local extra = (room - sum) / #order
    local x = 0
    for i, key in ipairs(order) do
        -- passt alles: Rest gleichmäßig verteilen, sonst im Verhältnis kürzen
        local w = math.floor(extra >= 0 and (want[i] + extra) or (room * want[i] / sum))
        local b = buttons[key]
        b:SetWidth(w)
        b.label:SetWidth(w - 8)
        b:ClearAllPoints()
        anchorFn(b, x)
        x = x + w + gap
    end
end
Window.FitRow = FitRow

local CAT_ROW, CAT_GAP, CAT_PAD = 472, 4, 18
function Window:FitCatButtons()
    FitRow(self.catButtons, CATS, CAT_ROW, CAT_GAP, CAT_PAD, function(b, x) b:SetPoint("TOPLEFT", x, 0) end)
end

function Window:SelectSettingsCat(cat)
    if not self.catPages or not self.catPages[cat] then cat = "general" end
    SM.db.ui.settingsCat = cat
    for c, page in pairs(self.catPages) do
        if c == cat then
            page.scroll:Show()
            self.catButtons[c]:LockHighlight()
        else
            page.scroll:Hide()
            if page.scroll.track then page.scroll.track:Hide() end
            self.catButtons[c]:UnlockHighlight()
        end
    end
    -- Texthöhen neu messen (beim Bauen kennt das Spiel sie manchmal noch nicht)
    if cat == "help" and self.helpFlow then self.helpFlow:Layout() end
    if cat == "general" and self.LayoutMore then self.LayoutMore() end
    self.settingsScroll = self.catPages[cat].scroll
    if self.settingsScroll.UpdateThumb then self.settingsScroll:UpdateThumb() end
    self:RefreshSettings()
end

---------------------------------------------------------------------------
-- Fluss-Layout: Elemente untereinander, Höhe von Texten wird bei jedem Zeigen neu gemessen.
-- So überdeckt sich nichts, egal wie lang eine Übersetzung ist (Chinesisch, Deutsch ...).
--   flow:Add(obj, x, h, gap)  h = feste Höhe oder nil (= Texthöhe von obj)
---------------------------------------------------------------------------
local function NewFlow(page)
    local flow = { items = {}, page = page }
    function flow:Add(obj, x, h, gap, minH)
        self.items[#self.items + 1] = { obj = obj, x = x or 0, h = h, gap = gap or 0, minH = minH }
        return obj
    end
    function flow:Layout()
        local y = 0
        for _, it in ipairs(self.items) do
            local o = it.obj
            if not it.skip or not it.skip() then
                o:ClearAllPoints()
                o:SetPoint("TOPLEFT", self.page, "TOPLEFT", it.x, y)
                if it.show then o:Show() end
                local h = it.h or TextH(o, it.minH)
                y = y - h - it.gap
            else
                o:Hide()
            end
        end
        self.height = -y
        self.page:SetHeight(-y + 10)
        return -y
    end
    return flow
end

---------------------------------------------------------------------------
-- Seite "Hilfe": was früher im Tab Info stand
---------------------------------------------------------------------------
function Window:BuildHelpPage(P)
    local flow = NewFlow(P)
    self.helpFlow = flow
    local fs = MakeText(P, "GameFontNormal")
    fs:SetWidth(SETTINGS_W - 4)
    fs:SetJustifyV("TOP")
    fs:SetText(L.INFO_TEXT)
    self.infoText = fs
    flow:Add(fs, 0, nil, 14, 100)

    -- Regeln, Tasten, Karten-Symbole
    flow:Add(Header(P, L.HELP_RULES_HDR, 0, 0), 0, 24)
    local rb = UI.Button(P, Name("Rules"), 220, 22, L.RULES_READ_ALL)
    rb:SetScript("OnClick", function() SM.Rules:ShowFull() end)
    self.rulesBtn = rb
    flow:Add(rb, 0, 22, 12)
    flow:Add(Header(P, L.SET_KEYS_HDR, 0, 0), 0, 24)
    flow:Add(Small(P, 0, 0, L.SET_KEYS_HINT), 0, nil, 12, 24)
    flow:Add(Header(P, L.SET_LEGEND_HDR, 0, 0), 0, 24)
    self.pinLegend = Small(P, 0, 0, L.PIN_LEGEND)
    flow:Add(self.pinLegend, 0, nil, 12, 60)

    -- Community-Tafel: vier Knöpfe, ein Klick öffnet den Kopier-Dialog (zwei Reihen)
    flow:Add(Header(P, L.INFO_LINKS_HDR, 0, 0), 0, 26)
    self.linkButtons = {}
    local linkRow = CreateFrame("Frame", nil, P)
    linkRow:SetSize(SETTINGS_W, 52)
    for i, link in ipairs(SM.Links) do
        if i > 4 then break end
        local b = UI.Button(linkRow, Name("Link"), 222, 24)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", col * 228, -row * 28)
        b:SetText(L["LINK_" .. link.id])
        b:SetScript("OnClick", function() SM.CopyDialog:Show(SM.LinkURL(link)) end)
        self.linkButtons[i] = b
    end
    flow:Add(linkRow, 0, 52, 10)

    -- Feedback kopieren: Fehler, unbekannte Zonen usw. als Text für CurseForge oder Discord
    local fb = UI.Button(P, Name("Feedback"), 200, 22, L.FEEDBACK_BTN)
    fb:SetScript("OnClick", function()
        if SM.Feedback then SM.CopyDialog:Show(SM.Feedback:Text(), L.FEEDBACK_COPY_TITLE, L.FEEDBACK_COPY_HINT) end
    end)
    fb:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:AddLine(L.FEEDBACK_BTN, 1, 0.82, 0)
        GameTooltip:AddLine(L.FEEDBACK_TT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    fb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.feedbackBtn = fb
    flow:Add(fb, 0, 22, 4)
    -- ein Satz, wofür der Knopf da ist (vorher nur im Tooltip)
    self.feedbackExplain = Small(P, 0, 0, L.FEEDBACK_EXPLAIN)
    flow:Add(self.feedbackExplain, 0, nil, 16, 24)
    flow:Layout()
end

---------------------------------------------------------------------------
-- Seite "Einstellungen"
---------------------------------------------------------------------------
function Window:BuildSettingsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel:Hide()
    self.settingsPanel = panel
    self.widgets, self.w = {}, {}
    local function Add(key, w)
        self.widgets[#self.widgets + 1] = w
        self.w[key] = w
        return w
    end
    local db = SM.db

    -- Zwei Seiten (Einstellungen, Hilfe), jede zum Scrollen
    self.catButtons, self.catPages = {}, {}
    for i, cat in ipairs(CATS) do
        local b = UI.Button(panel, Name("Cat"), 115, 22, L["SETCAT_" .. cat:upper()])
        b:SetPoint("TOPLEFT", (i - 1) * 119, 0)
        b:SetScript("OnClick", function() Window:SelectSettingsCat(cat) end)
        self.catButtons[cat] = b
        local scroll, P = UI.ScrollArea(panel, Name("SettingsScroll"))
        scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -34)
        scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 4)
        P:SetWidth(SETTINGS_W)
        scroll:Hide()
        self.catPages[cat] = { scroll = scroll, P = P }
    end
    self:FitCatButtons()

    local P = self.catPages.general.P
    local flow = NewFlow(P)
    self.generalFlow = flow
    -- Schalter mit einer kurzen Erklärung darunter (Höhe nach dem Text)
    local function Switch(key, label, desc, getter, setter)
        local cb = Add(key, MakeCheck(P, label, 0, 0, getter, setter))
        flow:Add(cb, 2, 20, desc and 2 or 8)
        if desc then
            cb.desc = Small(P, 28, 0, desc, SETTINGS_W - 32)
            flow:Add(cb.desc, 28, nil, 10)
        end
        return cb
    end

    -- Sprache
    flow:Add(Header(P, L.SET_LANGUAGE_HDR, 0, 0), 0, 28)
    local langRow = CreateFrame("Frame", nil, P)
    langRow:SetSize(SETTINGS_W, 22)
    local lb = UI.Button(langRow, Name("Lang"), 220, 22, "")
    lb:SetPoint("TOPLEFT", 0, 0)
    function lb:Refresh() self:SetText(L["LANG_" .. (db.language or "auto")]) end
    lb:SetScript("OnClick", function(btn)
        local cur = db.language or "auto"
        local nextIdx = 1
        for i, code in ipairs(LANG_CYCLE) do if code == cur then nextIdx = i % #LANG_CYCLE + 1 end end
        db.language = LANG_CYCLE[nextIdx]
        btn:Refresh()
        Window.reloadBtn:Show()
    end)
    Add("language", lb)
    self.reloadBtn = UI.Button(langRow, Name("Reload"), 200, 22, L.SET_RELOAD)
    self.reloadBtn:SetPoint("TOPLEFT", 228, 0)
    self.reloadBtn:SetScript("OnClick", function() if ReloadUI then ReloadUI() end end)
    self.reloadBtn:Hide()
    flow:Add(langRow, 0, 22, 4)
    flow:Add(Small(P, 0, 0, L.SET_LANGUAGE_HINT), 0, nil, 14)

    -- Aussehen (test8b): Skin (fertige Farbsätze) und Durchsichtigkeit - für alle Fenster,
    -- übernommen nach "Jetzt neu laden" (Media\Textures.lua)
    flow:Add(Header(P, L.SET_LOOK_HDR, 0, 0), 0, 28)
    local skinRow = CreateFrame("Frame", nil, P)
    skinRow:SetSize(SETTINGS_W, 22)
    local sb = UI.Button(skinRow, Name("Skin"), 220, 22, "")
    sb:SetPoint("TOPLEFT", 0, 0)
    function sb:Refresh() self:SetText(L.SET_SKIN:format(L["SKIN_" .. (SM.db.ui.skin or "parchment")] or "?")) end
    sb:SetScript("OnClick", function(btn) Window:SkinMenu(btn) end)
    Add("skin", sb)
    self.skinBtn = sb
    self.skinReloadBtn = UI.Button(skinRow, Name("Reload"), 200, 22, L.SET_RELOAD)
    self.skinReloadBtn:SetPoint("TOPLEFT", 228, 0)
    self.skinReloadBtn:SetScript("OnClick", function() if ReloadUI then ReloadUI() end end)
    self.skinReloadBtn:Hide()
    flow:Add(skinRow, 0, 22, 26)
    -- immer die aktuelle Einstellung (auch wenn SM.db.ui neu angelegt wurde)
    local uiNow = setmetatable({}, { __index = function(_, k) return SM.db.ui[k] end,
                                     __newindex = function(_, k, v) SM.db.ui[k] = v end })
    local opSlider = MakeSlider(P, 0, 0, 50, 100, 5, "SET_OPACITY", uiNow, "opacity", function() Window:SkinChanged() end)
    Add("opacity", opSlider)
    flow:Add(opSlider, 0, 20, 14)
    flow:Add(Small(P, 0, 0, L.SET_LOOK_HINT), 0, nil, 14)

    -- Die Schalter (zuerst die Einfach-Ansicht, test8b)
    Switch("simple", L.SET_SIMPLE, L.SET_SIMPLE_DESC,
        function() return Window:IsSimple() end, function(v) Window:SetSimple(v) end)
    Switch("dnd", L.SET_DND, L.SET_DND_DESC,
        function() return SM:IsDND() end, function(v) SM:SetDND(v) end)
    Switch("musicAuto", L.SET_MUSIC_AUTO, L.SET_MUSIC_AUTO_DESC,
        function() return SM:MusicMode() == "auto" end,
        function(v)
            local mode = v and "auto" or "click"
            if SM.Chill then SM.Chill:SetMode(mode) else db.music.mode = mode end
        end)
    Switch("sounds", L.SET_SOUNDS_ALL, L.SET_SOUNDS_ALL_DESC,
        function() return db.ui.sounds ~= false end,
        function(v)
            db.ui.sounds = v
            if SM.Soundboard then SM.Soundboard:SetEnabled(v) end
        end)
    Switch("loreZone", L.SET_LORE_ZONE, nil,
        function() return db.lore.onZone ~= false end, function(v) db.lore.onZone = v end)
    Switch("improve", L.SET_IMPROVE, L.SET_IMPROVE_DESC,
        function() return SM:HelpImprove() end, function(v) db.improve = v and true or false end)
    Switch("minimap", L.SET_MINIMAP, nil,
        function() return not db.minimap.hide end,
        function(v)
            db.minimap.hide = not v
            if SM.MinimapButton then SM.MinimapButton:Apply() end
        end)

    -- "Mehr": selten gebraucht, darum zugeklappt
    local more = UI.Button(P, Name("More"), 140, 22, L.SET_MORE)
    self.moreBtn = more
    flow:Add(more, 0, 22, 12)
    local function MoreOpen() return SM.db.ui.moreOpen and true or false end
    local function More(obj, x, h, gap, minH)
        flow:Add(obj, x, h, gap, minH)
        local it = flow.items[#flow.items]
        it.skip = function() return not MoreOpen() end
        it.show = true
        return obj
    end
    local moreItems = {}
    local function Keep(o) moreItems[#moreItems + 1] = o; return o end
    More(Keep(Header(P, L.SET_WINDOW, 0, 0)), 0, 24, 22)
    local sc = MakeSlider(P, 0, 0, 50, 120, 5, "SET_SCALE", db.window, "scale",
        function(pct) Window:ApplyScale(pct) end)
    Add("scale", sc)
    More(Keep(sc), 0, 20, 14)
    local function Pair(a, b, h)
        local row = CreateFrame("Frame", nil, P)
        row:SetSize(SETTINGS_W, h or 22)
        a:SetParent(row); a:ClearAllPoints(); a:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        if b then b:SetParent(row); b:ClearAllPoints(); b:SetPoint("TOPLEFT", row, "TOPLEFT", 228, 0) end
        return row
    end
    local rp = UI.Button(P, Name("ResetPos"), 220, 22, L.SET_RESET_POS)
    rp:SetScript("OnClick", function() SM:ResetPositions() end)
    local lw = UI.Button(P, Name("Learned"), 220, 22, L.SET_WINDOWS_BACK)
    lw:SetScript("OnClick", function()
        SM:ResetLearned()
        SM:Print(L.POPUP_RESET)
        Window:RefreshSettings()
    end)
    function lw:Refresh()
        if next(SM.db.ui.learned or {}) then self:Enable() else self:Disable() end
    end
    Add("learned", lw)
    More(Keep(Pair(rp, lw)), 0, 22, 4)
    More(Keep(Small(P, 0, 0, L.SET_WINDOWS_HINT)), 0, nil, 10)
    local su = UI.Button(P, Name("Setup"), 220, 22, L.SET_SETUP_AGAIN)
    su:SetScript("OnClick", function() SM.Setup:Show() end)
    local op = UI.Button(P, Name("OpenPlayer"), 220, 22, L.SET_OPEN_PLAYER)
    op:SetScript("OnClick", function() SM.Chill:ShowPlayer(true) end)
    self.openPlayerBtn = op
    More(Keep(Pair(su, op)), 0, 22, 6)
    local ra = UI.Button(P, Name("ResetAll"), 220, 22, L.SET_RESET_ALL)
    ra:SetScript("OnClick", function()
        SM.Confirm:Show(L.SET_RESET_ALL_ASK, function()
            SM:ResetSettings()
            if ReloadUI then ReloadUI() end
        end)
    end)
    self.resetAllBtn = ra
    More(Keep(Pair(ra)), 0, 22, 6)
    More(Keep(Small(P, 0, 0, L.SET_RESET_HINT)), 0, nil, 10)
    -- für Tests und die Optik: der aufklappbare Teil als Ganzes
    self.morePanel = { items = moreItems, IsShown = function() return MoreOpen() end }
    self.morePanel.shown = MoreOpen()

    local function Layout()
        more:SetText(MoreOpen() and L.SET_LESS or L.SET_MORE)
        self.morePanel.shown = MoreOpen()
        flow:Layout()
        local s = Window.catPages.general.scroll
        if s.UpdateThumb then s:UpdateThumb() end
    end
    more:SetScript("OnClick", function()
        SM.db.ui.moreOpen = not SM.db.ui.moreOpen
        Layout()
    end)
    self.LayoutMore = Layout
    Layout()

    self:BuildHelpPage(self.catPages.help.P)
    self:SelectSettingsCat(db.ui.settingsCat or "general")
end

-- Skin wählen: kleine Auswahl, der gewählte steht mit "(gewählt)" dabei
function Window:SkinMenu(btn)
    local db = SM.db
    local entries = {}
    for _, name in ipairs(SM.SKIN_ORDER) do
        local cur = (db.ui.skin or "parchment") == name
        entries[#entries + 1] = {
            text = (L["SKIN_" .. name] or name) .. (cur and ("  " .. L.SKIN_CURRENT) or ""),
            tip = L["SKIN_" .. name .. "_TT"],
            fn = function()
                db.ui.skin = name
                if btn and btn.Refresh then btn:Refresh() end
                Window:SkinChanged()
            end,
        }
    end
    return SM.UI.Menu(btn, L.SET_SKIN_MENU, entries)
end

-- Neu laden nötig? (anderer Skin oder andere Durchsichtigkeit als gerade aktiv)
function Window:SkinChanged()
    local db, M2 = SM.db, SM.Media
    local want = math.max(50, math.min(100, tonumber(db.ui.opacity) or 100)) / 100
    local changed = (db.ui.skin or "parchment") ~= (M2.skin or "parchment") or math.abs(want - (M2.opacity or 1)) > 0.001
    if self.skinReloadBtn then
        if changed then self.skinReloadBtn:Show() else self.skinReloadBtn:Hide() end
    end
    return changed
end

function Window:RefreshSettings()
    if not self.widgets then return end
    -- Nur Schalter und Regler haben einen Stand; reine Knöpfe werden übersprungen.
    for _, w in ipairs(self.widgets) do
        if w.Refresh then w:Refresh() end
    end
end

---------------------------------------------------------------------------
-- Rahmen, Tabs, Öffnen/Schließen
---------------------------------------------------------------------------
function Window:RefreshTitle()
    if not self.title then return end
    self.title:SetText(L.WIN_TITLE)
    -- Test- und Probe-Modus (nur mit dem Dev-Zusatz) stehen ÜBER dem Fenster, damit sie
    -- nichts in der Titelleiste verdecken.
    local tags = {}
    if SM:IsTestMode() then tags[#tags + 1] = "|cffff7060[TEST]|r" end
    if SM.Probe and SM.Probe.on then tags[#tags + 1] = "|cffb070ff[PROBE]|r" end
    if SM.DEV and SM.db.devForever ~= nil then
        tags[#tags + 1] = SM.db.devForever and "|cffffb347[FOREVER]|r" or "|cffb0a890[CLASSIC]|r"
    end
    if self.modeTag then
        self.modeTag:SetText(table.concat(tags, "  "))
        if #tags > 0 then self.modeTag:Show() else self.modeTag:Hide() end
    end
end

function Window:RefreshDND()
    if not self.dndBtn then return end
    if SM:IsDND() then self.dndBtn:LockHighlight() else self.dndBtn:UnlockHighlight() end
end

-- Rechtsklick auf "Nicht stören": für eine Weile
function Window:DNDMenu(btn)
    SM.UI.Menu(btn, L.SET_DND, {
        { text = L.SET_DND_30, fn = function() SM:SetDND(true, 30) end },
        { text = L.SET_DND_60, fn = function() SM:SetDND(true, 60) end },
        { text = L.SET_DND_LOGOUT, fn = function() SM:SetDND(true, "logout") end },
        { text = L.DND_OFF, disabled = not SM:IsDND(), fn = function() SM:SetDND(false) end },
    })
end

---------------------------------------------------------------------------
-- Erst-Tipp: beim ersten Öffnen eines Tabs zwei Zeilen oben, "Verstanden" - dann nie wieder.
-- So lange ist das Fenster etwas höher, damit nichts verdeckt wird.
---------------------------------------------------------------------------
function Window:LayoutTip(show)
    local f = self.frame
    f:SetHeight(HEIGHT + (show and TIP_H or 0))
    self.content:ClearAllPoints()
    self.content:SetPoint("TOPLEFT", 22, -88 - (show and TIP_H or 0))
    self.content:SetPoint("BOTTOMRIGHT", -22, 20)
    if show then self.tipBar:Show() else self.tipBar:Hide() end
end

function Window:ShowFirstTip(tab)
    if not self.tipBar then return end
    local seen = SM.db.ui.tipsSeen
    if seen[tab] or not rawget(L, "FIRST_TIP_" .. tab) then
        self:LayoutTip(false)
        return
    end
    self.tipBar.tab = tab
    self.tipBar.text:SetText(L["FIRST_TIP_" .. tab])
    self:LayoutTip(true)
end

---------------------------------------------------------------------------
-- Einfach-Ansicht (test8b): nur Treffpunkte, Instant und Optionen. Orte und Kontakte lassen sich
-- in den Optionen dazuschalten; wer sie gezielt öffnet (Befehl, Karte, Knopf), bekommt sie gleich.
---------------------------------------------------------------------------
local HIDEABLE = { places = true, contacts = true }

function Window:TabHidden(tab)
    local h = SM.db and SM.db.ui.hideTabs
    return HIDEABLE[tab] and h and h[tab] and true or false
end

function Window:VisibleTabs()
    local list = {}
    for _, t in ipairs(TABS) do if not self:TabHidden(t) then list[#list + 1] = t end end
    return list
end

function Window:LayoutTabs()
    if not self.tabButtons then return end
    local vis = self:VisibleTabs()
    local shown = {}
    for _, t in ipairs(vis) do shown[t] = true end
    for t, b in pairs(self.tabButtons) do if shown[t] then b:Show() else b:Hide() end end
    FitRow(self.tabButtons, vis, TAB_ROW, TAB_GAP, TAB_PAD,
        function(b, x) b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 22 + x, -52) end)
end

-- Einfach-Ansicht an/aus (Orte und Kontakte zusammen)
function Window:SetSimple(on)
    SM.db.ui.hideTabs = on and { places = true, contacts = true } or {}
    self:LayoutTabs()
    if self.tab and self:TabHidden(self.tab) then self:SelectTab("beacons") end
end

function Window:IsSimple()
    return self:TabHidden("places") and self:TabHidden("contacts")
end

-- Einen ausgeblendeten Tab dazuschalten (mit einer Chatzeile, wie man ihn wieder los wird)
function Window:ShowTab(tab)
    if not self:TabHidden(tab) then return false end
    SM.db.ui.hideTabs[tab] = nil
    self:LayoutTabs()
    SM:Print(L.TAB_SHOWN:format(L["TAB_" .. tab:upper()]))
    return true
end

function Window:SelectTab(tab)
    local valid = false
    for _, t in ipairs(TABS) do if t == tab then valid = true end end
    if not valid or self:TabHidden(tab) then tab = "beacons" end

    self.tab = tab
    SM.db.activeTab = tab
    if self.picker then self.picker:Hide() end
    -- Stellen von der Weltkarte gelten nur für den Tab, für den sie gedacht waren
    if tab ~= "places" then self.placeAt = nil end
    if tab ~= "beacons" then self.beaconAt = nil end

    local panels = { beacons = self.beaconPanel, instant = self.instantPanel,
                     contacts = self.contactsPanel, places = self.placesPanel, settings = self.settingsPanel }
    for _, t in ipairs(TABS) do
        if t == tab then
            panels[t]:Show()
            self.tabButtons[t]:LockHighlight()
        else
            panels[t]:Hide()
            self.tabButtons[t]:UnlockHighlight()
        end
    end

    if tab == "beacons" then
        self:PrefillQuest()
        self:RefreshTags()
        self:RefreshList()
        self:UpdateCreateButton()
    elseif tab == "instant" then
        self:RefreshInstant()
    elseif tab == "contacts" then
        self:RefreshContacts()
    elseif tab == "places" then
        self:RefreshPlaces()
    elseif tab == "settings" then
        self:RefreshSettings()
    end
    self:ShowFirstTip(tab)
end

function Window:ApplyScale(pct)
    local f = self.frame
    if not f then return end
    local oldS = f:GetEffectiveScale() or 1
    local cx, cy = f:GetCenter()
    f:SetScale(pct / 100)
    if cx and cy then
        local newS = f:GetEffectiveScale() or 1
        local x, y = cx * oldS / newS, cy * oldS / newS
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        local w = SM.db.window
        w.point, w.relPoint, w.x, w.y = "CENTER", "BOTTOMLEFT", x, y
    end
end

function Window:Create()
    if self.frame then return end

    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "SocializeMeForeverWindow", UIParent, template)
    self.frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true) -- angeklickt kommt es nach vorn (z. B. vor den Lore-Leser)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(fr) SM.UI.DragStart(fr) end)
    f:SetScript("OnMouseDown", function() SM.UI.DropFocus() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        local w = SM.db.window
        w.point, w.relPoint, w.x, w.y = point, relPoint, x, y
    end)

    if f.SetBackdrop then
        f:SetBackdrop({
            edgeFile = M.tex.border,
            edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    -- Pergament als eigene Fläche (die Backdrop-Farbe wird auf manchen Clients ignoriert)
    local paper = f:CreateTexture(nil, "BACKGROUND")
    paper:SetPoint("TOPLEFT", 11, -11)
    paper:SetPoint("BOTTOMRIGHT", -11, 11)
    paper:SetColorTexture(unpack(M.colors.parchment))

    local w = SM.db.window
    f:SetScale((w.scale or 85) / 100)
    if w.point then
        f:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
    else
        f:SetPoint("CENTER")
    end

    -- Titelleiste im Holz-Look (mit feiner Maserung)
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -14)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -14)
    bar:SetHeight(30)
    local barTex = bar:CreateTexture(nil, "BACKGROUND")
    barTex:SetAllPoints(bar)
    barTex:SetColorTexture(unpack(M.colors.wood))
    UI.AddGrain(bar, WIDTH - 28, 30, "BORDER")
    local barLine = bar:CreateTexture(nil, "ARTWORK")
    barLine:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    barLine:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    barLine:SetHeight(2)
    barLine:SetColorTexture(unpack(M.wood.border))
    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", bar, "LEFT", 10, 0) -- links, rechts sitzen "Nicht stören" und "Offenes Ohr"
    self.title = title
    local modeTag = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modeTag:SetPoint("BOTTOM", f, "TOP", 0, 2)
    self.modeTag = modeTag
    self:RefreshTitle()

    local close = UI.CloseButton(f, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -18)
    close:SetFrameLevel(bar:GetFrameLevel() + 3)
    self.closeBtn = close

    -- Ein offenes Ohr (eigenes Fenster)
    local earBtn = UI.Button(f, Name("Ear"), 110, 22, L.EAR_BTN)
    earBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -44, -18)
    earBtn:SetFrameLevel(bar:GetFrameLevel() + 3)
    earBtn:SetScript("OnClick", function() SM.EarUI:Toggle() end)
    earBtn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L.EAR_TITLE, 1, 0.82, 0)
        GameTooltip:AddLine(L.EAR_BTN_TT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    earBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.earBtn = earBtn

    -- "Nicht stören" als Schalter gleich daneben (Klick = an/aus, Rechtsklick = für eine Weile)
    local dnd = UI.Button(f, Name("DND"), 100, 22, L.DND_BTN)
    local dw = math.max(80, math.ceil(TextWidth(dnd.label)) + 20)
    dnd:SetWidth(dw)
    dnd.label:SetWidth(dw - 8)
    dnd:SetPoint("RIGHT", earBtn, "LEFT", -4, 0)
    dnd:SetFrameLevel(bar:GetFrameLevel() + 3)
    dnd:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    dnd:SetScript("OnClick", function(btn, button)
        if button == "RightButton" then Window:DNDMenu(btn) else SM:SetDND(not SM:IsDND()) end
    end)
    dnd:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L.SET_DND, 1, 0.82, 0)
        GameTooltip:AddLine(L.SET_DND_DESC, 1, 1, 1, true)
        GameTooltip:AddLine(L.DND_BTN_TT, 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    dnd:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.dndBtn = dnd
    self:RefreshDND()

    -- Tabs (Breite nach Text, die ganze Reihe gefüllt)
    self.tabButtons = {}
    for _, tab in ipairs(TABS) do
        local b = UI.Button(f, Name("Tab"), 80, 24, L["TAB_" .. tab:upper()])
        b:SetScript("OnClick", function() Window:SelectTab(tab) end)
        -- Maus drüber: in einem Satz, wofür der Tab da ist
        b:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(L["TAB_" .. tab:upper()], 1, 0.82, 0)
            GameTooltip:AddLine(L["TABTT_" .. tab], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.tabButtons[tab] = b
    end
    self:LayoutTabs()

    -- Erst-Tipp (zwei Zeilen + "Verstanden"), unter den Tabs
    local tipBar = UI.Panel(f, nil, M.colors.tip)
    tipBar:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -84)
    tipBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -84)
    tipBar:SetHeight(TIP_H - 6)
    tipBar.text = MakeText(tipBar, "GameFontNormalSmall")
    tipBar.text:SetPoint("TOPLEFT", 8, -5)
    tipBar.text:SetPoint("BOTTOMRIGHT", -106, 5)
    tipBar.text:SetJustifyV("MIDDLE")
    tipBar.ok = UI.Button(tipBar, Name("TipOK"), 92, 22, L.FIRST_TIP_OK)
    tipBar.ok:SetPoint("RIGHT", tipBar, "RIGHT", -6, 0)
    tipBar.ok:SetScript("OnClick", function()
        SM.db.ui.tipsSeen[tipBar.tab or ""] = true
        Window:LayoutTip(false)
    end)
    tipBar:Hide()
    self.tipBar = tipBar

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 22, -88)
    content:SetPoint("BOTTOMRIGHT", -22, 20)
    self.content = content

    self:BuildBeaconPanel(content)
    self:BuildInstantPanel(content)   -- UI/InstantPanel.lua
    self:BuildContactsPanel(content)  -- UI/ContactsPanel.lua
    self:BuildPlacesPanel(content)    -- UI/PlacesPanel.lua
    self:BuildSettingsPanel(content)

    -- Aktualisierung (Restzeit, Cooldown) nur solange sichtbar
    local acc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.5 then return end
        acc = 0
        if Window.tab == "beacons" then
            Window:RefreshList()
            Window:UpdateCreateButton()
        elseif Window.tab == "places" then
            Window.placeTick = (Window.placeTick or 0) + 1
            if Window.placeTick % 4 == 0 then Window:RefreshPlaces() end -- Entfernungen alle 2 Sek.
        end
    end)

    f:HookScript("OnHide", function() Window.placeAt, Window.beaconAt = nil, nil end)
    tinsert(UISpecialFrames, "SocializeMeForeverWindow") -- ESC schließt das Fenster
    f:Hide()
    self:SelectTab(SM.db.activeTab)
end

-- Formular für ein neues Beacon öffnen (Tastenbelegung): Fenster, Tab Beacons, Cursor ins Textfeld
function Window:OpenBeaconForm()
    if SM.Rules and not SM.Rules:Accepted() then SM.Rules:Show() return end
    if SM.Guard:SelfBlocked() then SM.Guard:ShowBlocked() return end
    self:Create()
    self.frame:Show()
    self:SelectTab("beacons")
    if self.editBox then self.editBox:SetFocus() end
end

-- Fenster auf einem bestimmten Tab öffnen (z. B. /sm optionen). Ein ausgeblendeter Tab
-- (Einfach-Ansicht) wird dabei dazugeschaltet - wer ihn gezielt öffnet, will ihn sehen.
function Window:OpenTab(tab)
    if SM.Rules and not SM.Rules:Accepted() then SM.Rules:Show() return end
    if SM.Guard:SelfBlocked() then SM.Guard:ShowBlocked() return end
    self:Create()
    self:ShowTab(tab)
    self.frame:Show()
    self:SelectTab(tab)
end

-- Liste aller Beacons öffnen (z. B. Klick auf einen Karten-Pin mit Zahl)
function Window:OpenBeaconList()
    if SM.Rules and not SM.Rules:Accepted() then SM.Rules:Show() return end
    if SM.Guard:SelfBlocked() then SM.Guard:ShowBlocked() return end
    self:Create()
    SM.db.beacon.zoneFilter = "all"
    self.offset = 0
    self.frame:Show()
    self:SelectTab("beacons")
end

function Window:Toggle()
    -- Erst die Regeln, und wer gesperrt ist, sieht nur den Hinweis
    if SM.Rules and not SM.Rules:Accepted() then SM.Rules:Show() return end
    if SM.Guard:SelfBlocked() then SM.Guard:ShowBlocked() return end
    self:Create()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
        self:SelectTab(self.tab or SM.db.activeTab)
    end
end

---------------------------------------------------------------------------
-- Live-Updates durch andere Module
---------------------------------------------------------------------------
local function IfShown(fn)
    return function(...)
        if Window.frame and Window.frame:IsShown() then fn(...) end
    end
end

SM:RegisterCallback("BEACON_ADDED", IfShown(function() Window:RefreshList() end))
SM:RegisterCallback("BEACON_REMOVED", IfShown(function() Window:RefreshList() end))
SM:RegisterCallback("TEST_CHANGED", function()
    if Window.frame then Window:RefreshTitle(); Window:UpdateCreateButton() end
end)
SM:RegisterCallback("BEACON_UPDATED", IfShown(function() Window:RefreshList() end))
SM:RegisterCallback("SILENT_CHANGED", IfShown(function() Window:RefreshSettings() end))
SM:RegisterCallback("DND_CHANGED", function()
    if Window.frame then
        Window:RefreshDND()
        if Window.frame:IsShown() then Window:RefreshSettings() end
    end
end)

SM:RegisterPosition(function() return SM.db.window end, function() return Window.frame end,
    function(f) f:SetPoint("CENTER") end)
