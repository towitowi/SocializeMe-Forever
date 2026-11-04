local ADDON, SM = ...
local L = SM.L
local M = SM.Media
local Q = SM.QuestInfo

-- Beacons als Pins auf der Weltkarte und der Minimap (mit HereBeDragons-Pins).
--
-- Aussehen (eigene Grafiken in Media\pin_*.tga):
--   Messingring + Innenscheibe in der Farbe der Art mit Symbol:
--   Schriftrolle = Quest, gekreuzte Schwerter = Grinden, Stern = Event, Flamme = Lagerfeuer.
--   Grüner Ring = die Quest steht in deinem Questlog, grauer Ring = schon erledigt.
--   Liegen Beacons dicht beieinander, werden sie zu EINEM Pin mit Zahl zusammengefasst.
--
-- Bedienung wie in der Liste: Klick (links oder rechts) = Auswahl (Weg zeigen, Ich komme, Grüßen ...).
-- Pin mit Zahl: Maus darüber zeigt alle, Klick öffnet die Liste.
-- Welche Beacons überhaupt erscheinen, bestimmt der Filter in den Einstellungen (Karte & Weg).
local Pins = SM:NewModule("pins")

local HBDPins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
local HBD = LibStub and LibStub("HereBeDragons-2.0", true)

local WORLD_SIZE, MINI_SIZE = 12, 12   -- etwa so groß wie ein Stadt-Symbol der Karte
local CLUSTER_YARDS = 60         -- so nah beieinander = ein gemeinsamer Pin
local CLUSTER_ZONE = 0.025       -- Ersatz ohne Weltkoordinaten: Anteil der Zonenbreite
local REBUILD_DELAY = 0.3        -- Sek.: Änderungen gebündelt neu zeichnen
local NEAR_FADE_YARDS = 12       -- stehst du direkt auf einem Pin, wird er auf der Minimap blass
local MAX_TIP_LINES = 12

local TEX = "Interface\\AddOns\\SocializeMeForever\\Media\\"

local function ShowFlag()
    return _G.HBD_PINS_WORLDMAP_SHOW_PARENT or 1
end

Pins.active = { world = {}, mini = {} }  -- Frames, die gerade auf einer Karte liegen
Pins.pool = { world = {}, mini = {} }

local function HexRGB(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

---------------------------------------------------------------------------
-- Ein Pin
---------------------------------------------------------------------------
local function OnEnter(pin)
    local g = pin.group
    if not g then return end
    if #g == 1 then
        if SM.BeaconTip then SM.BeaconTip:Show(pin, g[1], "ANCHOR_RIGHT", "pin") end
        return
    end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L.PIN_GROUP:format(#g), 1, 0.82, 0)
    for i, b in ipairs(g) do
        if i > MAX_TIP_LINES then
            GameTooltip:AddLine(L.PIN_GROUP_MORE:format(#g - MAX_TIP_LINES), 0.8, 0.8, 0.8)
            break
        end
        local r, gg, bb = HexRGB(M.colors.kind[b.kind] or "FFFFFF")
        GameTooltip:AddDoubleLine(("[%s] %s"):format(L["KIND_" .. b.kind], b.title or ""),
            b.own and L.ROW_OWN or b.sender, math.min(1, r + 0.35), math.min(1, gg + 0.35), math.min(1, bb + 0.35), 1, 1, 1)
    end
    GameTooltip:AddLine(L.PIN_GROUP_CLICK, 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function OnLeave()
    if SM.BeaconTip then SM.BeaconTip:Hide() end
    GameTooltip:Hide()
end

local function OnClick(pin, button)
    local g = pin.group
    if not g then return end
    if #g > 1 then
        -- mehrere: die Liste öffnen (alle Zonen, damit wirklich alle drin sind)
        if SM.Window then SM.Window:OpenBeaconList() end
        return
    end
    local b = g[1]
    if not SM.BeaconTip then return end
    SM.BeaconTip:Menu(pin, b) -- Klick = Auswahl, wie in der Liste
end

local function NewPin(size)
    local f = CreateFrame("Button", nil, UIParent)
    f:SetSize(size, size)
    f:EnableMouse(true)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    f.disc = f:CreateTexture(nil, "ARTWORK")
    f.disc:SetAllPoints(f)
    f.frame = f:CreateTexture(nil, "OVERLAY")
    f.frame:SetAllPoints(f)
    f.frame:SetTexture(TEX .. "pin_frame")
    f.stand = f:CreateTexture(nil, "OVERLAY", nil, 1)
    f.stand:SetAllPoints(f)
    f.stand:SetTexture(TEX .. "pin_stand")
    f.count = f:CreateFontString(nil, "OVERLAY", size >= 20 and "GameFontNormal" or "GameFontNormalSmall")
    f.count:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.count:SetTextColor(1, 0.95, 0.8)

    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(f)
    hl:SetTexture(TEX .. "pin_stand")
    hl:SetVertexColor(1, 1, 1, 0.5)

    f:SetScript("OnEnter", OnEnter)
    f:SetScript("OnLeave", OnLeave)
    f:SetScript("OnClick", OnClick)
    return f
end

local function TakePin(which, size)
    local pool = Pins.pool[which]
    local f = table.remove(pool)
    if not f then f = NewPin(size) end
    f:SetAlpha(1)
    f:Show()
    return f
end

local function GivePin(which, f)
    f.group = nil
    f:Hide()
    local pool = Pins.pool[which]
    pool[#pool + 1] = f
end

-- Aussehen für eine Gruppe (ein oder mehrere Beacons)
local function Paint(f, group, byID)
    if #group > 1 then
        f.disc:SetTexture(TEX .. "pin_cluster")
        f.count:SetText(#group > 9 and "9+" or tostring(#group))
        f.count:Show()
        f.stand:Hide()
        return
    end
    local b = group[1]
    f.count:Hide()
    f.disc:SetTexture(TEX .. "pin_" .. (M.colors.kind[b.kind] and b.kind or "quest"))
    local stand = b.questID and Q:OwnStand(b.questID, byID)
    if stand == "log" or stand == "ready" or stand == "done" then
        f.stand:SetVertexColor(HexRGB(M.colors.stand[stand]))
        f.stand:Show()
    else
        f.stand:Hide()
    end
end

---------------------------------------------------------------------------
-- Zusammenfassen: Beacons, die dicht beieinanderliegen, bilden eine Gruppe
---------------------------------------------------------------------------
local function Place(b)
    if HBD and HBD.GetWorldCoordinatesFromZone then
        local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(b.x, b.y, b.mapID)
        if wx and wy then return inst, wx, wy, true end
    end
    return b.mapID, b.x, b.y, false
end

function Pins:Groups(list)
    local groups = {}
    for _, b in ipairs(list) do
        local key, x, y, yards = Place(b)
        local home
        for _, g in ipairs(groups) do
            if g.key == key and g.yards == yards then
                local dx, dy = g.x - x, g.y - y
                local limit = yards and CLUSTER_YARDS or CLUSTER_ZONE
                if dx * dx + dy * dy <= limit * limit then home = g break end
            end
        end
        if home then
            home[#home + 1] = b
        else
            groups[#groups + 1] = { b, key = key, x = x, y = y, yards = yards }
        end
    end
    return groups
end

-- Alle Beacons, die der Filter durchlässt; eigene zuerst, dann die neuesten
function Pins:Visible(byID)
    local list = {}
    for _, b in pairs(SM.Beacon.cache) do
        if SM.Beacon:PassesFilter(b, byID) then list[#list + 1] = b end
    end
    table.sort(list, function(a, b)
        if (a.own and true or false) ~= (b.own and true or false) then return a.own and true or false end
        if a.created ~= b.created then return (a.created or 0) > (b.created or 0) end
        return a.key < b.key
    end)
    return list
end

function Pins:Clear()
    if HBDPins then
        pcall(HBDPins.RemoveAllWorldMapIcons, HBDPins, self)
        pcall(HBDPins.RemoveAllMinimapIcons, HBDPins, self)
    end
    for which, list in pairs(self.active) do
        for _, f in ipairs(list) do GivePin(which, f) end
        self.active[which] = {}
    end
end

function Pins:Rebuild()
    self:Clear()
    if not (self.enabled and HBDPins) then return end
    local db = SM.db.pins
    local _, byID = Q:ScanLog()
    local groups = self:Groups(self:Visible(byID))
    for _, g in ipairs(groups) do
        local first = g[1]
        if db.world then
            local f = TakePin("world", WORLD_SIZE)
            f.group = g
            Paint(f, g, byID)
            local ok, added = pcall(HBDPins.AddWorldMapIconMap, HBDPins, self, f, first.mapID, first.x, first.y, ShowFlag())
            if ok and added then table.insert(self.active.world, f) else GivePin("world", f) end
        end
        if db.minimap then
            local f = TakePin("mini", MINI_SIZE)
            f.group = g
            Paint(f, g, byID)
            local ok, added = pcall(HBDPins.AddMinimapIconMap, HBDPins, self, f, first.mapID, first.x, first.y, true, true)
            if ok and added then
                -- unter fremden Symbolen bleiben (z. B. Questgeber anderer Addons)
                if Minimap and Minimap.GetFrameLevel then f:SetFrameLevel(Minimap:GetFrameLevel() + 1) end
                table.insert(self.active.mini, f)
            else
                GivePin("mini", f)
            end
        end
    end
    self.groups = groups
end

-- Viele Änderungen kurz hintereinander nur einmal zeichnen
function Pins:QueueRebuild()
    if self.rebuildPending then return end
    self.rebuildPending = true
    C_Timer.After(REBUILD_DELAY, function()
        self.rebuildPending = false
        if self.enabled then self:Rebuild() end
    end)
end

-- Stehst du direkt auf einem Pin, verdeckt er auf der Minimap nicht deinen Pfeil.
function Pins:FadeNear()
    if not (HBDPins and HBDPins.GetVectorToIcon) then return end
    for _, f in ipairs(self.active.mini) do
        local ok, _, dist = pcall(HBDPins.GetVectorToIcon, HBDPins, f)
        f:SetAlpha((ok and dist and dist < NEAR_FADE_YARDS) and 0.35 or 1)
    end
end

---------------------------------------------------------------------------
-- Modul-Lebenszyklus
---------------------------------------------------------------------------
function Pins:OnEnable()
    if not HBDPins then
        SM:Debug("HereBeDragons-Pins not available - map pins are off")
        return
    end
    self:Rebuild()
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_ACCEPTED" }) do
        SM:RegisterEvent(self, event, function()
            if Q:IsOwnEvent() then return end
            self:QueueRebuild()
        end)
    end
    self.fader = C_Timer.NewTicker(1, function() self:FadeNear() end)
end

function Pins:OnDisable()
    self:Clear()
    self.rebuildPending = false
    if self.fader then self.fader:Cancel(); self.fader = nil end
end

-- Früher hießen die Aufrufe Add/Remove/Recolor - heute zeichnet jede Änderung neu (gebündelt).
for _, ev in ipairs({ "BEACON_ADDED", "BEACON_REMOVED", "BEACON_UPDATED", "PIN_FILTER_CHANGED" }) do
    SM:RegisterCallback(ev, function()
        if Pins.enabled then Pins:QueueRebuild() end
    end)
end
