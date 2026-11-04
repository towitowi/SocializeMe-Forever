local ADDON, SM = ...
local L = SM.L

-- Feedback für den Entwickler, ganz nebenbei (steht im Info-Tab unter Datenschutz):
--   * Fehler des Addons (Datei, Zeile, Meldung - keine Namen, keine Chat-Texte)
--   * Zonen, zu denen das Addon keine Lore kennt (neue Gebiete in WoW Forever)
--   * Lagerfeuer-Buffs: Zauber-Nummer und Name, wenn du an einem Feuer bist
--   * Musikstücke, die dein Spiel nicht abspielt
--   * deine Addon-Version
--   * wo du einen Händler, Briefkasten, Lehrer ... benutzt oder geangelt hast (nur die Position)
-- Jede Sache geht höchstens einmal je Sitzung als kurze Addon-Nachricht (R;1 / N;1) an die
-- anderen Addon-Nutzer. Normale Spieler werten R;1 nicht aus - nur der private Dev-Zusatz des
-- Entwicklers sammelt sie. N;1 verbessert die Punkte des Warte-Tipps für alle, sobald 3
-- verschiedene Spieler fast dieselbe Stelle gemeldet haben (wie beim Nachmessen der Orte).
-- Addon-Nachrichten erreichen nur den eigenen Realm. Deshalb gibt es im Info-Tab zusätzlich
-- "Feedback kopieren": dieselben Angaben als Text für CurseForge oder Discord.
local FB = SM:NewModule("feedback")
SM.Feedback = FB

local PREFIX = "SMForever"
local SEND_GAP = 5           -- Sek. zwischen zwei Feedback-Nachrichten
local MAX_ITEMS = 30         -- je Art höchstens so viele Einträge merken
local NEED = 3               -- so viele Spieler bestätigen einen Warte-Tipp-Punkt
local NEAR = 0.04            -- so nah (Anteil der Karte) gehört eine Meldung zu einem festen Punkt
local CLUSTER = 0.015
local POINT_KINDS = { repair = "repair", inn = "inn", flight = "flight", mail = "mail", auction = "auction", classtrainer = "class" }

FB.queue = {}
FB.sentKeys = {}

local function Clean(s, max)
    s = tostring(s or ""):gsub("[;|%c]", " ")
    return s:sub(1, max or 120)
end

local function Version()
    local fn = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = fn and fn(ADDON, "Version")
    return Clean(v or "?", 20)
end
FB.Version = Version

function FB:Store()
    local s = SM.db.feedback
    if type(s) ~= "table" then s = {}; SM.db.feedback = s end
    for _, k in ipairs({ "errors", "zones", "buffs", "music", "points" }) do
        if type(s[k]) ~= "table" then s[k] = {} end
    end
    return s
end

local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- Nachricht in die Warteschlange (jede Sache nur einmal je Sitzung)
function FB:Queue(key, msg)
    if self.sentKeys[key] or not SM:HelpImprove() then return end
    self.sentKeys[key] = true
    self.queue[#self.queue + 1] = msg
    if not self.sender then
        self.sender = C_Timer.NewTicker(SEND_GAP, function()
            local m = table.remove(FB.queue, 1)
            if m and SM:Active() and SM:HelpImprove() and SM.Beacon then SM.Beacon:Broadcast(m) end
            if #FB.queue == 0 and FB.sender then FB.sender:Cancel(); FB.sender = nil end
        end)
    end
end

---------------------------------------------------------------------------
-- Sammeln
---------------------------------------------------------------------------
-- Fehler (aus SM.SafeCall)
function FB:NoteError(err)
    if not SM.db then return end
    local msg = Clean(tostring(err):gsub("^.-AddOns[\\/]", ""), 120)
    local e = self:Store().errors
    local entry = e[msg]
    if not entry and Count(e) >= MAX_ITEMS then return end
    entry = entry or { n = 0 }
    entry.n, entry.t, entry.v = entry.n + 1, time(), Version()
    e[msg] = entry
    self:Queue("e" .. msg, "R;1;e;" .. msg)
end

-- Zone ohne Lore (nur WoW Forever: dort gibt es neue Gebiete)
function FB:CheckZone()
    if not SM.FOREVER or not (C_Map and C_Map.GetBestMapForUnit) then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or not SM.LoreData then return end
    if SM.LoreData.en and SM.LoreData.en[mapID] then return end
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    if info and info.mapType and Enum and Enum.UIMapType and info.mapType ~= Enum.UIMapType.Zone then return end
    local name = Clean(info and info.name or "?", 40)
    local z = self:Store().zones
    if not z[mapID] and Count(z) < MAX_ITEMS then z[mapID] = name end
    self:Queue("z" .. mapID, ("R;1;z;%d;%s"):format(mapID, name))
end

-- Lagerfeuer-Buffs: alle Buffs, deren Name nach Lagerfeuer klingt
local FIRE_WORDS = { "campfire", "lagerfeuer", "营火", "篝火" }
function FB:CheckBuffs()
    if not UnitBuff then return end
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, sid = UnitBuff("player", i)
        if not name then break end
        local low = name:lower()
        for _, w in ipairs(FIRE_WORDS) do
            if sid and low:find(w, 1, true) then
                local b = self:Store().buffs
                if not b[sid] and Count(b) < MAX_ITEMS then b[sid] = Clean(name, 40) end
                self:Queue("b" .. sid, ("R;1;b;%d;%s"):format(sid, Clean(name, 40)))
            end
        end
    end
end

-- Ein Musikstück spielt nicht
function FB:NoteMusic(fileID)
    local m = self:Store().music
    if not m[fileID] and Count(m) < MAX_ITEMS then m[fileID] = time() end
    self:Queue("m" .. tostring(fileID), ("R;1;m;%s;%s"):format(tostring(fileID), SM.FOREVER and "f" or "c"))
end

---------------------------------------------------------------------------
-- Warte-Tipp-Punkte und Angelstellen (N;1;mapID;Art;x;y;f|c[;Klasse])
---------------------------------------------------------------------------
local function Client() return SM.FOREVER and "f" or "c" end

-- Ich habe hier einen Händler, Briefkasten, Lehrer ... benutzt (aus Places:Learn)
function FB:NotePoint(kind, mapID, x, y)
    local k = POINT_KINDS[kind]
    if not k or not mapID then return end
    local cls = (k == "class" and type(UnitClass) == "function") and select(2, UnitClass("player")) or ""
    local xi, yi = math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5)
    local cell = ("%d:%s:%d:%d"):format(mapID, k, math.floor(xi / 200), math.floor(yi / 200))
    self:Report(UnitName("player"), mapID, k, x, y, Client(), cls)
    self:Queue("n" .. cell, ("N;1;%d;%s;%d;%d;%s;%s"):format(mapID, k, xi, yi, Client(), cls))
end

-- Ich angle hier (aus Chill:OnFishing)
function FB:NoteFishing()
    if not (C_Map and C_Map.GetBestMapForUnit) then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y
    if pos and pos.GetXY then x, y = pos:GetXY() end
    if not x or not y or (x == 0 and y == 0) then return end
    local xi, yi = math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5)
    self:Queue(("f%d:%d:%d"):format(mapID, math.floor(xi / 200), math.floor(yi / 200)),
        ("N;1;%d;fish;%d;%d;%s;"):format(mapID, xi, yi, Client()))
end

-- Fester Punkt aus Modules\WaitData.lua, zu dem eine Meldung gehört: Schlüssel oder nil
local function MatchPoint(mapID, kind, x, y, cls)
    local best, bestD
    for ti, town in ipairs(SM.WaitData or {}) do
        if town.m == mapID then
            for pi, p in ipairs(town) do
                if p[1] == kind and (kind ~= "class" or p.k == cls) then
                    local px, py = p[2] / 100, p[3] / 100
                    if not SM.FOREVER and p.cx then px, py = p.cx / 100, p.cy / 100 end
                    local d = math.max(math.abs(px - x), math.abs(py - y))
                    if d <= NEAR and (not bestD or d < bestD) then best, bestD = ti .. ":" .. pi, d end
                end
            end
        end
    end
    return best
end

function FB:Report(who, mapID, kind, x, y, client, cls)
    if client ~= Client() then return end   -- Forever- und Classic-Karten nicht mischen
    local key = MatchPoint(mapID, kind, x, y, cls)
    if not key then return end
    local pts = self:Store().points
    pts[key] = pts[key] or {}
    pts[key][who] = { x = x, y = y, t = time() }
end

-- Bestätigte Position eines festen Punktes (3 Spieler fast an derselben Stelle) oder nil
function FB:PointFix(key)
    local reports = SM.db and self:Store().points[key]
    if not reports then return nil end
    local list = {}
    for _, r in pairs(reports) do list[#list + 1] = r end
    if #list < NEED then return nil end
    for _, a in ipairs(list) do
        local sx, sy, n = 0, 0, 0
        for _, b in ipairs(list) do
            if math.abs(a.x - b.x) <= CLUSTER and math.abs(a.y - b.y) <= CLUSTER then sx, sy, n = sx + b.x, sy + b.y, n + 1 end
        end
        if n >= NEED then return sx / n, sy / n end
    end
end

---------------------------------------------------------------------------
-- Empfangen (nur N;1 - R;1 wertet nur der Dev-Zusatz aus)
---------------------------------------------------------------------------
function FB:HandleMessage(text, sender)
    local mapID, kind, xi, yi, client, cls = text:match("^N;1;(%d+);(%a+);(%d+);(%d+);([fc]);(%u*)$")
    if not mapID then return end
    mapID, xi, yi = tonumber(mapID), tonumber(xi), tonumber(yi)
    if xi > 10000 or yi > 10000 or kind == "fish" then return end
    local short = (sender:match("^([^-]+)")) or sender
    if short == UnitName("player") or SM.Guard:IsBlocked(short) or SM.Beacon:IsIgnored(short) then return end
    self:Report(short, mapID, kind, xi / 10000, yi / 10000, client, cls)
end

---------------------------------------------------------------------------
-- "Feedback kopieren" (Info-Tab): alles Gesammelte als eine Zeile Text
---------------------------------------------------------------------------
function FB:Text()
    local s = self:Store()
    local parts = { ("SocializeMe %s %s %s"):format(Version(), SM.FOREVER and "Forever" or "Classic", SM.locale or "?") }
    local e = {}
    for msg, entry in pairs(s.errors) do e[#e + 1] = ("%dx %s"):format(entry.n, msg) end
    table.sort(e)
    parts[#parts + 1] = "errors: " .. (#e > 0 and table.concat(e, " / ") or "none")
    local z = {}
    for id, name in pairs(s.zones) do z[#z + 1] = id .. " " .. name end
    table.sort(z)
    if #z > 0 then parts[#parts + 1] = "zones without lore: " .. table.concat(z, ", ") end
    local b = {}
    for id, name in pairs(s.buffs) do b[#b + 1] = id .. " " .. name end
    table.sort(b)
    if #b > 0 then parts[#parts + 1] = "campfire buffs: " .. table.concat(b, ", ") end
    local m = {}
    for id in pairs(s.music) do m[#m + 1] = tostring(id) end
    table.sort(m)
    if #m > 0 then parts[#parts + 1] = "music not playing: " .. table.concat(m, ", ") end
    return table.concat(parts, " | ")
end

function FB:OnEnable()
    SM:RegisterEvent(self, "CHAT_MSG_ADDON", function(_, prefix, text, dist, sender)
        if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" then return end
        if text:sub(1, 2) == "N;" then self:HandleMessage(text, sender) end
    end)
    SM:RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", function() FB:CheckZone() end)
    SM:RegisterEvent(self, "UNIT_AURA", function(_, unit)
        if unit ~= "player" then return end
        local now = GetTime()
        if FB.lastBuffScan and now - FB.lastBuffScan < 2 then return end
        FB.lastBuffScan = now
        self:CheckBuffs()
    end)
    C_Timer.After(60, function()
        if FB.enabled then FB:Queue("v", "R;1;v;" .. Version() .. ";" .. (SM.FOREVER and "f" or "c")); FB:CheckZone() end
    end)
end
