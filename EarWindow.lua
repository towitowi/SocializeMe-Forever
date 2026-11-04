local ADDON, SM = ...
local L = SM.L
local M = SM.Media

-- "Ein offenes Ohr": eine ruhige Karte für Momente, in denen einem alles zu viel wird.
-- Es gibt kein Netzwerk und es wird nichts gesendet. Die Karte zeigt Hilfe-Nummern und zwei
-- Wege zu Menschen - zu denen, die du schon kennst, oder zu einer kleinen Runde:
--   * Kontakte / Freunde anschreiben (Tab Kontakte)
--   * eine Instant-Runde "Einfach plaudern" suchen (Tab Instant)
-- Öffnen: Knopf "Offenes Ohr" oben im Fenster, "Mir ist nach Reden" bei den Kontakten,
-- /sm ohr oder /sm reden (und eine Taste in der Tastenbelegung).
local EarUI = {}
SM.EarUI = EarUI

local W, PAD = 380, 18
local SOFT = M.colors.soft

local function Text(parent, font, color, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWidth(width)
    fs:SetShadowOffset(0, 0)
    color = color or M.colors.ink
    fs:SetTextColor(color[1], color[2], color[3])
    return fs
end

function EarUI:Build()
    if self.frame then return end
    local UI = SM.UI
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "SocializeMeForeverEar", UIParent, template)
    self.frame = f
    f:SetSize(W, 300)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(fr) SM.UI.DragStart(fr) end)
    f:SetScript("OnDragStop", function(fr)
        fr:StopMovingOrSizing()
        local point, _, relPoint, x, y = fr:GetPoint()
        local p = SM.db.ear
        p.point, p.relPoint, p.x, p.y = point, relPoint, x, y
    end)
    if f.SetBackdrop then
        f:SetBackdrop({ edgeFile = M.tex.border, edgeSize = 24, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    end
    local paper = f:CreateTexture(nil, "BACKGROUND")
    paper:SetPoint("TOPLEFT", 8, -8)
    paper:SetPoint("BOTTOMRIGHT", -8, 8)
    paper:SetColorTexture(unpack(M.colors.parchment))

    f.title = Text(f, "GameFontNormalLarge", nil, W - 2 * PAD - 24)
    f.title:SetPoint("TOPLEFT", PAD, -PAD)
    f.title:SetText(L.EAR_TITLE)
    local close = UI.CloseButton(f, function() f:Hide() end)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -12)

    f.body = Text(f, "GameFontNormal", nil, W - 2 * PAD)
    f.body:SetPoint("TOPLEFT", PAD, -PAD - 28)
    f.body:SetText(L.EAR_CARD_TEXT)

    f.help = Text(f, "GameFontNormalSmall", SOFT, W - 2 * PAD)
    f.help:SetText(L.EAR_HELP)

    local function Btn(label, fn, tt)
        local b = UI.Button(f, nil, W - 2 * PAD, 24, label)
        b:SetScript("OnClick", function() fn(); f:Hide() end)
        if tt then
            b:SetScript("OnEnter", function(btn)
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                GameTooltip:AddLine(label, 1, 0.82, 0)
                GameTooltip:AddLine(tt, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return b
    end
    f.contacts = Btn(L.EAR_BTN_CONTACTS, function()
        if SM.Window then SM.Window:OpenTab("contacts") end
    end, L.EAR_BTN_CONTACTS_TT)
    f.instant = Btn(L.EAR_BTN_INSTANT, function()
        SM.db.circle.topic = 1   -- "Einfach plaudern" passt zu jeder Runde
        if SM.Window then SM.Window:OpenTab("instant") end
    end, L.EAR_BTN_INSTANT_TT)
    tinsert(UISpecialFrames, "SocializeMeForeverEar")
    f:Hide()
end

-- Höhe nach dem Text richten (Hilfe-Text ist je nach Sprache verschieden lang)
function EarUI:Layout()
    local f = self.frame
    local bodyH = (f.body.GetStringHeight and f.body:GetStringHeight()) or 60
    if type(bodyH) ~= "number" or bodyH <= 0 then bodyH = 60 end
    local y = -PAD - 28 - bodyH - 12
    f.contacts:ClearAllPoints(); f.contacts:SetPoint("TOPLEFT", PAD, y)
    f.instant:ClearAllPoints(); f.instant:SetPoint("TOPLEFT", PAD, y - 30)
    f.help:ClearAllPoints(); f.help:SetPoint("TOPLEFT", PAD, y - 66)
    local helpH = (f.help.GetStringHeight and f.help:GetStringHeight()) or 50
    if type(helpH) ~= "number" or helpH <= 0 then helpH = 50 end
    f:SetHeight(-(y - 66) + helpH + PAD + 6)
end

-- Neben dem Hauptfenster öffnen (oder dort, wo du die Karte zuletzt hingeschoben hast)
function EarUI:Place()
    local f, p = self.frame, SM.db.ear
    f:ClearAllPoints()
    if p.point then
        f:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
        return
    end
    local main = SM.Window and SM.Window.frame
    if main and main:IsShown() then
        f:SetPoint("TOPLEFT", main, "TOPRIGHT", 4, 0)
    else
        f:SetPoint("CENTER", 0, 80)
    end
end

function EarUI:Show()
    self:Build()
    self:Place()
    self.frame:Show()
    self:Layout()
end

function EarUI:Toggle()
    self:Build()
    if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

-- "Mir ist nach Reden" (Kontakte, /sm reden): dieselbe Karte
function EarUI:AskNow() self:Show() end

SM:RegisterCommand("ohr", function() EarUI:Toggle() end, "ear")
SM:RegisterCommand("reden", function() EarUI:Show() end, "talk")

SM:RegisterPosition(function() return SM.db.ear end, function() return EarUI.frame end,
    function() EarUI:Place() end)
