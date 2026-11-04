local ADDON, SM = ...
local L = SM.L
local M = SM.Media

-- Foto-Tipp zu einem Ort: wann und wie das Bild gut wird, welche Taste die Oberfläche
-- ausblendet (aus DEINER Tastenbelegung gelesen) und wo man das Bild zeigen kann.
local Photo = {}
SM.PhotoCard = Photo

local ink = M.colors.ink
local SOFT = M.colors.soft
local LINKS = {
    { id = "classicwow", url = "https://www.reddit.com/r/classicwow/" },
    { id = "wow", url = "https://www.reddit.com/r/wow/" },
}

-- "ALT-Z" -> "Alt+Z" (in der Sprache des Addons)
function Photo.KeyText(action)
    local key = GetBindingKey and GetBindingKey(action)
    if not key or key == "" then return L.KEY_NONE end
    key = key:gsub("ALT%-", L.KEY_ALT .. "+"):gsub("CTRL%-", L.KEY_CTRL .. "+"):gsub("SHIFT%-", L.KEY_SHIFT .. "+")
    key = key:gsub("PRINTSCREEN", L.KEY_PRINT)
    return key
end

function Photo:Build()
    if self.frame then return end
    local UI = SM.UI
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "SocializeMeForeverPhoto", UIParent, template)
    self.frame = f
    f:SetSize(430, 360)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(fr) SM.UI.DragStart(fr) end)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({ edgeFile = M.tex.border, edgeSize = 24, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    end
    local paper = f:CreateTexture(nil, "BACKGROUND")
    paper:SetPoint("TOPLEFT", 8, -8)
    paper:SetPoint("BOTTOMRIGHT", -8, 8)
    paper:SetColorTexture(unpack(M.colors.parchment))
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 20, -18)
    f.title:SetPoint("TOPRIGHT", -36, -18)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.title:SetTextColor(ink[1], ink[2], ink[3])
    f.title:SetShadowOffset(0, 0)
    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.body:SetPoint("TOPLEFT", 20, -46)
    f.body:SetWidth(390)
    f.body:SetHeight(230)
    f.body:SetJustifyH("LEFT")
    f.body:SetJustifyV("TOP")
    f.body:SetTextColor(ink[1], ink[2], ink[3])
    f.body:SetShadowOffset(0, 0)
    f.share = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.share:SetPoint("BOTTOMLEFT", 20, 50)
    f.share:SetWidth(390)
    f.share:SetJustifyH("LEFT")
    f.share:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
    f.share:SetShadowOffset(0, 0)
    f.links = {}
    for i, link in ipairs(LINKS) do
        local b = UI.Button(f, nil, 130, 22, "r/" .. link.id)
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18 + (i - 1) * 136, 18)
        b:SetScript("OnClick", function() SM.CopyDialog:Show(link.url) end)
        f.links[i] = b
    end
    local done = UI.Button(f, nil, 120, 22, L.RULES_CLOSE)
    done:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 18)
    done:SetScript("OnClick", function() f:Hide() end)
    local close = UI.CloseButton(f, function() f:Hide() end)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
    tinsert(UISpecialFrames, "SocializeMeForeverPhoto")
    f:Hide()
end

function Photo:Text(item)
    local lines = {}
    local tip = item and item.photo
    if not tip or tip == "" then tip = L["PHOTO_TIP_" .. ((item and item.cat) or "view")] end
    if tip and not tip:match("^PHOTO_TIP_") then lines[#lines + 1] = tip .. "\n" end
    lines[#lines + 1] = "• " .. L.PHOTO_HIDE_UI:format(Photo.KeyText("TOGGLEUI"))
    lines[#lines + 1] = "• " .. L.PHOTO_SHOT:format(Photo.KeyText("SCREENSHOT"))
    lines[#lines + 1] = "   " .. L.PHOTO_SNIP
    local h, m = 0, 0
    if GetGameTime then h, m = GetGameTime() end
    lines[#lines + 1] = "• " .. L.PHOTO_LIGHT:format(("%02d:%02d"):format(h or 0, m or 0))
    lines[#lines + 1] = "• " .. L.PHOTO_CAMERA
    return table.concat(lines, "\n")
end

function Photo:Show(item)
    self:Build()
    local f = self.frame
    f.title:SetText(L.PHOTO_TITLE:format(item and item.name or L.PLACE_CAT_view))
    f.body:SetText(self:Text(item))
    f.share:SetText(L.PHOTO_SHARE)
    f:Show()
end
