local ADDON, SM = ...
local L = SM.L

-- Lore-Häppchen: kurze Zonen-Geschichten beim Betreten einer Zone (mit Willkommen), beim Angeln,
-- an Aussichtspunkten oder auf Wunsch. Mehr zum Lesen: /sm lore öffnet den Lore-Leser.
-- Pro Zone höchstens alle paar Minuten (Einstellung, mindestens 5), bei "Nicht stören" gar nicht.
local Lore = SM:NewModule("lore")

Lore.lastShown = {}    -- mapID -> GetTime()
Lore.lastText = {}     -- mapID -> zuletzt gezeigter Index

local function Data()
    local D = SM.LoreData
    local lang = (SM.locale == "deDE") and "de" or "en"
    return D[lang], D.fish[lang]
end

local function PlayerMapID()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
end

local function MapName(mapID)
    return mapID and SM:MapName(mapID) or "?"
end

local function Pick(list, key)
    if not list or #list == 0 then return nil end
    local i = math.random(#list)
    if #list > 1 and i == Lore.lastText[key] then i = (i % #list) + 1 end
    Lore.lastText[key] = i
    return list[i]
end

function Lore:Interval()
    return math.max(5, SM.db.lore.interval or 5) * 60
end

-- Zeigt (vielleicht) ein Häppchen. kind: "zone", "fish" oder "spot". force = Wartezeit ignorieren (/sm lore).
-- welcome = Zonenwechsel: vorne "Willkommen in <Zone>!".
-- Gibt den Text zurück, wenn einer gezeigt wurde.
function Lore:Offer(kind, mapID, force, welcome)
    if not self.enabled or (SM:IsDND() and not force) then return nil end
    mapID = mapID or PlayerMapID()
    local key = (kind == "fish" and "fish:" or "") .. tostring(mapID)
    local now = GetTime()
    if not force and self.lastShown[key] and (now - self.lastShown[key]) < self:Interval() then return nil end

    local zones, fish = Data()
    local text
    if kind == "fish" and (not zones[mapID] or math.random(2) == 1) then
        text = Pick(fish, "fish")
    else
        text = Pick(zones[mapID], mapID)
    end
    if not text then return nil end
    self.lastShown[key] = now
    local head = L.LORE_PREFIX
    if welcome then head = L.LORE_WELCOME:format(MapName(mapID)) end
    print(SM.COLOR .. head .. "|r " .. text .. "  " .. L.LORE_READ_HINT)
    return text
end

-- Beim Betreten einer neuen Zone: kurzes Willkommen mit einem Häppchen - nicht im Kampf,
-- nicht in Instanzen, nicht bei "Nicht stören", je Zone einmal pro Spielsitzung.
function Lore:OnZoneChanged()
    if not self.enabled or SM.db.lore.onZone == false or SM:IsDND() or SM:Calm() then return end
    local mapID = PlayerMapID()
    if not mapID or mapID == self.lastZone then return end
    self.lastZone = mapID
    -- test8b: je Zone nur einmal pro Spielsitzung (nach dem nächsten Einloggen wieder)
    self.zoneSeen = self.zoneSeen or {}
    if self.zoneSeen[mapID] then return end
    self.zoneSeen[mapID] = true
    self:Offer("zone", mapID, false, true)
end

function Lore:OnEnable()
    -- kurz warten: nach dem Ladebildschirm stimmt die Karte erst einen Moment später
    SM:RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", function()
        C_Timer.After(3, function() Lore:OnZoneChanged() end)
    end)
end

-- /sm lore öffnet den Lore-Leser (Geschichten zum Lesen), /sm lore chat zeigt ein Häppchen im Chat
SM:RegisterCommand("lore", function(rest)
    if not Lore.enabled then SM:Print(L.LORE_OFF) return end
    if (rest or ""):lower() == "chat" then
        if not Lore:Offer("zone", nil, true) then SM:Print(L.LORE_NONE) end
        return
    end
    SM.LoreReader:Open()
end)
