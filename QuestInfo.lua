local ADDON, SM = ...
local L = SM.L

-- Alles rund um Quests: Questlog lesen, Fortschritt, eigener Stand.
-- (Belohnungen zeigt das Addon nicht mehr - ein Quest-Beacon zeigt nur Name und Fortschritt.)
-- Die Quest-Funktionen von Blizzard unterscheiden sich je nach Client (Era/TBC,
-- Wrath, Cata, MoP). Jeder Zugriff ist deshalb abgesichert: fehlt eine Funktion,
-- fehlt nur diese Angabe, aber nichts bricht.
local Q = {}
SM.QuestInfo = Q

-- Zustände eines Quest-Beacons (so werden sie auch gesendet)
Q.STATE_PROGRESS, Q.STATE_READY, Q.STATE_TURNEDIN, Q.STATE_ABANDONED = 0, 1, 2, 3

local function Num(v)
    return type(v) == "number" and v or nil
end

local function Unpack(ok, ...)
    if ok then return ... end
end

-- Ruft fn geschützt auf und gibt ALLE Rückgabewerte zurück (bei Fehler: nichts).
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return Unpack(pcall(fn, ...))
end

---------------------------------------------------------------------------
-- Questlog lesen
---------------------------------------------------------------------------
local function NumEntries()
    local n = Call(GetNumQuestLogEntries)
    if not n and C_QuestLog then n = Call(C_QuestLog.GetNumQuestLogEntries) end
    return Num(n) or 0
end

-- Ein Eintrag: title, level, isHeader, isComplete, questID, isCollapsed
local function Entry(index)
    if type(GetQuestLogTitle) == "function" then
        local title, level, _, isHeader, isCollapsed, isComplete, _, questID = Call(GetQuestLogTitle, index)
        if title ~= nil then
            return title, level, isHeader and true or false,
                (isComplete ~= nil and isComplete ~= -1 and isComplete ~= false), questID,
                (isCollapsed and isCollapsed ~= 0) and true or false
        end
    end
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = Call(C_QuestLog.GetInfo, index)
        if type(info) == "table" then
            local complete = false
            if info.questID and C_QuestLog.IsComplete then
                complete = Call(C_QuestLog.IsComplete, info.questID) and true or false
            end
            return info.title, info.level, info.isHeader and true or false, complete, info.questID,
                info.isCollapsed and true or false
        end
    end
end

-- Zählt die Ziele einer Quest zusammen: erledigt / insgesamt.
local function Objectives(questID, index)
    if C_QuestLog and C_QuestLog.GetQuestObjectives and questID then
        local objs = Call(C_QuestLog.GetQuestObjectives, questID)
        if type(objs) == "table" and #objs > 0 then
            local done, total = 0, 0
            for _, o in ipairs(objs) do
                local need = Num(o.numRequired)
                if need and need > 0 and need <= 100 and o.type ~= "progressbar" then
                    total = total + need
                    done = done + math.min(Num(o.numFulfilled) or 0, need)
                else
                    total = total + 1
                    if o.finished then done = done + 1 end
                end
            end
            return done, total
        end
    end
    if type(GetNumQuestLeaderBoards) == "function" and type(GetQuestLogLeaderBoard) == "function" then
        local n = Num(Call(GetNumQuestLeaderBoards, index)) or 0
        local done, total = 0, 0
        for j = 1, n do
            local desc, _, finished = Call(GetQuestLogLeaderBoard, j, index)
            local have, need = tostring(desc or ""):match("(%d+)%s*/%s*(%d+)")
            have, need = tonumber(have), tonumber(need)
            if have and need and need > 0 and need <= 100 then
                total = total + need
                done = done + math.min(have, need)
            else
                total = total + 1
                if finished then done = done + 1 end
            end
        end
        return done, total
    end
    return 0, 0
end

-- Ein Durchlauf durch das Questlog. Gibt zurück: Liste (nur Quests, keine Überschriften),
-- Tabelle questID -> Eintrag, Tabelle der eingeklappten Überschriften (Titel -> true) und deren Anzahl.
local function RawScan()
    local list, byID, collapsed, nCollapsed = {}, {}, {}, 0
    local zone -- die zuletzt gesehene Überschrift: im Questlog ist das die Zone der Quest
    for i = 1, NumEntries() do
        local title, level, isHeader, complete, questID, isCollapsed = Entry(i)
        if title then
            if isHeader then
                zone = title
                if isCollapsed then collapsed[title] = true; nCollapsed = nCollapsed + 1 end
            elseif questID and questID > 0 then
                local done, total = Objectives(questID, i)
                local e = {
                    index = i, questID = questID, title = title, level = level, zone = zone,
                    complete = complete, done = done, total = total,
                    state = complete and Q.STATE_READY or Q.STATE_PROGRESS,
                }
                list[#list + 1] = e
                byID[questID] = e
            end
        end
    end
    return list, byID, collapsed, nCollapsed
end

-- Im klassischen Questlog verschwinden Quests unter eingeklappten Zonen aus der Aufzählung.
-- Damit keine Quest "fehlt" (und kein Beacon fälschlich als aufgegeben gilt), klappt das Addon
-- bei Bedarf kurz alles auf, liest, und klappt dieselben Zonen wieder zu.
-- fn(list, byID) läuft im aufgeklappten Zustand. Die Ereignisse, die das Auf-/Zuklappen
-- selbst auslöst, werden über IsOwnEvent() erkennbar gemacht.
local OWN_EVENT_SECONDS = 1
local function WithExpanded(fn)
    local list, byID, collapsed, n = RawScan()
    Q.lastExpanded = false
    if n == 0 or type(ExpandQuestHeader) ~= "function" then
        return fn(list, byID)
    end
    Q.lastExpanded = true
    Q.ownEventUntil = GetTime() + OWN_EVENT_SECONDS
    Call(ExpandQuestHeader, 0)
    list, byID = RawScan()
    local ok, a, b = pcall(fn, list, byID)
    if type(CollapseQuestHeader) == "function" then
        for i = NumEntries(), 1, -1 do -- von unten nach oben, damit die Positionen oben stimmen
            local title, _, isHeader = Entry(i)
            if isHeader and collapsed[title] then Call(CollapseQuestHeader, i) end
        end
    end
    Q.ownEventUntil = GetTime() + OWN_EVENT_SECONDS
    if not ok then error(a, 0) end
    return a, b
end

-- true, wenn ein Questlog-Ereignis gerade vom Auf-/Zuklappen des Addons selbst kommt.
function Q:IsOwnEvent()
    return GetTime() < (self.ownEventUntil or 0)
end

-- Beim nächsten Lesen neu einlesen (nach Änderungen am Questlog).
function Q:Invalidate()
    self.scanCache = nil
end

local SCAN_CACHE_SECONDS = 3

-- Liest den ganzen Questlog. Gibt zurück: Liste und eine Tabelle questID -> Eintrag.
-- Sind Zonen eingeklappt, wird das Ergebnis kurz zwischengespeichert, damit das
-- Auf-/Zuklappen nicht ständig passiert.
function Q:ScanLog()
    local c = self.scanCache
    local now = GetTime()
    if c and (now - c.time) < SCAN_CACHE_SECONDS then return c.list, c.byID end
    local list, byID = WithExpanded(function(l, b) return l, b end)
    self.scanCache = Q.lastExpanded and { time = now, list = list, byID = byID } or nil
    self:TrackProgress(list)
    return list, byID
end

function Q:IsFlaggedCompleted(questID)
    if not questID then return false end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return Call(C_QuestLog.IsQuestFlaggedCompleted, questID) and true or false
    end
    if type(IsQuestFlaggedCompleted) == "function" then
        return Call(IsQuestFlaggedCompleted, questID) and true or false
    end
    if type(GetQuestsCompleted) == "function" then
        local t = Call(GetQuestsCompleted)
        return type(t) == "table" and t[questID] and true or false
    end
    return false
end

-- Dein eigener Stand zu einer Quest: "ready", "log", "done" oder "none".
-- byID aus ScanLog() mitgeben, wenn mehrere Quests geprüft werden.
function Q:OwnStand(questID, byID)
    if not questID or questID == 0 then return nil end
    byID = byID or select(2, self:ScanLog())
    local e = byID[questID]
    if e then return e.complete and "ready" or "log" end
    if self:IsFlaggedCompleted(questID) then return "done" end
    return "none"
end

-- Zustand für das Senden. Gibt erledigt, gesamt, Zustand zurück.
-- Steht die Quest nicht mehr im Log: abgegeben (2) oder aufgegeben (3); die Zahlen
-- sind dann nil, damit der Aufrufer die zuletzt bekannten behalten kann.
function Q:StateFor(questID, byID)
    byID = byID or select(2, self:ScanLog())
    local e = byID[questID]
    if e then return e.done, e.total, e.state end
    if self:IsFlaggedCompleted(questID) then return nil, nil, Q.STATE_TURNEDIN end
    return nil, nil, Q.STATE_ABANDONED
end

-- Zone, in der die Quest zu machen ist (Überschrift im eigenen Questlog), sonst nil.
function Q:LocalZone(questID, byID)
    if not questID then return nil end
    byID = byID or select(2, self:ScanLog())
    local e = byID[questID]
    if e and type(e.zone) == "string" and e.zone ~= "" then return e.zone end
end

-- Name der Quest in der Sprache dieses Clients, falls das Spiel ihn kennt.
function Q:LocalTitle(questID, byID)
    if not questID then return nil end
    local e = byID and byID[questID]
    if e then return e.title end
    local t
    if C_QuestLog then
        t = Call(C_QuestLog.GetTitleForQuestID, questID) or Call(C_QuestLog.GetQuestInfo, questID)
    end
    if type(t) == "string" and t ~= "" then return t end
end

---------------------------------------------------------------------------
-- Kodierung für die Addon-Nachricht
---------------------------------------------------------------------------
-- Fortschritt: "erledigt,gesamt,zustand"
function Q.EncodeProgress(done, total, state)
    done = math.max(0, math.min(math.floor(done or 0), 999))
    total = math.max(0, math.min(math.floor(total or 0), 999))
    return ("%d,%d,%d"):format(done, total, state or 0)
end

function Q.DecodeProgress(str)
    local d, t, s = tostring(str or ""):match("^(%d+),(%d+),(%d)$")
    d, t, s = tonumber(d), tonumber(t), tonumber(s)
    if not d then return nil end
    if t > 999 then t = 999 end
    if d > t then d = t end
    if s > Q.STATE_ABANDONED then s = Q.STATE_PROGRESS end
    return d, t, s
end

---------------------------------------------------------------------------
-- Anzeige-Hilfen
---------------------------------------------------------------------------
-- Fortschritt als Text, z. B. "3/8", "bereit" (Texte kommen aus Locales)
function Q.ProgressText(done, total, state)
    if state == Q.STATE_TURNEDIN then return L.PROG_turnedin end
    if state == Q.STATE_ABANDONED then return L.PROG_abandoned end
    if state == Q.STATE_READY then
        if total > 0 then return ("%d/%d - %s"):format(done, total, L.PROG_ready) end
        return L.PROG_ready
    end
    if total > 0 then return ("%d/%d"):format(done, total) end
    return L.PROG_started
end

---------------------------------------------------------------------------
-- Zuletzt vorangekommen: Bei welcher Quest ist zuletzt ein Ziel dazugekommen (3/8 -> 4/8) oder
-- ist sie fertig geworden? Das Treffpunkt-Formular schlägt diese Quest von selbst vor.
---------------------------------------------------------------------------
function Q:TrackProgress(list)
    local prev, cur = self.lastDone, {}
    for _, e in ipairs(list or {}) do
        local d = (tonumber(e.done) or 0) + (e.complete and 1000 or 0)
        cur[e.questID] = d
        if prev and prev[e.questID] and d > prev[e.questID] and SM.db then SM.db.lastQuest = e.questID end
    end
    self.lastDone = cur
end

-- Die Quest mit dem letzten Fortschritt, wenn sie noch im Log steht: Eintrag oder nil
function Q:LastProgress()
    local id = SM.db and SM.db.lastQuest
    if not id then return nil end
    local _, byID = self:ScanLog()
    return byID[id]
end

-- Fortschritt auch ohne offenes Fenster mitbekommen (höchstens einmal pro Sekunde - die
-- Ereignisse kommen oft; das letzte Ziel einer Quest geht so trotzdem nicht verloren, weil
-- jeder spätere Blick ins Questlog den Stand wieder vergleicht)
local watch = { last = -math.huge }
SM:RegisterEvent(watch, "QUEST_LOG_UPDATE", function()
    if Q:IsOwnEvent() or not SM.db then return end
    local now = GetTime()
    if now - watch.last < 1 then return end
    watch.last = now
    -- nur die sichtbaren Quests lesen: hier wird nichts auf- und zugeklappt (das Questlog des
    -- Spielers soll nicht flackern, während er darin blättert)
    Q:TrackProgress((RawScan()))
end)
