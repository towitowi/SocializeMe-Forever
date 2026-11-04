local ADDON, SM = ...
local L = SM.L

-- Troll-Schutz: Melden, Pause, Ausschluss.
--
-- Grundsätze (so auch in den Regeln beschrieben):
--   * Melden geht nur, wenn dich jemand angeschrieben hat (geflüstert oder im Gruppenchat).
--     Ein Beacon-Text kann auch gemeldet werden - das blendet aber nur das Beacon aus.
--   * 3 gültige Meldungen von 3 verschiedenen Spielern innerhalb von 30 Tagen = 14 Tage Pause.
--     Kommt es danach noch einmal so weit: für immer raus.
--   * Gültig ist eine Meldung nur, wenn
--       - dein Addon den Meldenden schon seit mindestens 14 Tagen kennt,
--       - nicht alle drei Meldenden aus derselben Gilde kommen,
--       - der Meldende nicht mehr als 3 Meldungen am Tag abgibt,
--       - der Meldende nicht mehr als 5 Leute in 7 Tagen meldet (sonst zählen seine Meldungen 30 Tage nicht).
--   * Die Sperre steckt in den Addons ALLER anderen: Sie ignorieren den Gesperrten. Wer gemeldet hat,
--     schickt seine Meldungen regelmäßig erneut, damit auch später Dazugekommene sie kennen.
--   * Startphase bis einschließlich 18.11.2026 (zum Start von WoW Forever kennt noch niemand jemanden
--     14 Tage): Meldende zählen schon nach 3 Tagen. Dafür braucht es 4 Meldungen aus mindestens
--     2 Gilden (Gildenlose zählen je für sich), und eine Sperre dauert höchstens 3 Tage. Sperren aus
--     der Startphase zählen nicht als erster Strike für "für immer".
--
-- Nachrichten (Präfix SMForever):
--   P;1                                    "ich bin da" (damit das Addon weiß, seit wann es jemanden kennt)
--   T;1;name;grund;zeit;gilde;guid         Meldung (grund: s = Spam, i = beleidigend, h = belästigend/bedrohlich)
--   T;1;name;b;zeit;gilde;beaconID         unpassender Beacon-Text
--   K;1;bis                                (geflüstert) "mein Addon ignoriert dich" - nur zur Info, bis = 0 heißt für immer
local Guard = {}
SM.Guard = Guard

local PREFIX = "SMForever"
local DAY = 86400
local SEEN_MIN = 14 * DAY        -- so lange muss man jemanden kennen, damit seine Meldung zählt
local WINDOW = 30 * DAY          -- 3 Meldungen innerhalb dieser Zeit
local PAUSE = 14 * DAY           -- erste Sperre
local NEEDED = 3                 -- Meldungen von so vielen verschiedenen Spielern
local PER_DAY = 3                -- höchstens so viele Meldungen pro Tag zählen
local HEAVY_COUNT, HEAVY_SPAN, HEAVY_MUTE = 5, 7 * DAY, 30 * DAY
local KEEP_REPORTS = 180 * DAY   -- Meldungen so lange merken
local RESEND_OWN = 120 * DAY     -- eigene Meldungen so lange weitergeben
local WROTE_KEEP = 7 * DAY       -- so lange kann man jemanden nach seiner Nachricht melden
local MAX_MSGS = 15              -- so viele Nachrichten je Spieler bleiben als Beweis (nur bei dir, 7 Tage)
local MAX_SEEN = 3000
local PRESENCE_EVERY = 1200      -- Sek.
local RESEND_EVERY = 1800        -- Sek.
local NOTICE_EVERY = 3600        -- Sek.: "du wirst ignoriert" höchstens einmal pro Stunde und Spieler
Guard.MIN_BEACON_LEVEL = 10      -- eigene Beacons erst ab dieser Stufe

-- Startphase (siehe oben). Ende: 19.11.2026, 0 Uhr Ortszeit.
local START_END = time({ year = 2026, month = 11, day = 19, hour = 0, min = 0, sec = 0 })
local START_SEEN = 3 * DAY
local START_NEEDED = 4
local START_PAUSE = 3 * DAY

function Guard:InStartPhase(t)
    return (t or time()) < START_END
end
Guard.START_END = START_END

Guard.REASONS = { "s", "i", "h" }

local function ShortName(name)
    return (name and name:match("^([^-]+)")) or name
end

local function Realm()
    local r = type(GetRealmName) == "function" and GetRealmName() or nil
    return (r and r ~= "") and r or "?"
end

local function Me()
    return UnitName("player")
end

local function MyGuild()
    if SM.Probe and SM.Probe.on and SM.Probe.guild then return SM.Probe.guild end
    if type(GetGuildInfo) ~= "function" then return "" end
    local g = GetGuildInfo("player")
    return (type(g) == "string") and g:gsub("[;|]", "") or ""
end
Guard.MyGuild = MyGuild

local function Clean(s, max)
    s = tostring(s or ""):gsub("[;|%c]", "")
    return s:sub(1, max or 40)
end

---------------------------------------------------------------------------
-- Speicher (je Realm)
---------------------------------------------------------------------------
function Guard:Store()
    local all = SM.db.guard
    local realm = Realm()
    local s = all[realm]
    if type(s) ~= "table" then s = {}; all[realm] = s end
    for _, k in ipairs({ "seen", "wrote", "mine", "reports", "pauses", "spauses", "perm", "guids", "beacons", "notices" }) do
        if type(s[k]) ~= "table" then s[k] = {} end
    end
    return s
end

function Guard:Init()
    local s = self:Store()
    local me = Me()
    if me and not s.seen[me] then s.seen[me] = { f = time(), l = time() } end
    self:Prune()
    self.verdicts = {}
    self:Evaluate(me)
end

-- Altes aufräumen
function Guard:Prune()
    local s, now = self:Store(), time()
    for name, w in pairs(s.wrote) do if (now - (w.t or 0)) > WROTE_KEEP then s.wrote[name] = nil end end
    for target, byRep in pairs(s.reports) do
        for rep, r in pairs(byRep) do
            if (now - (r.t or 0)) > KEEP_REPORTS then byRep[rep] = nil end
        end
        if next(byRep) == nil then s.reports[target] = nil end
    end
    for target, r in pairs(s.mine) do if (now - (r.t or 0)) > RESEND_OWN then s.mine[target] = nil end end
    -- gesehene Spieler: höchstens MAX_SEEN, die am längsten nicht gesehenen fliegen
    local list = {}
    for name, e in pairs(s.seen) do list[#list + 1] = { name = name, l = e.l or 0 } end
    if #list > MAX_SEEN then
        table.sort(list, function(a, b) return a.l < b.l end)
        for i = 1, #list - MAX_SEEN do s.seen[list[i].name] = nil end
    end
end

function Guard:Seen(name)
    if not name then return end
    local s, now = self:Store(), time()
    local e = s.seen[name]
    if e then e.l = now else s.seen[name] = { f = now, l = now } end
end

-- Kennt mein Addon diesen Spieler schon lange genug?
function Guard:KnownLongEnough(name)
    -- Testmodus (nur mit dem privaten Dev-Zusatz): die 14-Tage-Regel gilt nur auf diesem Rechner nicht.
    if SM:IsTestMode() then return true end
    local e = self:Store().seen[name]
    local need = self:InStartPhase() and START_SEEN or SEEN_MIN
    return e and e.f and (time() - e.f) >= need or false
end

---------------------------------------------------------------------------
-- Wer hat mich angeschrieben? (Voraussetzung fürs Melden)
---------------------------------------------------------------------------
function Guard:NoteWrote(sender, guid, lineID, text, channel)
    if type(sender) ~= "string" or sender == "" then return end
    local short = ShortName(sender)
    if short == Me() then return end
    local s = self:Store()
    local w = s.wrote[short]
    local msgs = (w and type(w.msgs) == "table") and w.msgs or {}
    if type(text) == "string" and text ~= "" then
        msgs[#msgs + 1] = { t = time(), c = channel or "", m = text:sub(1, 255) }
        while #msgs > MAX_MSGS do table.remove(msgs, 1) end
    end
    s.wrote[short] = { t = time(), full = sender, guid = guid, line = lineID, msgs = msgs }
    if type(guid) == "string" and guid ~= "" then
        -- Namensänderung: dieselbe Kennung unter neuem Namen ist dieselbe Person
        local old = s.guids[guid]
        if old and old ~= short and self:IsBlocked(old) then s.guids[guid] = old; self.alias = self.alias or {}; self.alias[short] = old end
        if not old then s.guids[guid] = short end
    end
end

function Guard:Wrote(name)
    local w = self:Store().wrote[ShortName(name)]
    if w and (time() - (w.t or 0)) <= WROTE_KEEP then return w end
end

---------------------------------------------------------------------------
-- Bewertung: ist jemand pausiert oder ausgeschlossen?
---------------------------------------------------------------------------
-- Alle Meldungen eines Spielers (als Meldender), sortiert nach Zeit
local function ByReporter(s, reporter)
    local list = {}
    for target, byRep in pairs(s.reports) do
        local r = byRep[reporter]
        if r and r.r ~= "b" then list[#list + 1] = { target = target, t = r.t } end
    end
    table.sort(list, function(a, b) return a.t < b.t end)
    return list
end

-- Meldet jemand auffällig viele Leute, zählen seine Meldungen eine Weile nicht.
function Guard:Weightless(reporter)
    local s = self:Store()
    local list = ByReporter(s, reporter)
    local now = time()
    for i = 1, #list do
        local targets, n = {}, 0
        for j = i, #list do
            if list[j].t - list[i].t > HEAVY_SPAN then break end
            if not targets[list[j].target] then targets[list[j].target] = true; n = n + 1 end
        end
        if n > HEAVY_COUNT and now < list[i].t + HEAVY_SPAN + HEAVY_MUTE then return true end
    end
    return false
end

-- Zählt diese Meldung zu den ersten 3 des Tages dieses Meldenden?
local function WithinDailyLimit(s, reporter, target, t)
    local day = math.floor(t / DAY)
    local list = ByReporter(s, reporter)
    local rank = 0
    for _, e in ipairs(list) do
        if math.floor(e.t / DAY) == day then
            rank = rank + 1
            if e.target == target then return rank <= PER_DAY end
        end
    end
    return true
end

-- Ergebnis: { untilTime = Zeitpunkt oder nil, perm = true/false, strikes = n }
function Guard:Evaluate(target)
    if not target then return end
    local s = self:Store()
    local now = time()
    local result = { strikes = 0, perm = false }

    if s.perm[target] then
        result.perm, result.strikes = true, 2
    else
        local events = {}
        local byRep = s.reports[target] or {}
        for rep, r in pairs(byRep) do
            if r.r ~= "b" and rep ~= target and (rep == Me() or self:KnownLongEnough(rep)) and not self:Weightless(rep)
                and not s.perm[rep] and WithinDailyLimit(s, rep, target, r.t) then
                events[#events + 1] = { t = r.t, rep = rep, grp = (r.g and r.g ~= "") and ("g:" .. r.g) or ("p:" .. rep) }
            end
        end
        table.sort(events, function(a, b) return a.t < b.t end)
        local consumed = 0
        local firstPause = s.pauses[target]
        if firstPause then
            result.strikes = 1
            consumed = firstPause + PAUSE
            result.untilTime = firstPause + PAUSE
        end
        -- Sperre aus der Startphase (höchstens 3 Tage, kein Strike)
        local startPause = s.spauses[target]
        if startPause then
            consumed = math.max(consumed, startPause + START_PAUSE)
            result.untilTime = math.max(result.untilTime or 0, startPause + START_PAUSE)
        end
        for i = 1, #events do
            local ti = events[i].t
            if ti > consumed then
                local reps, groups, nr, ng = {}, {}, 0, 0
                for j = 1, i do
                    local e = events[j]
                    if e.t > consumed and e.t > ti - WINDOW and not reps[e.rep] then
                        reps[e.rep] = true; nr = nr + 1
                        if not groups[e.grp] then groups[e.grp] = true; ng = ng + 1 end
                    end
                end
                local start = self:InStartPhase(ti)
                if nr >= (start and START_NEEDED or NEEDED) and ng >= 2 and start then
                    s.spauses[target] = ti
                    result.untilTime = math.max(result.untilTime or 0, ti + START_PAUSE)
                    consumed = ti + START_PAUSE
                elseif not start and nr >= NEEDED and ng >= 2 then
                    result.strikes = result.strikes + 1
                    if result.strikes == 1 then
                        s.pauses[target] = ti
                        result.untilTime = ti + PAUSE
                        consumed = ti + PAUSE
                    else
                        s.perm[target] = now
                        result.perm = true
                        break
                    end
                end
            end
        end
    end

    local before = self.verdicts and self.verdicts[target]
    self.verdicts = self.verdicts or {}
    self.verdicts[target] = result
    local blockedNow = result.perm or (result.untilTime and result.untilTime > now) or false
    local blockedBefore = before and (before.perm or (before.untilTime and before.untilTime > now)) or false
    if blockedNow ~= blockedBefore or (before and before.perm ~= result.perm) then
        SM:Fire("GUARD_CHANGED", target, blockedNow, result)
    end
    return result
end

function Guard:Verdict(name)
    name = ShortName(name)
    if not name then return nil end
    if self.alias and self.alias[name] then name = self.alias[name] end
    self.verdicts = self.verdicts or {}
    local v = self.verdicts[name]
    if not v then v = self:Evaluate(name) end
    return v, name
end

-- Ist dieser Spieler gerade gesperrt (Pause oder für immer)?
function Guard:IsBlocked(name)
    if not SM.db then return false end
    local v = self:Verdict(name)
    if not v then return false end
    if v.perm then return true end
    return (v.untilTime and v.untilTime > time()) and true or false
end

function Guard:SelfBlocked()
    if not SM.db then return false end
    return self:IsBlocked(Me())
end

-- Text für den Gesperrten selbst
function Guard:BlockText()
    local v = self:Verdict(Me())
    if v and v.perm then return L.BLOCK_PERM end
    if v and v.untilTime then return L.BLOCK_PAUSE:format(date(L.BLOCK_DATE, v.untilTime)) end
    return ""
end

---------------------------------------------------------------------------
-- Melden
---------------------------------------------------------------------------
-- Kann ich diesen Spieler melden? Gibt true oder false + Grund zurück.
function Guard:CanReport(name)
    name = ShortName(name)
    if not name or name == Me() then return false, L.REPORT_SELF end
    if not self:Wrote(name) then return false, L.REPORT_NEED_WORDS end
    local s = self:Store()
    local mine = s.mine[name]
    if mine and mine.r ~= "b" and (time() - mine.t) < WINDOW then return false, L.REPORT_ALREADY end
    if self:MyReportsToday() >= PER_DAY and not SM:IsTestMode() then return false, L.REPORT_LIMIT end
    return true
end

function Guard:MyReportsToday()
    local s, today, n = self:Store(), math.floor(time() / DAY), 0
    for _, r in pairs(s.mine) do
        if r.r ~= "b" and math.floor(r.t / DAY) == today then n = n + 1 end
    end
    return n
end

local function ReportMsg(target, r)
    return ("T;1;%s;%s;%d;%s;%s"):format(target, r.r, r.t, Clean(r.g, 32), Clean(r.x, 40))
end

-- Meldet einen Spieler. reason: "s", "i" oder "h". Gibt true/false + Text zurück.
function Guard:Report(name, reason)
    local short = ShortName(name)
    local ok, why = self:CanReport(short)
    if not ok then return false, why end
    if reason ~= "s" and reason ~= "i" and reason ~= "h" then return false, L.REPORT_PICK end
    local s = self:Store()
    local w = self:Wrote(short)
    local r = { t = time(), r = reason, g = MyGuild(), x = w and w.guid or "" }
    s.mine[short] = r
    s.reports[short] = s.reports[short] or {}
    s.reports[short][Me()] = { t = r.t, r = reason, g = r.g }
    if SM.Beacon then SM.Beacon:Transmit(ReportMsg(short, r)) end
    self:Evaluate(short)
    local text = L.REPORT_DONE:format(short)
    if reason == "h" then
        -- schwerwiegend: sofort ignorieren und Blizzards Meldefenster öffnen
        SM:IgnoreName(short)
        local opened = self:OpenBlizzardReport(w and w.full or short, w)
        text = text .. "\n" .. (opened and L.REPORT_BLIZZ_OPEN or L.REPORT_BLIZZ_HOWTO):format(short)
    end
    SM:Fire("GUARD_REPORTED", short, reason)
    return true, text
end

-- Unpassender Beacon-Text: blendet das Beacon bei dir sofort aus; ab 3 Meldungen bei allen.
function Guard:ReportBeacon(b)
    if not b or b.own then return false, L.REPORT_SELF end
    local key = b.sender .. ":" .. tostring(b.id)
    local s = self:Store()
    s.beacons[key] = s.beacons[key] or {}
    if s.beacons[key][Me()] then return false, L.REPORT_ALREADY end
    s.beacons[key][Me()] = time()
    local r = { t = time(), r = "b", g = MyGuild(), x = tostring(b.id) }
    if SM.Beacon then
        SM.Beacon:Transmit(ReportMsg(b.sender, r))
        SM.Beacon:Remove(b.key, "reported")
    end
    return true, L.REPORT_BEACON_DONE
end

function Guard:IsBeaconHidden(key)
    local s = self:Store()
    local byRep = s.beacons[key]
    if not byRep then return false end
    if byRep[Me()] then return true end
    local n = 0
    for rep in pairs(byRep) do
        if self:KnownLongEnough(rep) and not self:Weightless(rep) then n = n + 1 end
    end
    return n >= NEEDED
end

-- Blizzards Meldefenster mit dem Spieler öffnen (abschicken muss man selbst).
function Guard:OpenBlizzardReport(name, w)
    if not (ReportFrame and ReportFrame.InitiateReport and ReportInfo and Enum and Enum.ReportType and PlayerLocation) then
        return false
    end
    local loc
    if w and w.line and PlayerLocation.CreateFromChatLineID then
        local ok, l = pcall(PlayerLocation.CreateFromChatLineID, PlayerLocation, w.line)
        if ok then loc = l end
    end
    if not loc and w and w.guid and PlayerLocation.CreateFromGUID then
        local ok, l = pcall(PlayerLocation.CreateFromGUID, PlayerLocation, w.guid)
        if ok then loc = l end
    end
    if not loc then return false end
    local ok, info = pcall(ReportInfo.CreateReportInfoFromType, ReportInfo, Enum.ReportType.Chat)
    if not ok or not info then return false end
    return (pcall(ReportFrame.InitiateReport, ReportFrame, info, name, loc))
end

---------------------------------------------------------------------------
-- Empfangen
---------------------------------------------------------------------------
function Guard:HandleReport(text, reporter)
    local target, reason, t, g, x = text:match("^T;1;([^;]+);([sihb]);(%d+);([^;]*);([^;]*)$")
    if not target then return end
    t = tonumber(t)
    local now = time()
    if not t or t > now + 300 or t < now - KEEP_REPORTS then return end
    if target == reporter then return end
    local s = self:Store()
    if reason == "b" then
        local key = target .. ":" .. x
        s.beacons[key] = s.beacons[key] or {}
        s.beacons[key][reporter] = t
        if self:IsBeaconHidden(key) and SM.Beacon and SM.Beacon.cache[key] then
            SM.Beacon:Remove(key, "reported")
        end
        return
    end
    s.reports[target] = s.reports[target] or {}
    local old = s.reports[target][reporter]
    if old and old.t == t then return end            -- schon bekannt (erneut gesendet)
    s.reports[target][reporter] = { t = t, r = reason, g = g }
    if x ~= "" and x:match("^Player%-") then s.guids[x] = s.guids[x] or target end
    self:Evaluate(target)
end

function Guard:HandleMessage(text, dist, sender)
    local short = ShortName(sender)
    if not short or short == Me() then return end
    self:Seen(short)
    local kind = text:sub(1, 1)
    if kind == "T" then
        self:HandleReport(text, short)
    elseif kind == "P" then
        self:Answer(short, sender)
    elseif kind == "K" and dist == "WHISPER" then
        local untilTime = tonumber(text:match("^K;1;(%d+)$") or "")
        if untilTime then
            self.ignoredBy = self.ignoredBy or {}
            self.ignoredBy[short] = untilTime
            if not self.ignoredNoticeShown then
                self.ignoredNoticeShown = true
                SM:Print(L.BLOCK_OTHERS)
            end
        end
    end
end

-- Jemand ist (wieder) da: Ist er gesperrt, bekommt er einmal pro Stunde den Hinweis.
-- Wer ihn gemeldet hat, schickt seine Meldung erneut (z. B. nach einer Neuinstallation).
function Guard:Answer(short, full)
    if not self:IsBlocked(short) then return end
    local s, now = self:Store(), time()
    local last = s.notices[short]
    if last and (now - last) < NOTICE_EVERY then return end
    s.notices[short] = now
    local v = self:Verdict(short)
    if SM.Beacon then
        SM.Beacon:Whisper(full or short, ("K;1;%d"):format(v.perm and 0 or (v.untilTime or 0)))
        local mine = s.mine[short]
        if mine then SM.Beacon:Transmit(ReportMsg(short, mine)) end
    end
end

---------------------------------------------------------------------------
-- Regelmäßig: "ich bin da" und eigene Meldungen erneut senden
---------------------------------------------------------------------------
function Guard:SendPresence()
    if not SM:Active() or not SM.Beacon then return end
    SM.Beacon:Broadcast("P;1")
end

function Guard:ResendOwn()
    if not SM:Active() or not SM.Beacon then return end
    local s, now = self:Store(), time()
    local list = {}
    for target, r in pairs(s.mine) do
        if r.r ~= "b" and (now - r.t) <= RESEND_OWN then list[#list + 1] = ReportMsg(target, r) end
    end
    for i, msg in ipairs(list) do
        if i > 20 then break end
        C_Timer.After(i * 2, function() if SM:Active() then SM.Beacon:Broadcast(msg) end end)
    end
end

function Guard:Start()
    if self.started then return end
    self.started = true
    C_Timer.After(25, function() self:SendPresence() end)
    C_Timer.After(45, function() self:ResendOwn() end)
    self.presenceTimer = C_Timer.NewTicker(PRESENCE_EVERY, function() self:SendPresence() end)
    self.resendTimer = C_Timer.NewTicker(RESEND_EVERY, function() self:ResendOwn() end)
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
SM:RegisterEvent(Guard, "CHAT_MSG_ADDON", function(_, prefix, text, dist, sender)
    if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" or not SM.db then return end
    if not SM.Rules:Accepted() then return end
    Guard:HandleMessage(text, dist, sender)
end)

-- Wer mir schreibt (geflüstert oder in der Gruppe), darf ich melden.
local WROTE_EVENTS = { "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }
local Wrote = {}
for _, ev in ipairs(WROTE_EVENTS) do
    SM:RegisterEvent(Wrote, ev, function(event, text, sender, _, _, _, _, _, _, _, _, lineID, guid)
        if SM.db then Guard:NoteWrote(sender, guid, lineID, text, event:gsub("^CHAT_MSG_", "")) end
    end)
end

-- Sperren wirken sofort: Beacons und Instant-Runden des Gesperrten verschwinden.
SM:RegisterCallback("GUARD_CHANGED", function(target, blocked)
    if target == Me() then
        if blocked then
            SM:StopModules()
            SM:Print(Guard:BlockText())
        elseif SM:Active() then
            SM:StartModules()
        end
        return
    end
    if blocked then
        if SM.Beacon then SM.Beacon:RemoveBySender(target, "blocked") end
        if SM.Circle then SM.Circle:Forget(target) end
    end
end)

SM:RegisterCallback("READY", function() if SM:Active() then Guard:Start() end end)
SM:RegisterCallback("RULES_ACCEPTED", function() if SM:Active() then Guard:Start() end end)

SM:RegisterCommand("melden", function(rest)
    local name = (rest or ""):match("^(%S+)")
    if not name then SM:Print(L.REPORT_USAGE) return end
    name = name:sub(1, 1):upper() .. name:sub(2)
    local ok, why = Guard:CanReport(name)
    if not ok then SM:Print(why) return end
    Guard:ShowDialog(name)
end, "report")
