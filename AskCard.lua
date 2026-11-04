local ADDON, SM = ...
local M = SM.Media

-- Kleine Frage-Karte mit bis zu drei Knöpfen ("Musik für den Weg?", "Lagerfeuer-Pin setzen?" ...).
-- Läuft immer über SM:Popup: hast du die Karte oft gleich zugemacht, kommt nur eine Chat-Zeile,
-- im Kampf / in Instanzen wartet die Karte bis danach.
--   SM.AskCard:Ask(key, text, { { label, function }, ... }, chatLine)
local Ask = {}
SM.AskCard = Ask

local ink = M.colors.ink
local WIDTH, HEIGHT = 360, 116

function Ask:Build()
    if self.frame then return end
    local UI = SM.UI
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "SocializeMeForeverAsk", UIParent, template)
    self.frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("TOP", UIParent, "TOP", 0, -250)
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
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("TOPLEFT", 18, -18)
    f.text:SetPoint("TOPRIGHT", -30, -18)
    f.text:SetHeight(50)
    f.text:SetJustifyH("LEFT")
    f.text:SetJustifyV("TOP")
    f.text:SetTextColor(ink[1], ink[2], ink[3])
    f.text:SetShadowOffset(0, 0)
    f.buttons = {}
    for i = 1, 3 do
        local b = UI.Button(f, "SocializeMeForeverAskBtn" .. i, 104, 22, "")
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16 + (i - 1) * 110, 14)
        b:SetScript("OnClick", function(btn)
            local fn = btn.action
            f:Hide()
            if fn then SM.SafeCall(fn) end
        end)
        f.buttons[i] = b
    end
    local close = UI.CloseButton(f, function() f:Hide() end)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
    tinsert(UISpecialFrames, "SocializeMeForeverAsk")
    f:Hide()
end

function Ask:ShowNow(text, buttons)
    self:Build()
    local f = self.frame
    f.text:SetText(text)
    for i, b in ipairs(f.buttons) do
        local o = buttons[i]
        if o then
            b:SetText(o[1])
            b.action = o[2]
            b:Show()
        else
            b.action = nil
            b:Hide()
        end
    end
    f.key = self.pendingKey
    f:Show()
end

-- Gibt true zurück, wenn die Karte sofort erscheint.
function Ask:Ask(key, text, buttons, chatLine)
    return SM:Popup(key, function()
        self.pendingKey = key
        self:ShowNow(text, buttons)
    end, chatLine or (text:gsub("\n", " ")), function() return self.frame end)
end

function Ask:Hide(key)
    if self.frame and self.frame:IsShown() and (not key or self.frame.key == key) then
        self.frame.smUsed = true -- vom Addon zu, nicht von dir (zählt nicht beim Mitlernen)
        self.frame:Hide()
    end
end
