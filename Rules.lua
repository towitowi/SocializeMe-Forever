local ADDON, SM = ...
local L = SM.L
local M = SM.Media

-- Regeln beim ersten Öffnen - so kurz wie möglich: drei Zeilen, eine freiwillige Frage
-- ("eher ruhig" oder "gern gesprächig") und "Einverstanden". Vorher bleiben alle Module aus,
-- das Addon sendet und empfängt nichts. Die ausführlichen Regeln stehen einen Klick weiter
-- ("Alle Regeln lesen") und unter Optionen > Hilfe. Ändern sich die Regeln, wird VERSION erhöht
-- und alle bestätigen neu.
local Rules = {}
SM.Rules = Rules
Rules.VERSION = 1

local W, H_SHORT, H_FULL = 470, 360, 500
local SOFT = M.colors.soft

local function CharKey()
    local name = UnitName("player") or "?"
    local realm = (type(GetRealmName) == "function" and GetRealmName()) or "?"
    return name .. "-" .. realm
end
Rules.CharKey = CharKey

function Rules:Accepted()
    local c = SM.db and SM.db.consent
    local e = c and c[CharKey()]
    return (type(e) == "table" and (tonumber(e.v) or 0) >= Rules.VERSION) and true or false
end

---------------------------------------------------------------------------
-- Wie magst du es? (früher die Einrichtung mit drei Fragen)
--   quiet: Kürzel "eher ruhig", Musik nur auf Klick (die Begrüßung folgt dem Kürzel)
--   talk:  ohne Kürzel, Musik auch von selbst
-- Die Fenster lernen bei beiden mit (siehe SM:Popup).
---------------------------------------------------------------------------
function Rules:ApplyStyle(style)
    local db = SM.db
    if style == "quiet" then
        db.social.quiet = true
        if SM.Chill and SM.Chill.SetMode then SM.Chill:SetMode("click") else db.music.mode = "click" end
    else
        db.social.quiet = false
        if SM.Chill and SM.Chill.SetMode then SM.Chill:SetMode("auto") else db.music.mode = "auto" end
    end
    db.ui.style = style
end

function Rules:Style()
    local s = SM.db and SM.db.ui.style
    if s == "quiet" or s == "talk" then return s end
    return (SM.db and SM.db.social.quiet) and "quiet" or "talk"
end

function Rules:Accept()
    SM.db.consent[CharKey()] = { v = Rules.VERSION, t = time() }
    self:ApplyStyle(self.pickedStyle or self:Style())
    SM.db.ui.setupDone = true
    if self.frame then self.frame:Hide() end
    SM:Print(L.RULES_THANKS)
    SM:Fire("RULES_ACCEPTED")
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------
local function Text(parent, font, color, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    color = color or M.colors.ink
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetShadowOffset(0, 0)
    if width then fs:SetWidth(width) end
    return fs
end

function Rules:Build()
    if self.frame then return end
    local UI = SM.UI
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "SocializeMeForeverRules", UIParent, template)
    self.frame = f
    f:SetSize(W, H_SHORT)
    f:SetPoint("CENTER", 0, 30)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(fr) SM.UI.DragStart(fr) end)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({ edgeFile = M.tex.border, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    end
    local paper = f:CreateTexture(nil, "BACKGROUND")
    paper:SetPoint("TOPLEFT", 11, -11)
    paper:SetPoint("BOTTOMRIGHT", -11, 11)
    paper:SetColorTexture(unpack(M.colors.parchment))

    -- Holzleiste mit Titel
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -14)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -14)
    bar:SetHeight(30)
    local barTex = bar:CreateTexture(nil, "BACKGROUND")
    barTex:SetAllPoints(bar)
    barTex:SetColorTexture(unpack(M.colors.wood))
    UI.AddGrain(bar, W - 28, 30, "BORDER")
    local tx = M.wood.text
    f.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("CENTER", bar, "CENTER", 0, 0)
    f.title:SetTextColor(tx[1], tx[2], tx[3])

    -------------------------------------------------------------------
    -- Kurze Ansicht: drei Zeilen + Frage
    -------------------------------------------------------------------
    local short = CreateFrame("Frame", nil, f)
    short:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -54)
    short:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 60)
    f.short = short
    f.intro = Text(short, "GameFontNormal", nil, W - 48)
    f.intro:SetPoint("TOPLEFT", 0, 0)
    f.lines = Text(short, "GameFontNormalLarge", nil, W - 56)
    f.lines:SetPoint("TOPLEFT", 6, -26)
    f.readAll = UI.Button(short, "SocializeMeForeverRulesReadAll", 180, 22, L.RULES_READ_ALL)
    f.readAll:SetPoint("TOPLEFT", 0, -112)
    f.readAll:SetScript("OnClick", function() Rules:ShowFull(true) end)

    local line = short:CreateTexture(nil, "ARTWORK")
    f.line = line
    line:SetPoint("TOPLEFT", 0, -144)
    line:SetPoint("TOPRIGHT", 0, -144)
    line:SetHeight(1)
    line:SetColorTexture(unpack(M.colors.line))

    f.styleQ = Text(short, "GameFontNormal", nil, W - 48)
    f.styleQ:SetPoint("TOPLEFT", 0, -154)
    f.styleQ:SetText(L.SETUP_Q_STYLE)
    f.styleButtons = {}
    for i, st in ipairs({ "quiet", "talk" }) do
        local b = UI.Button(short, "SocializeMeForeverRulesStyle" .. i, 205, 24, L["SETUP_STYLE_" .. st:upper()])
        b:SetPoint("TOPLEFT", (i - 1) * 216, -176)
        b:SetScript("OnClick", function()
            Rules.pickedStyle = st
            Rules:RefreshStyle()
            Rules:LayoutShort()
        end)
        b:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:AddLine(L["SETUP_STYLE_" .. st:upper()], 1, 0.82, 0)
            GameTooltip:AddLine(L["SETUP_STYLE_" .. st:upper() .. "_TT"], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b.style = st
        f.styleButtons[i] = b
    end
    f.styleDesc = Text(short, "GameFontNormalSmall", SOFT, W - 48)
    f.styleDesc:SetPoint("TOPLEFT", 0, -208)

    -------------------------------------------------------------------
    -- Lange Ansicht: alle Regeln zum Scrollen
    -------------------------------------------------------------------
    local scroll, child = UI.ScrollArea(f, "SocializeMeForeverRulesScroll")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -54)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 66)
    child:SetWidth(W - 60)
    local text = Text(child, "GameFontNormal", nil, W - 64)
    text:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    f.text, f.scroll, f.child = text, scroll, child

    -- Knöpfe unten
    local accept = UI.Button(f, "SocializeMeForeverRulesAccept", 200, 26, L.RULES_ACCEPT)
    accept:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 24)
    accept:SetScript("OnClick", function()
        if Rules:Accepted() then
            -- nur die Frage (z. B. /sm einrichten): Stil übernehmen, fertig
            Rules:ApplyStyle(Rules.pickedStyle or Rules:Style())
            SM.db.ui.setupDone = true
            f:Hide()
            SM:Print(L.SETUP_FINISHED)
        else
            Rules:Accept()
        end
    end)
    f.accept = accept

    local later = UI.Button(f, "SocializeMeForeverRulesLater", 200, 26, L.RULES_LATER_BTN)
    later:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 24)
    later:SetScript("OnClick", function()
        if f.fullFromShort then Rules:ShowShort() return end -- "Zurück" zur kurzen Ansicht
        f:Hide()
        if not Rules:Accepted() then SM:Print(L.RULES_LATER) end
    end)
    f.later = later

    tinsert(UISpecialFrames, "SocializeMeForeverRules")
    f:Hide()
end

function Rules:RefreshStyle()
    local f = self.frame
    local cur = self.pickedStyle or self:Style()
    for _, b in ipairs(f.styleButtons) do
        if b.style == cur then b:LockHighlight() else b:UnlockHighlight() end
    end
    f.styleDesc:SetText(L["SETUP_STYLE_" .. cur:upper() .. "_TT"])
end

-- Untereinander nach der echten Texthöhe (lange Übersetzungen schieben den Rest nach unten)
local function TH(fs, minH)
    local h = fs.GetStringHeight and fs:GetStringHeight() or 0
    return math.max(minH or 12, math.ceil(tonumber(h) or 0))
end
function Rules:LayoutShort()
    local f = self.frame
    local y = 0
    local function At(obj, x, h, gap)
        obj:ClearAllPoints()
        obj:SetPoint("TOPLEFT", f.short, "TOPLEFT", x, y)
        y = y - h - gap
    end
    At(f.intro, 0, TH(f.intro), 8)
    At(f.lines, 6, TH(f.lines, 48), 12)
    At(f.readAll, 0, 22, 10)
    At(f.line, 0, 1, 9)
    At(f.styleQ, 0, TH(f.styleQ), 6)
    f.styleButtons[1]:ClearAllPoints()
    f.styleButtons[1]:SetPoint("TOPLEFT", f.short, "TOPLEFT", 0, y)
    f.styleButtons[2]:ClearAllPoints()
    f.styleButtons[2]:SetPoint("TOPLEFT", f.short, "TOPLEFT", 216, y)
    y = y - 24 - 8
    At(f.styleDesc, 0, TH(f.styleDesc, 24), 0)
    -- Fenster so hoch wie nötig: Kopf 54, Inhalt, Knöpfe unten 60
    f:SetHeight(math.max(H_SHORT, 54 + (-y) + 70))
end

-- Kurze Ansicht (erster Start, oder /sm einrichten): drei Zeilen + "Wie magst du es?"
function Rules:ShowShort()
    self:Build()
    local f = self.frame
    f.fullFromShort = nil
    f.scroll:Hide()
    f.short:Show()
    f.title:SetText(L.RULES_WELCOME)
    f.intro:SetText(L.RULES_SHORT_INTRO)
    f.lines:SetText(L.RULES_SHORT)
    self:RefreshStyle()
    self:LayoutShort()
    f.accept:Show()
    f.accept:Enable()
    f.later:Show()
    if self:Accepted() then
        f.accept:SetText(L.SETUP_DONE)
        f.later:Hide()
        f.accept:ClearAllPoints()
        f.accept:SetPoint("BOTTOM", f, "BOTTOM", 0, 24)
    else
        f.accept:SetText(L.RULES_ACCEPT)
        f.later:SetText(L.RULES_LATER_BTN)
        f.accept:ClearAllPoints()
        f.accept:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 24)
        f.later:ClearAllPoints()
        f.later:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 24)
    end
    f:Show()
end

-- Lange Ansicht: alle Regeln. fromShort = aus der kurzen Ansicht ("Zurück" statt "Schließen")
function Rules:ShowFull(fromShort)
    self:Build()
    local f = self.frame
    f.fullFromShort = fromShort or nil
    f:SetHeight(H_FULL)
    f.short:Hide()
    f.scroll:Show()
    f.title:SetText(L.RULES_TITLE)
    f.text:SetText(L.RULES_TEXT)
    local h = f.text.GetStringHeight and f.text:GetStringHeight()
    f.child:SetHeight((type(h) == "number" and h > 0) and (h + 10) or 900)
    if f.scroll.ScrollTo then f.scroll:ScrollTo(0) end
    f.accept:Hide()
    f.later:Show()
    f.later:SetText(fromShort and L.RULES_BACK or L.RULES_CLOSE)
    f.later:ClearAllPoints()
    f.later:SetPoint("BOTTOM", f, "BOTTOM", 0, 24)
    f:Show()
end

-- Zeigt die Regeln: wer noch nicht zugestimmt hat, die kurze Ansicht; sonst alles zum Nachlesen.
function Rules:Show()
    self.pickedStyle = nil
    if self:Accepted() then self:ShowFull() else self:ShowShort() end
end

SM:RegisterCommand("regeln", function() Rules:ShowFull() end, "rules")

-- Frühere "Einrichtung": heute nur noch die Frage "eher ruhig / gern gesprächig"
SM.Setup = {
    Show = function()
        Rules.pickedStyle = nil
        Rules:ShowShort()
    end,
}
SM:RegisterCommand("einrichten", function() SM.Setup.Show() end, "setup")
