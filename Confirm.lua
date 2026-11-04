local ADDON, SM = ...
local L = SM.L
local M = SM.Media

-- Kleine Rückfrage im Holz-/Pergament-Look ("Wirklich ignorieren?").
local Confirm = {}
SM.Confirm = Confirm

function Confirm:Create()
    if self.frame then return end
    local UI = SM.UI
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "SocializeMeForeverConfirm", UIParent, template)
    self.frame = f
    f:SetSize(380, 130)
    f:SetPoint("CENTER", 0, 140)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    if f.SetBackdrop then
        f:SetBackdrop({ edgeFile = M.tex.border, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    end
    local paper = f:CreateTexture(nil, "BACKGROUND")
    paper:SetPoint("TOPLEFT", 11, -11)
    paper:SetPoint("BOTTOMRIGHT", -11, 11)
    paper:SetColorTexture(unpack(M.colors.parchment))

    local ink = M.colors.ink
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 24, -26)
    text:SetPoint("TOPRIGHT", -24, -26)
    text:SetHeight(50)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("TOP")
    text:SetTextColor(ink[1], ink[2], ink[3])
    text:SetShadowOffset(0, 0)
    self.text = text

    local yes = UI.Button(f, "SocializeMeForeverConfirmYes", 140, 24, L.CONFIRM_YES)
    yes:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 22)
    yes:SetScript("OnClick", function()
        f:Hide()
        local fn = Confirm.onYes
        Confirm.onYes = nil
        if fn then SM.SafeCall(fn) end
    end)
    self.yes = yes

    local no = UI.Button(f, "SocializeMeForeverConfirmNo", 140, 24, L.CONFIRM_NO)
    no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 22)
    no:SetScript("OnClick", function() Confirm.onYes = nil; f:Hide() end)
    self.no = no

    tinsert(UISpecialFrames, "SocializeMeForeverConfirm")
    f:Hide()
end

-- yesText / noText (freiwillig): andere Beschriftung, z. B. "Trotzdem beitreten" / "Abbrechen"
function Confirm:Show(message, onYes, yesText, noText)
    self:Create()
    self.onYes = onYes
    self.text:SetText(message)
    self.yes:SetText(yesText or L.CONFIRM_YES)
    self.no:SetText(noText or L.CONFIRM_NO)
    self.frame:Show()
end
