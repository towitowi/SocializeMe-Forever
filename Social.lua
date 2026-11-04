local ADDON, SM = ...
local L = SM.L
local M = SM.Media

-- Miteinander: alles, was die Hürde senkt, mit anderen zu spielen.
--   * Sprachchat-Stufe eines Beacons: 0 = nur Text, 1 = Sprachchat, 2 = Sprachchat, Zuhören okay
--   * freiwilliges Kürzel "eher ruhig" (bei eigenen Beacons sichtbar)
--   * Begrüßung zur Auswahl (freundlich, eher ruhig, kurz)
--   * Schnellsätze in der Gruppe und "Freundlich verabschieden"
--   * darunter die Spaß-Töne (Modules/Soundboard.lua)
local Social = {}
SM.Social = Social

Social.VOICE_TEXT, Social.VOICE, Social.VOICE_LISTEN = 0, 1, 2

-- Sprachchat-Stufe aus beliebiger Angabe (true/false, Zahl, Text) auf 0-2 bringen.
function Social.VoiceLevel(v)
    if v == true then return 1 end
    v = tonumber(v) or 0
    if v < 0 or v > 2 then return 0 end
    return math.floor(v)
end

-- Kurzes Kürzel für die Listenzeile (leer bei "nur Text")
function Social.VoiceTag(level)
    level = Social.VoiceLevel(level)
    if level == 1 then return L.VOICE_SHORT end
    if level == 2 then return L.VOICE_SHORT_2 end
    return nil
end

-- Zeile fürs Tooltip
function Social.VoiceLine(level)
    return L["TT_VOICE_" .. Social.VoiceLevel(level)]
end

function Social:IsQuiet()
    return SM.db and SM.db.social and SM.db.social.quiet and true or false
end

---------------------------------------------------------------------------
-- Begrüßungen
---------------------------------------------------------------------------
-- Seit test8 ohne eigene Einstellung: die Begrüßung folgt deinem Kürzel. Mit "eher ruhig"
-- grüßt du ruhig, sonst freundlich. (Die kurze Begrüßung gibt es nur noch für alte Aufrufe.)
Social.GREETINGS = 3

function Social:GreetingStyle()
    return self:IsQuiet() and 2 or 1
end

-- Text für ein Beacon (%s = Titel)
function Social:BeaconGreeting(title)
    local key = ({ "WHISPER_HELLO", "GREET_QUIET", "GREET_SHORT" })[self:GreetingStyle()]
    return L[key]:format(title)
end

---------------------------------------------------------------------------
-- Schnellsätze in der Gruppe
---------------------------------------------------------------------------
local PHRASES = {
    { key = "hello", button = "QSB_HELLO", text = "QS_HELLO" },
    { key = "thanks", button = "QSB_THANKS", text = "QS_THANKS" },
    { key = "gg", button = "QSB_GG", text = "QS_GG" },
    { key = "afk", button = "QSB_AFK", text = "QS_AFK" },
    { key = "back", button = "QSB_BACK", text = "QS_BACK" },
    { key = "bye", button = "QSB_BYE" },
}
Social.PHRASES = PHRASES
local SAY_LOCK = 2            -- Sek. zwischen zwei Schnellsätzen (kein Versehens-Spam)
local LEAVE_DELAY = 1.5       -- Sek.: erst verabschieden, dann die Gruppe verlassen

Social.lastSay = -math.huge

local function InGroup()
    return (type(IsInGroup) == "function" and IsInGroup()) or (type(IsInRaid) == "function" and IsInRaid()) or false
end

local function GroupChannel()
    if type(IsInRaid) == "function" and IsInRaid() then return "RAID" end
    return "PARTY"
end

-- Sagt einen Satz in der Gruppe. Gibt true zurück, wenn er rausging.
function Social:Say(text)
    if not InGroup() then
        -- nicht still ins Leere klicken lassen (Probe zeigt die Leiste auch ohne Gruppe)
        SM:Print(L.SAY_NO_GROUP)
        return false
    end
    local now = GetTime()
    if (now - self.lastSay) < SAY_LOCK then return false end
    local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not fn or not pcall(fn, text, GroupChannel()) then return false end
    self.lastSay = now
    return true
end

function Social:LeaveGroup()
    local fn = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
    if fn then pcall(fn) end
end

-- Bedankt sich und verlässt dann die Gruppe (nach einer Rückfrage).
function Social:Farewell(skipConfirm)
    if not InGroup() then return false end
    local function go()
        self.lastSay = -math.huge
        if self:Say(L.QS_BYE) then
            C_Timer.After(LEAVE_DELAY, function() self:LeaveGroup() end)
        else
            self:LeaveGroup()
        end
    end
    if skipConfirm then go() else SM.Confirm:Show(L.QS_BYE_ASK:format(L.QS_BYE), go) end
    return true
end

local BAR_W, BAR_H = 336, 82
local SOUND_ROW_H = 72        -- Überschrift + zwei Reihen Spaß-Töne
local SOUND_W = 78

function Social:BuildBar()
    if self.bar then return end
    local UI = SM.UI
    local f = CreateFrame("Frame", "SocializeMeForeverQuickBar", UIParent)
    self.bar = f
    f:SetSize(BAR_W, BAR_H)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(fr) SM.UI.DragStart(fr) end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relPoint, x, y = frame:GetPoint()
        local s = SM.db.social
        s.point, s.relPoint, s.x, s.y = point, relPoint, x, y
    end)
    local s = SM.db.social
    if s.point then
        f:SetPoint(s.point, UIParent, s.relPoint or s.point, s.x or 0, s.y or 0)
    else
        f:SetPoint("LEFT", UIParent, "LEFT", 20, -60)
    end

    local panel = UI.Panel(f, nil, M.colors.wood)
    panel:SetAllPoints(f)
    UI.AddGrain(panel, BAR_W, BAR_H, "ARTWORK")
    local tx = M.wood.text
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -6)
    title:SetTextColor(tx[1], tx[2], tx[3])
    title:SetShadowOffset(0, 0)
    title:SetText(L.QS_TITLE)
    f.title = title

    f.buttons = {}
    for i, p in ipairs(PHRASES) do
        local b = UI.Button(panel, nil, 104, 22, L[p.button])
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", 8 + col * 108, -24 - row * 26)
        b:SetScript("OnClick", function()
            if p.key == "bye" then
                Social:Farewell()
            else
                Social:Say(L[p.text])
            end
        end)
        b:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:AddLine(p.key == "bye" and L.QS_BYE_TT or L[p.text], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.buttons[p.key] = b
    end

    -- Spaß-Töne: hören nur Gruppenmitglieder mit dem Addon (siehe Modules/Soundboard.lua)
    local snd = CreateFrame("Frame", nil, panel)
    snd:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -BAR_H + 6)
    snd:SetSize(BAR_W, SOUND_ROW_H)
    f.soundRow = snd
    UI.AddGrain(snd, BAR_W, SOUND_ROW_H, "ARTWORK")
    local st = snd:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    st:SetPoint("TOPLEFT", snd, "TOPLEFT", 8, -2)
    st:SetTextColor(tx[1], tx[2], tx[3])
    st:SetShadowOffset(0, 0)
    st:SetText(L.SND_TITLE)
    snd.buttons = {}
    for i, s in ipairs(SM.Soundboard.SOUNDS) do
        local b = UI.Button(snd, nil, SOUND_W, 22, L[s.name])
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        b:SetPoint("TOPLEFT", snd, "TOPLEFT", 8 + col * (SOUND_W + 4), -18 - row * 26)
        b:SetScript("OnClick", function()
            local ok, msg = SM.Soundboard:Play(s.key)
            if not ok and msg then SM:Print(msg) end
        end)
        b:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:AddLine(L[s.name], 1, 0.82, 0)
            GameTooltip:AddLine(L.SND_TT, 1, 1, 1, true)
            local wait = SM.Soundboard:Wait()
            if wait > 0 then GameTooltip:AddLine(L.SND_WAIT:format(wait), 1, 0.6, 0.4, true) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        snd.buttons[i] = b
    end

    local close = UI.CloseButton(panel, function()
        f:Hide()
        Social.barClosed = true    -- erst in der nächsten Gruppe wieder
    end)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -3)
    f:Hide()
end

-- Ton-Reihe zeigen oder ausblenden; in der Pause sind die Knöpfe blasser
function Social:RefreshSoundRow()
    local f = self.bar
    if not f then return end
    local on = SM.Soundboard and SM.Soundboard:Enabled()
    if on then
        f.soundRow:Show()
        f:SetHeight(BAR_H + SOUND_ROW_H - 6)
        local alpha = SM.Soundboard:Wait() > 0 and 0.5 or 1
        for _, b in ipairs(f.soundRow.buttons) do b:SetAlpha(alpha) end
    else
        f.soundRow:Hide()
        f:SetHeight(BAR_H)
    end
end

-- Leiste zeigen, solange man in einer Gruppe ist (und es eingeschaltet ist).
function Social:UpdateBar()
    if not SM.db then return end
    if not SM:Active() then
        if self.bar then self.bar:Hide() end
        return
    end
    local inGroup = InGroup()
    if not inGroup then
        self.barClosed = false
        if self.bar then self.bar:Hide() end
        return
    end
    if not SM.db.social.quickbar or self.barClosed then
        if self.bar then self.bar:Hide() end
        return
    end
    self:BuildBar()
    self:RefreshSoundRow()
    self.bar:Show()
end

SM:RegisterEvent(Social, "GROUP_ROSTER_UPDATE", function() Social:UpdateBar() end)
SM:RegisterEvent(Social, "PARTY_MEMBERS_CHANGED", function() Social:UpdateBar() end) -- ältere Clients
SM:RegisterCallback("READY", function() Social:UpdateBar() end)

SM:RegisterPosition(function() return SM.db.social end, function() return Social.bar end,
    function(f) f:SetPoint("LEFT", UIParent, "LEFT", 20, -60) end)
