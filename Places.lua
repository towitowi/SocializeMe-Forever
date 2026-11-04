local ADDON, SM = ...
local L = SM.L

-- Orte: schöne Plätze und wichtige Punkte einer Zone.
--
-- Woher die Orte kommen:
--   * Startliste des Addons (Modules\PlacesData.lua), nur in WoW Forever
--   * deine eigenen Orte ("Hier merken" im Tab Orte) und Orte, die du eingefügt hast
--   * Lagerfeuer-Beacons in deiner Zone (live)
--
-- Teilen geht ohne Netzwerk: "Teilen" zeigt eine Textzeile zum Kopieren, z. B.
--   [SM] Tor von Orgrimmar @ Durotar 45.7, 12.8 {1411;4570;1280;arch}
-- Die kannst du in den Chat, ins Forum oder in Discord stellen. Wer sie kopiert, fügt sie im
-- Tab Orte mit "Einfügen" ein - dann steht der Ort bei seinen eigenen Orten. Eine Zeile darf
-- mehrere Orte enthalten. Namen laufen durch denselben Filter wie Beacon-Texte.
--
-- Nur bei dir (es wird nichts gesendet): Das Addon merkt sich, wo du repariert, Post geholt,
-- beim Lehrer gelernt usw. hast. Damit schlägt der Warte-Tipp nach deinem Beacon vor, was du
-- in der Wartezeit in der Nähe erledigen kannst.
local Places = SM:NewModule("places")

local HBD = LibStub and LibStub("HereBeDragons-2.0", true)

Places.CATS = { "view", "fish", "arch", "meet" }
Places.POI_TYPES = { "repair", "inn", "flight", "mail", "bank", "auction", "classtrainer", "proftrainer", "stable", "fishtrainer" }
local IS_CAT, IS_POI = {}, {}
for _, c in ipairs(Places.CATS) do IS_CAT[c] = true end
for _, t in ipairs(Places.POI_TYPES) do IS_POI[t] = true end

-- Symbole aus dem Spiel selbst (Blizzards Minimap-Symbole)
Places.POI_ICON = {
    repair = "Interface\\Minimap\\Tracking\\Repair",
    inn = "Interface\\Minimap\\Tracking\\Innkeeper",
    flight = "Interface\\Minimap\\Tracking\\FlightMaster",
    mail = "Interface\\Minimap\\Tracking\\Mailbox",
    bank = "Interface\\Minimap\\Tracking\\Banker",
    auction = "Interface\\Minimap\\Tracking\\Auctioneer",
    classtrainer = "Interface\\Minimap\\Tracking\\Class",
    proftrainer = "Interface\\Minimap\\Tracking\\Profession",
    stable = "Interface\\Minimap\\Tracking\\StableMaster",
    fishtrainer = "Interface\\Icons\\Trade_Fishing",
}
Places.CAT_ICON = {
    view = "Interface\\Icons\\INV_Misc_Spyglass_02",
    fish = "Interface\\Icons\\Trade_Fishing",
    arch = "Interface\\Icons\\INV_Misc_Map_01",
    meet = "Interface\\Icons\\INV_Misc_Horn_01",
}

local SAME_YARDS = 30           -- näher beieinander = derselbe Ort
local SAME_ZONE = 0.015         -- Ersatz ohne Weltkoordinaten
local MAX_ENTRIES = 1500        -- gemerkte nützliche Punkte je Realm
local MAX_IMPORT = 20           -- so viele Orte nimmt "Einfügen" auf einmal

local function Me() return UnitName("player") end

local function Realm()
    return (GetRealmName and GetRealmName()) or "?"
end

function Places:Store()
    local all = SM.db.places
    if not all then all = {}; SM.db.places = all end
    local r = Realm()
    local s = all[r]
    if not s then s = { spots = {}, pois = {} }; all[r] = s end
    return s
end

local function Lang()
    local loc = SM.locale or ""
    if loc == "deDE" then return "de" elseif loc == "zhCN" then return "zh" end
    return "en"
end
function Places.Text(t)
    if type(t) ~= "table" then return t end
    return t[Lang()] or t.en or t.de or ""
end

-- Text für Namen (eingefügt oder geteilt): kein Steuerzeichen, kein Trenner, höchstens 40 Zeichen
local function CleanName(name)
    name = tostring(name or ""):gsub("|", ""):gsub(";", ","):gsub("[@{}]", ""):gsub("%c", "")
    name = name:match("^%s*(.-)%s*$") or ""
    return SM.TrimChars(name, 40)
end
Places.CleanName = CleanName

---------------------------------------------------------------------------
-- Gleicher Ort?
---------------------------------------------------------------------------
local function World(mapID, x, y)
    if HBD and HBD.GetWorldCoordinatesFromZone then
        local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(x, y, mapID)
        if wx and wy then return wx, wy, inst end
    end
end

local function Close(a, mapID, x, y)
    if a.m ~= mapID then return false end
    local ax, ay = World(a.m, a.x, a.y)
    local bx, by = World(mapID, x, y)
    if ax and bx then
        local dx, dy = ax - bx, ay - by
        return dx * dx + dy * dy <= SAME_YARDS * SAME_YARDS
    end
    local dx, dy = a.x - x, a.y - y
    return dx * dx + dy * dy <= SAME_ZONE * SAME_ZONE
end

-- Nützlichen Punkt hinzufügen oder auffrischen. Gibt den Eintrag und true (= neu) zurück.
function Places:Merge(which, mapID, x, y, kind, name, who)
    local list = self:Store()[which]
    local now = time()
    for _, e in ipairs(list) do
        if e.c == kind and Close(e, mapID, x, y) then
            e.by = e.by or {}
            e.by[who] = now
            e.t = now
            if (not e.n or e.n == "") and name and name ~= "" then e.n = name end
            return e, false
        end
    end
    if #list >= MAX_ENTRIES then self:Prune(which) end
    local e = { m = mapID, x = x, y = y, c = kind, n = name, by = { [who] = now }, t = now }
    list[#list + 1] = e
    return e, true
end

-- Bei vollem Speicher die ältesten nützlichen Punkte entfernen
function Places:Prune(which)
    local list = self:Store()[which]
    if #list < MAX_ENTRIES then return end
    table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
    for i = #list, MAX_ENTRIES - 100, -1 do table.remove(list, i) end
end

---------------------------------------------------------------------------
-- Meine Position
---------------------------------------------------------------------------
function Places:PlayerPos()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y
    if pos and pos.GetXY then x, y = pos:GetXY() end
    if not x or not y or (x == 0 and y == 0) then return nil end
    return mapID, x, y
end

local function Round(v) return math.floor(v * 10000 + 0.5) / 10000 end

---------------------------------------------------------------------------
-- Alle Orte einer Zone für die Liste
--   cat: "all", "view", "fish", "arch", "meet", "fire"
-- Jeder Eintrag: { kind, cat, name, mapID, x, y, desc, photo, wiki, count, source, ref }
---------------------------------------------------------------------------
-- Wo liegt ein mitgelieferter Ort? Selbst nachgemessen (Dev) > von 3 Spielern nachgemessen > Liste
local function AddonPos(p)
    local fix = (SM.db.devMeasure or {})[p.key]
    if fix and fix.m == p.m then return fix.x, fix.y end
    if SM.PlaceFix and SM.PlaceFix.Get then
        local fx, fy = SM.PlaceFix:Get(p.key) -- Modules\PlaceFix.lua
        if fx then return fx, fy end
    end
    return p.x, p.y
end

-- Startliste des Addons als Einträge - nur in WoW Forever (für seine neue Grafik ausgesucht und
-- dort vermessen). mapID = nil: alle Karten.
function Places:AddonPlaces(mapID, cat)
    local out = {}
    for _, p in ipairs(SM:IsForever() and SM.PlacesData or {}) do
        local mx, my = AddonPos(p)
        if (not mapID or p.m == mapID) and mx and my and (cat == "all" or cat == p.c) then
            out[#out + 1] = { kind = "place", cat = p.c, name = Places.Text(p.name), mapID = p.m, x = mx, y = my,
                              desc = Places.Text(p.desc), photo = Places.Text(p.photo), wiki = p.wiki, source = "addon", ref = p }
        end
    end
    return out
end

function Places:ForZone(mapID, cat)
    local out = {}
    local function add(t)
        t.dist = SM.Eta and SM.Eta.enabled and SM.Eta:Distance({ mapID = t.mapID, x = t.x, y = t.y }) or nil
        out[#out + 1] = t
    end
    local want = function(c) return cat == "all" or cat == c end

    for _, t in ipairs(self:AddonPlaces(mapID, cat)) do add(t) end
    -- Eigene Aussichtspunkte
    for i, s in ipairs(SM.db.spots or {}) do
        local c = s.c or "view"
        if s.mapID == mapID and want(c) then
            add({ kind = "place", cat = c, name = SM.Chill and SM.Chill:SpotName(s) or s.name or "?", mapID = s.mapID, x = s.x, y = s.y,
                  source = "own", ref = s, ownIndex = i })
        end
    end
    -- Lagerfeuer (live)
    if want("fire") and SM.Beacon then
        for _, b in pairs(SM.Beacon.cache) do
            if b.kind == "campfire" and b.mapID == mapID then
                add({ kind = "fire", cat = "fire", name = b.title ~= "" and b.title or L.KIND_campfire, mapID = b.mapID,
                      x = b.x, y = b.y, source = b.own and "own" or "beacon", beacon = b })
            end
        end
    end
    table.sort(out, function(a, b)
        if a.dist and b.dist then return a.dist < b.dist end
        if a.dist ~= b.dist then return a.dist ~= nil end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

---------------------------------------------------------------------------
-- Eigene Orte merken und teilen
---------------------------------------------------------------------------
function Places:Remember(name, cat)
    return self:RememberAt(name, cat)
end

-- Ort merken - ohne mapID dort, wo du stehst; mit mapID/x/y an dieser Stelle (Weltkarte, Alt+Klick)
function Places:RememberAt(name, cat, mapID, x, y)
    if not SM.Chill then return false, L.MUSIC_OFF_MOD end
    local ok, msg
    if mapID and x and y then ok, msg = SM.Chill:AddSpotAt(name, mapID, x, y)
    else ok, msg = SM.Chill:AddSpot(name) end
    if ok then
        local s = SM.db.spots[#SM.db.spots]
        if s then s.c = IS_CAT[cat] and cat or "view" end
        SM:Fire("PLACES_CHANGED")
    end
    return ok, msg
end

-- Textzeile zum Teilen (siehe oben). Gibt den Text oder nil und eine Meldung zurück.
function Places:ShareText(item)
    if not item or item.kind ~= "place" or not item.mapID or not item.x then return nil, L.PLACE_SHARE_NONE end
    local name = CleanName(item.name)
    local banned, word, why = SM.Filter:Check(name)
    if banned then return nil, SM.Filter:Message(word, why) end
    local zone = CleanName(SM:MapName(item.mapID) or "")
    return ("[SM] %s @ %s %.1f, %.1f {%d;%d;%d;%s}"):format(name, zone, item.x * 100, item.y * 100,
        item.mapID, math.floor(item.x * 10000 + 0.5), math.floor(item.y * 10000 + 0.5), item.cat)
end

local function ValidPos(m, x, y)
    m, x, y = tonumber(m), tonumber(x), tonumber(y)
    if not (m and x and y) or m <= 0 or m > 100000 or x < 0 or x > 10000 or y < 0 or y > 10000 then return nil end
    if C_Map and C_Map.GetMapInfo and not C_Map.GetMapInfo(m) then return nil end -- Karte gibt es hier nicht
    return m, x / 10000, y / 10000
end

-- Geteilte Orte aus einem eingefügten Text übernehmen (zu den eigenen Orten).
-- Gibt ok und eine Meldung zurück.
function Places:Import(text)
    text = tostring(text or "")
    local added, known, bad = 0, 0, 0
    local spots = SM.db.spots
    for chunk, m, x, y, c in text:gmatch("%[SM%]([^{]-){(%d+);(%d+);(%d+);(%a+)}") do
        if added + known + bad >= MAX_IMPORT then break end
        local mapID, px, py = ValidPos(m, x, y)
        local name = CleanName((chunk:match("^(.-)@") or chunk))
        if not mapID or not IS_CAT[c] or SM.Filter:Check(name) then
            bad = bad + 1
        else
            if name == "" then name = L["PLACE_CAT_" .. c] end
            local dupe = false
            for _, sp in ipairs(spots) do
                if (sp.c or "view") == c and Close({ m = sp.mapID, x = sp.x, y = sp.y }, mapID, px, py) then dupe = true end
            end
            if dupe then
                known = known + 1
            else
                local ok, msg = SM.Chill:AddSpotAt(name, mapID, px, py)
                if not ok then
                    if added == 0 then return false, msg end
                    break
                end
                spots[#spots].c = c
                spots[#spots].imported = true
                added = added + 1
            end
        end
    end
    if added + known + bad == 0 then return false, L.PLACE_PASTE_NONE end
    if added > 0 then SM:Fire("PLACES_CHANGED") end
    local msg = L.PLACE_PASTE_DONE:format(added)
    if known > 0 then msg = msg .. " " .. L.PLACE_PASTE_KNOWN:format(known) end
    if bad > 0 then msg = msg .. " " .. L.PLACE_PASTE_BAD:format(bad) end
    return added > 0 or known > 0, msg
end

---------------------------------------------------------------------------
-- Nützliche Punkte merken (nur bei dir, nichts wird gesendet): wo du repariert, Post geholt,
-- beim Lehrer gelernt hast ... Der Warte-Tipp schlägt sie vor.
---------------------------------------------------------------------------
function Places:Learn(kind)
    if not IS_POI[kind] or not SM:Active() then return end
    if IsInInstance then
        local inside, t = IsInInstance()
        if inside and t ~= "none" then return end
    end
    local mapID, x, y = self:PlayerPos()
    if not mapID then return end
    x, y = Round(x), Round(y)
    local npc = CleanName(UnitName and UnitName("npc") or "")
    local e = self:Merge("pois", mapID, x, y, kind, npc, Me())
    e.mine = true
    if SM.Feedback and SM.Feedback.enabled then SM.Feedback:NotePoint(kind, mapID, x, y) end
end

-- Feste Punkte aus Modules\WaitData.lua für eine Karte: { poi, mapID, x, y, builtin = true }.
-- Die Koordinaten richten sich nach dem echten Spiel (Forever oder Classic), nicht nach dem
-- Dev-Schalter - die Karte selbst ist ja die des Spiels.
function Places:BuiltinPOIs(mapID)
    local out = {}
    local fac = type(UnitFactionGroup) == "function" and UnitFactionGroup("player")
    fac = (fac == "Alliance" and "A") or (fac == "Horde" and "H") or nil
    local cls = type(UnitClass) == "function" and select(2, UnitClass("player")) or nil
    for ti, town in ipairs(SM.WaitData or {}) do
        if town.m == mapID and (not town.f or town.f == fac) then
            for pi, p in ipairs(town) do
                if (not p.f or p.f == fac) and (p[1] ~= "class" or p.k == cls) then
                    local x, y = p[2] / 100, p[3] / 100
                    if not SM.FOREVER and p.cx then x, y = p.cx / 100, p.cy / 100 end
                    -- von 3 Spielern bestätigt (Modules\Feedback.lua): deren Stelle gilt
                    local fx, fy
                    if SM.Feedback and SM.db then fx, fy = SM.Feedback:PointFix(ti .. ":" .. pi) end
                    if fx then x, y = fx, fy end
                    out[#out + 1] = { poi = (p[1] == "class") and "classtrainer" or p[1], mapID = mapID,
                                      x = x, y = y, builtin = true }
                end
            end
        end
    end
    return out
end

-- Nützliche Punkte in deiner Zone, die nächsten zuerst: { poi, npc, mapID, x, y, dist }.
-- Selbst gemerkte (nur bei dir) und die festen Punkte des Addons.
function Places:NearbyPOIs(maxYards)
    local mapID = self:PlayerPos()
    local out = {}
    if not mapID then return out end
    local function add(e)
        e.dist = SM.Eta and SM.Eta.enabled and SM.Eta:Distance({ mapID = e.mapID, x = e.x, y = e.y }) or nil
        if not maxYards or (e.dist and e.dist <= maxYards) then out[#out + 1] = e end
    end
    local learned = {}
    for _, e in ipairs(self:Store().pois) do
        if e.m == mapID and e.by and e.by[Me()] then
            learned[#learned + 1] = e
            add({ poi = e.c, npc = e.n, mapID = e.m, x = e.x, y = e.y })
        end
    end
    for _, p in ipairs(self:BuiltinPOIs(mapID)) do
        local dupe = false
        for _, e in ipairs(learned) do
            if e.c == p.poi and Close(e, p.mapID, p.x, p.y) then dupe = true end
        end
        if not dupe then add(p) end
    end
    table.sort(out, function(a, b) return (a.dist or math.huge) < (b.dist or math.huge) end)
    return out
end

local function IsInnkeeper()
    if C_GossipInfo and C_GossipInfo.GetOptions then
        for _, o in ipairs(C_GossipInfo.GetOptions() or {}) do
            if o.type == "binder" or o.icon == 132052 then return true end
        end
    elseif GetGossipOptions then
        local t = { GetGossipOptions() }
        for i = 2, #t, 2 do if t[i] == "binder" then return true end end
    end
    return false
end

---------------------------------------------------------------------------
-- Sammelplätze auf der Weltkarte (nur WoW Forever): kleine Symbole in Pin-Optik,
-- Maus darüber = Name und Beschreibung, Klick = Auswahl (Weg zeigen ...). So sieht man auf der Karte (M),
-- dass es z. B. in Menethil oder Beutebucht einen Sammelplatz gibt.
---------------------------------------------------------------------------
local HBDPins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
local MEET_SIZE = 12
Places.meetPins = {}

local function MeetEnter(f)
    local it = f.item
    if not it then return end
    GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
    GameTooltip:AddLine(it.name or "", 1, 0.82, 0)
    GameTooltip:AddLine(L.PLACE_CAT_meet, 0.8, 0.8, 0.8)
    if it.desc and it.desc ~= "" then GameTooltip:AddLine(it.desc, 1, 1, 1, true) end
    GameTooltip:AddLine(L.MEET_PIN_HINT, 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

local function MeetGo(it)
    if not (it and SM.Eta) then return end
    local _, msg = SM.Eta:GoTo({ mapID = it.mapID, x = it.x, y = it.y, title = it.name, desc = it.desc,
                                placeKey = it.ref and it.ref.key or nil })
    SM:Print(msg)
end

-- Klick = Auswahl, wie überall (test8b): Weg zeigen oben, dazu die Geschichte der Zone
local function MeetClick(f)
    local it = f.item
    if not it then return end
    SM.UI.Menu(f, it.name, {
        { text = L.PLACE_GO, disabled = not (SM.Eta and SM.Eta.enabled), fn = function() MeetGo(it) end },
        { text = L.PLACE_LORE, fn = function() SM.LoreReader:Open(it.mapID, it.wiki) end },
    })
end

function Places:MeetPin(i)
    local f = self.meetPins[i]
    if f then return f end
    local TEX = "Interface\\AddOns\\SocializeMeForever\\Media\\"
    f = CreateFrame("Button", nil, UIParent)
    f:SetSize(MEET_SIZE, MEET_SIZE)
    f:EnableMouse(true)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.disc = f:CreateTexture(nil, "ARTWORK")
    f.disc:SetAllPoints(f)
    f.disc:SetTexture(TEX .. "pin_meet")
    f.ring = f:CreateTexture(nil, "OVERLAY")
    f.ring:SetAllPoints(f)
    f.ring:SetTexture(TEX .. "pin_frame")
    f:SetScript("OnEnter", MeetEnter)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnClick", MeetClick)
    self.meetPins[i] = f
    return f
end

function Places:DrawMeetPins()
    if not HBDPins then return 0 end
    pcall(HBDPins.RemoveAllWorldMapIcons, HBDPins, Places.meetPins)
    for _, f in ipairs(self.meetPins) do f.item = nil; f:Hide() end
    if not self.enabled then return 0 end
    local flag = _G.HBD_PINS_WORLDMAP_SHOW_PARENT or 1
    local n = 0
    for _, it in ipairs(self:AddonPlaces(nil, "meet")) do
        n = n + 1
        local f = self:MeetPin(n)
        f.item = it
        f:Show()
        -- eigener Schlüssel (die Tabelle meetPins), damit die Beacon-Pins unberührt bleiben
        pcall(HBDPins.AddWorldMapIconMap, HBDPins, Places.meetPins, f, it.mapID, it.x, it.y, flag)
    end
    return n
end

---------------------------------------------------------------------------
-- Modul
---------------------------------------------------------------------------
function Places:OnEnable()
    SM:RegisterEvent(self, "MERCHANT_SHOW", function()
        if CanMerchantRepair and CanMerchantRepair() then self:Learn("repair") end
    end)
    SM:RegisterEvent(self, "TAXIMAP_OPENED", function() self:Learn("flight") end)
    SM:RegisterEvent(self, "MAIL_SHOW", function() self:Learn("mail") end)
    SM:RegisterEvent(self, "BANKFRAME_OPENED", function() self:Learn("bank") end)
    SM:RegisterEvent(self, "AUCTION_HOUSE_SHOW", function() self:Learn("auction") end)
    SM:RegisterEvent(self, "PET_STABLE_SHOW", function() self:Learn("stable") end)
    SM:RegisterEvent(self, "TRAINER_SHOW", function()
        local prof = IsTradeskillTrainer and IsTradeskillTrainer()
        self:Learn(prof and "proftrainer" or "classtrainer")
    end)
    SM:RegisterEvent(self, "GOSSIP_SHOW", function() if IsInnkeeper() then self:Learn("inn") end end)
    self:DrawMeetPins()
    -- Geteilte Orte über das Addon-Netz gibt es nicht mehr (frühere Testversionen): weg damit
    self:Store().spots = {}
    -- nützliche Punkte gibt es nur noch von dir selbst (frühere Testversionen teilten sie)
    local pois = self:Store().pois
    for i = #pois, 1, -1 do
        if not (pois[i].by and pois[i].by[Me()]) then table.remove(pois, i) end
    end
end

function Places:OnDisable()
    self:DrawMeetPins() -- räumt nur ab (enabled ist schon aus)
end

-- Forever/Classic umgeschaltet (Dev) oder ein Ort neu vermessen: neu zeichnen
SM:RegisterCallback("FOREVER_CHANGED", function() if Places.enabled then Places:DrawMeetPins() end end)

SM:RegisterCommand("orte", function()
    if SM.Window then SM.Window:OpenPlaces() end
end, "places")
