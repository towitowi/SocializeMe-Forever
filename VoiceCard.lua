local ADDON, SM = ...
local L = SM.L
local M = SM.Media

-- Sprachchat-Spickzettel: Sätze zum Vorlesen (für den Einstieg, mittendrin, zum Abschied) und
-- kurze Benimmregeln. Es wird nichts gesendet - die Sätze sind nur eine Hilfe für dich.
-- Öffnen: Knopf "Spickzettel" bei den Beacons, /sm sprachchat, und einmal von selbst, wenn du
-- dich an ein Lagerfeuer mit Sprachchat setzt oder dein erstes Beacon mit Sprachchat entzündest.
local Card = {}
SM.VoiceCard = Card

local ink = M.colors.ink

function Card:Build()
    if self.frame then return end
    local UI = SM.UI
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "SocializeMeForeverVoice", UIParent, template)
    self.frame = f
    f:SetSize(470, 470)
    f:SetPoint("CENTER", 0, 30)
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
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetTextColor(ink[1], ink[2], ink[3])
    title:SetShadowOffset(0, 0)
    title:SetText(L.VOICE_CARD_TITLE)

    local scroll, child = UI.ScrollArea(f, "SocializeMeForeverVoiceScroll")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 50)
    child:SetWidth(414)
    local body = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    body:SetPoint("TOPLEFT", 0, -3) -- kleiner Abstand: sonst wird die erste Zeile oben angeschnitten
    body:SetWidth(410)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetTextColor(ink[1], ink[2], ink[3])
    body:SetShadowOffset(0, 0)
    f.body, f.child, f.scroll = body, child, scroll

    local done = UI.Button(f, nil, 140, 24, L.RULES_CLOSE)
    done:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
    done:SetScript("OnClick", function() f:Hide() end)
    local close = UI.CloseButton(f, function() f:Hide() end)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
    tinsert(UISpecialFrames, "SocializeMeForeverVoice")
    f:Hide()
end

function Card:Text()
    local me = UnitName("player") or "?"
    local lines = { L.VOICE_CARD_INTRO, "" }
    local function Section(head, list)
        lines[#lines + 1] = SM.Hex("7A4A00") .. head .. "|r"
        for _, s in ipairs(list) do lines[#lines + 1] = "  " .. s end
        lines[#lines + 1] = ""
    end
    Section(L.VOICE_HDR_HELLO, { L.VOICE_HELLO_1, L.VOICE_HELLO_2:format(me), L.VOICE_HELLO_3 })
    Section(L.VOICE_HDR_DURING, { L.VOICE_DURING_1, L.VOICE_DURING_2, L.VOICE_DURING_3, L.VOICE_DURING_4 })
    Section(L.VOICE_HDR_BYE, { L.VOICE_BYE_1, L.VOICE_BYE_2 })
    Section(L.VOICE_HDR_RULES, { L.VOICE_RULE_1, L.VOICE_RULE_2, L.VOICE_RULE_3, L.VOICE_RULE_4,
        L.VOICE_RULE_5, L.VOICE_RULE_6, L.VOICE_RULE_7 })
    return table.concat(lines, "\n")
end

function Card:Show()
    self:Build()
    local f = self.frame
    f.body:SetText(self:Text())
    local h = (f.body.GetStringHeight and f.body:GetStringHeight()) or 600
    f.child:SetHeight((type(h) == "number" and h or 600) + 13)
    if f.scroll.ScrollTo then f.scroll:ScrollTo(0) end
    f:Show()
    SM.db.social.voiceCardSeen = true
end

function Card:Toggle()
    self:Build()
    if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

-- Früher kam der Spickzettel einmal von selbst. Seit test8b (weniger Fenster) nur noch über den
-- Knopf "Spickzettel" oder /sm sprachchat.
function Card:OfferOnce()
    return false
end

SM:RegisterCommand("sprachchat", function() Card:Toggle() end, "voice")
