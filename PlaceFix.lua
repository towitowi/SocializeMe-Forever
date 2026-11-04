local ADDON, SM = ...

-- Gemeinsames Nachmessen der mitgelieferten Orte (nur in WoW Forever).
--
-- Die Koordinaten der Startliste sind aus NPC-Standorten abgeleitet und gerundet. Spieler, die
-- wirklich dort sind, verbessern sie nebenbei:
--   * im Hintergrund: Stehst du im Teilgebiet eines Ortes (z. B. "Scharlachrotes Kloster" laut
--     Spiel), merkt sich das Addon alle 10 Sekunden deine Position. Nach einer Minute dort zählt
--     der Mittelwert als deine Messung. Das trifft grob die Mitte des Gebiets.
--   * per Klick: Läufst du mit "Weg zeigen" zu einem Ort, fragt eine kleine Karte kurz vor dem
--     Ziel "Stimmt die Stelle?". "Hier ist es" ist genauer und zählt vor den Hintergrund-Messungen.
-- Eine Messung geht als kurze Addon-Nachricht an die anderen (V;1;Ort;Karte;x;y;s|c). Eine neue
-- Koordinate gilt erst, wenn 3 verschiedene Spieler fast dieselbe Stelle gemessen haben - so kann
-- ein einzelner Troll keinen Ort verschieben. Messungen weit weg von der bisherigen Schätzung
-- werden verworfen. Gesendet wird nur die Position am Ort (steht im Info-Tab unter Datenschutz).
local Fix = SM:NewModule("placefix")
SM.PlaceFix = Fix

local PREFIX = "SMForever"
local SAMPLE_EVERY = 10      -- Sek. zwischen zwei Hintergrund-Proben
local SAMPLES_NEEDED = 6     -- so viele Proben (= 1 Minute im Gebiet) ergeben eine Messung
local MAX_SAMPLES = 30
local NEED = 3               -- so viele verschiedene Spieler bestätigen eine Koordinate
local CLUSTER = 0.02         -- 2 % der Karte: so nah müssen die Messungen beieinanderliegen
local PLAUSIBLE = 0.15       -- weiter als 15 % der Karte von der Schätzung weg = verworfen
local RESEND_GAP = 15        -- Sek. zwischen zwei eigenen Messungen beim erneuten Senden
local RESEND_DELAY = 90      -- Sek. nach dem Login
local KEEP = 90 * 86400      -- Messungen anderer so lange merken

Fix.asked = {}               -- Ort -> true: in dieser Sitzung schon gefragt
Fix.sent = {}                -- Ort -> true: in dieser Sitzung schon gesendet

local function Me() return UnitName("player") end
local function ShortName(n) return (n and n:match("^([^-]+)")) or n end

-- Sprache des Spiels (nicht die des Addons): Teilgebiet-Namen kommen vom Client
local function ClientLang()
    local loc = type(GetLocale) == "function" and GetLocale() or ""
    if loc == "deDE" then return "de" end
    if loc == "enUS" or loc == "enGB" then return "en" end
end

function Fix:Store()
    local s = SM.db.placeFix
    if type(s) ~= "table" then s = {}; SM.db.placeFix = s end
    if type(s.reports) ~= "table" then s.reports = {} end
    if type(s.own) ~= "table" then s.own = {} end
    return s
end

local BY_KEY
local function Place(key)
    if not BY_KEY then
        BY_KEY = {}
        for _, p in ipairs(SM.PlacesData or {}) do BY_KEY[p.key] = p end
    end
    return BY_KEY[key]
end

local function Median(list)
    table.sort(list)
    local n = #list
    if n % 2 == 1 then return list[(n + 1) / 2] end
    return (list[n / 2] + list[n / 2 + 1]) / 2
end

-- Bestätigte Koordinate eines Ortes aus den Messungen: x, y, Anzahl (oder nil)
local function Confirm(reports)
    local function cluster(onlyClicks)
        local xs, ys, pts = {}, {}, {}
        for _, r in pairs(reports) do
            if not onlyClicks or r.s == "c" then
                xs[#xs + 1], ys[#ys + 1] = r.x, r.y
                pts[#pts + 1] = r
            end
        end
        if #pts < NEED then return nil end
        local mx, my = Median(xs), Median(ys)
        local sx, sy, n = 0, 0, 0
        for _, r in ipairs(pts) do
            if math.abs(r.x - mx) <= CLUSTER and math.abs(r.y - my) <= CLUSTER then
                sx, sy, n = sx + r.x, sy + r.y, n + 1
            end
        end
        if n < NEED then return nil end
        return sx / n, sy / n, n
    end
    local x, y, n = cluster(true)
    if x then return x, y, n end
    return cluster(false)
end

-- Bestätigte Koordinate für einen Ort der Startliste (oder nil)
function Fix:Get(key)
    if not SM.db then return nil end
    local reports = self:Store().reports[key]
    if not reports then return nil end
    local x, y = Confirm(reports)
    return x, y
end

-- Wie viele Orte sind bestätigt? Gibt Anzahl und Liste { key, x, y, n } zurück.
function Fix:Confirmed()
    local list = {}
    for key, reports in pairs(self:Store().reports) do
        local p = Place(key)
        local x, y, n = Confirm(reports)
        if p and x then list[#list + 1] = { key = key, m = p.m, x = x, y = y, n = n } end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return #list, list
end

---------------------------------------------------------------------------
-- Messen und senden
---------------------------------------------------------------------------
local function Send(key, m, x, y, src)
    if not SM.Beacon or not SM:HelpImprove() then return false end
    return SM.Beacon:Broadcast(("V;1;%s;%d;%d;%d;%s"):format(key, m,
        math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5), src))
end

-- Eigene Messung speichern (zählt auch bei mir mit) und einmal je Sitzung senden
function Fix:Record(key, x, y, src)
    local p = Place(key)
    if not p then return false end
    local s = self:Store()
    s.own[key] = { x = x, y = y, s = src, t = time() }
    s.reports[key] = s.reports[key] or {}
    s.reports[key][Me()] = { x = x, y = y, s = src, t = time() }
    if not self.sent[key] or src == "c" then
        self.sent[key] = true
        Send(key, p.m, x, y, src)
    end
    SM:Fire("PLACES_CHANGED")
    return true
end

local function PlayerPos()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y
    if pos and pos.GetXY then x, y = pos:GetXY() end
    if not x or not y or (x == 0 and y == 0) then return nil end
    return mapID, x, y
end

local function InInstance()
    if type(IsInInstance) ~= "function" then return false end
    local inside, kind = IsInInstance()
    return inside and kind ~= "none"
end

-- Hintergrund: im Teilgebiet eines Ortes Proben sammeln
function Fix:Sample()
    if not SM.FOREVER or not SM:Active() or InInstance() or not SM:HelpImprove() then return end
    local lang = ClientLang()
    if not lang then return end
    local sub = type(GetSubZoneText) == "function" and GetSubZoneText() or ""
    if sub == "" then return end
    local mapID, x, y = PlayerPos()
    if not mapID then return end
    local s = self:Store()
    for _, p in ipairs(SM.PlacesData or {}) do
        local name = p.sub and p.sub[lang]
        if name and name == sub and p.m == mapID then
            local acc = self.samples and self.samples[p.key] or { sx = 0, sy = 0, n = 0 }
            self.samples = self.samples or {}
            if acc.n < MAX_SAMPLES then
                acc.sx, acc.sy, acc.n = acc.sx + x, acc.sy + y, acc.n + 1
                self.samples[p.key] = acc
            end
            local own = s.own[p.key]
            -- Hintergrund-Messung, solange keine eigene Klick-Messung da ist
            if acc.n >= SAMPLES_NEEDED and not (own and own.s == "c") and not self.sent[p.key] then
                self:Record(p.key, acc.sx / acc.n, acc.sy / acc.n, "s")
            end
        end
    end
end

-- Früher kam kurz vor einem Ort die Frage "Stimmt die Stelle?". Seit test8b (weniger Fenster)
-- wird nur noch still im Hintergrund gemessen (Fix:Sample) - nichts geht mehr von selbst auf.
function Fix:CheckTarget()
    return nil
end

function Fix:Tick()
    self.tickN = (self.tickN or 0) + 1
    if self.tickN % (SAMPLE_EVERY / 5) == 0 then self:Sample() end
end

---------------------------------------------------------------------------
-- Empfangen
---------------------------------------------------------------------------
Fix.recvCount = {}
local function Flood(short)
    local now = GetTime()
    local r = Fix.recvCount[short]
    if not r or (now - r.t) > 60 then r = { t = now, n = 0 }; Fix.recvCount[short] = r end
    r.n = r.n + 1
    return r.n > 20
end

function Fix:HandleMessage(text, sender)
    local key, m, xi, yi, src = text:match("^V;1;([%w_]+);(%d+);(%d+);(%d+);([sc])$")
    if not key then return end
    local p = Place(key)
    m, xi, yi = tonumber(m), tonumber(xi), tonumber(yi)
    if not p or m ~= p.m or xi > 10000 or yi > 10000 then return end
    local short = ShortName(sender)
    if short == Me() or SM.Guard:IsBlocked(short) or SM.Beacon:IsIgnored(short) or Flood(short) then return end
    local x, y = xi / 10000, yi / 10000
    -- weit weg von der bisherigen Schätzung: verwerfen (schützt vor absichtlich falschen Werten)
    if p.x and p.y and (math.abs(x - p.x) > PLAUSIBLE or math.abs(y - p.y) > PLAUSIBLE) then return end
    local s = self:Store()
    s.reports[key] = s.reports[key] or {}
    local before = self:Get(key)
    s.reports[key][short] = { x = x, y = y, s = src, t = time() }
    if (self:Get(key) ~= nil) ~= (before ~= nil) or self:Get(key) then SM:Fire("PLACES_CHANGED") end
end

-- Alte Messungen anderer aufräumen
function Fix:Prune()
    local now = time()
    for key, reports in pairs(self:Store().reports) do
        for who, r in pairs(reports) do
            if who ~= Me() and (now - (r.t or 0)) > KEEP then reports[who] = nil end
        end
        if next(reports) == nil or not Place(key) then self:Store().reports[key] = nil end
    end
end

-- Eigene Messungen nach dem Login noch einmal senden (für alle, die neu dazugekommen sind)
function Fix:Resend()
    if not SM.FOREVER then return end
    local keys = {}
    for key in pairs(self:Store().own) do if Place(key) then keys[#keys + 1] = key end end
    table.sort(keys)
    for i, key in ipairs(keys) do
        C_Timer.After((i - 1) * RESEND_GAP, function()
            local o = Fix:Store().own[key]
            if Fix.enabled and o and not Fix.sent[key] then
                Fix.sent[key] = true
                Send(key, Place(key).m, o.x, o.y, o.s == "c" and "c" or "s")
            end
        end)
    end
end

function Fix:OnEnable()
    SM:RegisterEvent(self, "CHAT_MSG_ADDON", function(_, prefix, text, dist, sender)
        if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" then return end
        if text:sub(1, 2) == "V;" then self:HandleMessage(text, sender) end
    end)
    self:Prune()
    self.ticker = C_Timer.NewTicker(5, function() self:Tick() end)
    C_Timer.After(RESEND_DELAY, function() if Fix.enabled then Fix:Resend() end end)
end

function Fix:OnDisable()
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
end
