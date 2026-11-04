local ADDON, SM = ...
local L = SM.L
local Q = SM.QuestInfo

local Beacon = SM:NewModule("beacon")

---------------------------------------------------------------------------
-- Konstanten
---------------------------------------------------------------------------
local PREFIX = "SMForever"       -- Addon-Nachrichten-Präfix (max. 16 Zeichen)
local CHANNEL = "SMForever"      -- versteckter Custom-Channel
local PROTO = 2                  -- Version der kurzen Nachrichten (U = Stand-Update, X = Abbruch)
local PROTO_B = 3                -- Version der Beacon-Nachricht (v2 und v1 werden weiter gelesen)
-- Nur noch zwei Arten: Quest und Lagerfeuer (einfach zusammen sein). Alles, was der Dungeon-Browser
-- löst, braucht kein Beacon. Ältere Versionen schicken noch "grind"/"event" - die werden ignoriert.
local KINDS = { quest = true, campfire = true }
-- Ältere Versionen nannten die Art "elite"; sie wird als "quest" gelesen.
local KIND_ALIAS = { elite = "quest" }
local MAX_TITLE_BYTES = 48
local MAX_ZONE_BYTES = 32
local MAX_MSG_BYTES = 255 - #PREFIX - 1   -- Blizzard zählt Präfix + Text zusammen
local MIN_TTL, MAX_TTL = 1, 120  -- Minuten, harte Grenzen beim Empfang
local RECV_MIN_INTERVAL = 10     -- Sek.: Mindestabstand NEUER Beacons desselben Senders
local MAX_CACHE = 200            -- globale Obergrenze im Cache
local CONNECT_DELAY = 15         -- Sek. nach Login, damit Standard-Channels zuerst da sind
local CONNECT_INTERVAL = 30      -- Sek.: Prüfintervall für Channel-Verbindung
local PRUNE_INTERVAL = 30        -- Sek.: Aufräumen abgelaufener Beacons
local QUEST_UPDATE_INTERVAL = 30  -- Sek.: so oft sendet das eigene Beacon höchstens einen neuen Quest-Stand
local UPDATE_MIN_INTERVAL = 10    -- Sek.: Mindestabstand empfangener Stand-Updates je Beacon
local WHISPER_LOCK = 60           -- Sek.: pro Spieler höchstens eine Begrüßung

Beacon.cache = {}      -- key -> beacon
Beacon.recvLast = {}   -- sender -> GetTime() des letzten neuen Beacons
Beacon.lastSent = -math.huge
Beacon.lastQuestUpdate = -math.huge
Beacon.whisperLock = {}  -- Spielername -> GetTime() der letzten Begrüßung

---------------------------------------------------------------------------
-- Kompatibilitäts-Wrapper (Era/TBC/Wrath/Cata/MoP unterscheiden sich)
---------------------------------------------------------------------------
local function RegisterPrefix(prefix)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        return C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    elseif RegisterAddonMessagePrefix then
        return RegisterAddonMessagePrefix(prefix)
    end
end

local function SendAddon(prefix, msg, dist, target)
    local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not fn then return false end
    local ok = pcall(fn, prefix, msg, dist, target)
    return ok
end

local function IsPlayerIgnored(name)
    local fn = (C_FriendList and C_FriendList.IsIgnored) or IsIgnored
    if not fn then return false end
    local ok, res = pcall(fn, name)
    return ok and res and true or false
end

-- Name in der Sprache des Addons (ZoneNames.lua), sonst wie im Spiel
local function MapName(mapID)
    return SM:MapName(mapID)
end

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------
local function ShortName(name)
    return (name and name:match("^([^-]+)")) or name or "?"
end

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Kürzt auf maxBytes, ohne ein UTF-8-Zeichen (z. B. Umlaut) zu zerschneiden.
local function TrimUTF8(s, maxBytes)
    if #s <= maxBytes then return s end
    s = s:sub(1, maxBytes)
    local i = #s
    while i > 0 and s:byte(i) >= 0x80 and s:byte(i) < 0xC0 do i = i - 1 end
    if i > 0 then
        local b = s:byte(i)
        local len = (b >= 0xF0 and 4) or (b >= 0xE0 and 3) or (b >= 0xC0 and 2) or 1
        if i + len - 1 > #s then s = s:sub(1, i - 1) end
    end
    return s
end

-- Entfernt Steuerzeichen und alle |-Escape-Sequenzen (Farben, Links, Texturen).
local function SanitizeText(text, maxBytes)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|H.-|h", ""):gsub("|[hrTt]", "")
    text = text:gsub("|", ""):gsub("%c", ""):gsub(";", ",")
    text = text:match("^%s*(.-)%s*$") or ""
    return TrimUTF8(text, maxBytes)
end

local function SanitizeTitle(title)
    return SanitizeText(title, MAX_TITLE_BYTES)
end

local function SanitizeZone(zone)
    return SanitizeText(zone, MAX_ZONE_BYTES)
end

local function KindName(kind)
    return L["KIND_" .. kind]
end

-- Text eines Beacons ohne eigenen Text: Lagerfeuer bekommen einen netten Standardtext in der
-- Sprache des Lesers (gesendet wird dann nichts), alles andere den Namen der Art.
local function DefaultTitle(kind)
    if kind == "campfire" then return L.CAMP_DEFAULT_TITLE end
    return KindName(kind)
end

---------------------------------------------------------------------------
-- Cache
---------------------------------------------------------------------------
-- Wartezeit zwischen eigenen Beacons in Sekunden (im Testmodus 0).
function Beacon:Cooldown()
    if SM:IsTestMode() then return 0 end
    return SM.db.beacon.cooldown
end

function Beacon:Count()
    local n = 0
    for _ in pairs(self.cache) do n = n + 1 end
    return n
end

function Beacon:CountBySender(sender)
    local n = 0
    for _, b in pairs(self.cache) do
        if b.sender == sender then n = n + 1 end
    end
    return n
end

function Beacon:GetAll()
    local list = {}
    for _, b in pairs(self.cache) do list[#list + 1] = b end
    table.sort(list, function(a, c) return a.created < c.created end)
    return list
end

function Beacon:Remove(key, reason)
    local b = self.cache[key]
    if not b then return end
    self.cache[key] = nil
    SM:Fire("BEACON_REMOVED", b, reason)
end

function Beacon:RemoveBySender(sender, reason)
    local keys = {}
    for key, b in pairs(self.cache) do
        if b.sender == sender then keys[#keys + 1] = key end
    end
    for _, key in ipairs(keys) do self:Remove(key, reason) end
    return #keys
end

function Beacon:RemoveOldestOf(sender)
    local oldestKey, oldest
    for key, b in pairs(self.cache) do
        if b.sender == sender and (not oldest or b.created < oldest) then
            oldestKey, oldest = key, b.created
        end
    end
    if oldestKey then self:Remove(oldestKey, "replaced") end
end

function Beacon:Prune()
    local now = GetTime()
    local expired = {}
    for key, b in pairs(self.cache) do
        if b.expires <= now then expired[#expired + 1] = key end
    end
    for _, key in ipairs(expired) do self:Remove(key, "expired") end
end

function Beacon:Add(b)
    self.cache[b.key] = b
    SM:Fire("BEACON_ADDED", b)
end

---------------------------------------------------------------------------
-- Transport: versteckter Channel + optional Gilde / Gruppe
---------------------------------------------------------------------------
local function GetChannelIndex()
    local id = GetChannelName(CHANNEL)
    if id and id > 0 then return id end
end

local function HideChannelFromChat()
    if not ChatFrame_RemoveChannel then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then pcall(ChatFrame_RemoveChannel, cf, CHANNEL) end
    end
end

local function NoticeFilter(_, _, _, _, _, channelName)
    if channelName and channelName:find(CHANNEL, 1, true) then
        return true -- "Channel betreten/verlassen"-Meldungen unterdrücken
    end
end

function Beacon:Connect()
    if not self.enabled or not SM.db.beacon.useChannel then return end
    if GetChannelIndex() then
        HideChannelFromChat()
        return
    end
    SM:Debug("joining channel", CHANNEL)
    JoinChannelByName(CHANNEL)
    -- Blizzard fügt den Channel nach dem Beitritt dem Chatfenster hinzu;
    -- deshalb mehrfach verzögert wieder ausblenden.
    C_Timer.After(1, HideChannelFromChat)
    C_Timer.After(3, HideChannelFromChat)
end

function Beacon:Disconnect()
    if GetChannelIndex() then LeaveChannelByName(CHANNEL) end
end

-- Eine kurze Nachricht direkt an einen Spieler (Flüster-Weg, unsichtbar für ihn im Chat).
function Beacon:Whisper(target, msg)
    if SM.Guard:SelfBlocked() then return false end -- gesperrt: das Addon sendet nichts mehr
    if SM.Probe and SM.Probe.on then return SM.Probe:Outgoing(target, msg) end -- Probe: nichts geht raus
    local ok = SendAddon(PREFIX, msg, "WHISPER", target)
    SM:Debug("whisper", target, msg, ok and "ok" or "FAILED")
    return ok
end

function Beacon:IsIgnored(name)
    return IsPlayerIgnored(ShortName(name))
end

-- Filter aus den Einstellungen (Karte & Chat-Hinweise): Arten und "nur Quests aus meinem Questlog".
-- Eigene Beacons fallen nie durch.
function Beacon:PassesFilter(b, byID)
    if not b or b.own then return true end
    local f = SM.db.pins
    if f.kinds and f.kinds[b.kind] == false then return false end
    if f.logOnly and b.kind == "quest" then
        if not b.questID then return false end
        local stand = SM.QuestInfo:OwnStand(b.questID, byID)
        if stand ~= "log" and stand ~= "ready" then return false end
    end
    return true
end

-- Eines meiner eigenen Beacons anhand seiner Nummer.
function Beacon:FindOwn(id)
    return self.cache[self.playerName .. ":" .. tostring(id)]
end

-- Sendet an alle aktivierten Wege. Gibt true zurück, wenn mindestens einer klappte.
function Beacon:Transmit(msg)
    if SM.Guard:SelfBlocked() then return false end -- gesperrt: das Addon sendet nichts mehr
    if SM.Probe and SM.Probe.on then return SM.Probe:Outgoing(nil, msg) end -- Probe: nichts geht raus
    local db = SM.db.beacon
    local sent = false

    if db.useChannel then
        local idx = GetChannelIndex()
        if idx and SendAddon(PREFIX, msg, "CHANNEL", idx) then sent = true end
    end
    if db.useGuild and IsInGuild() then
        if SendAddon(PREFIX, msg, "GUILD") then sent = true end
    end
    if db.useParty then
        if IsInRaid() then
            if SendAddon(PREFIX, msg, "RAID") then sent = true end
        elseif IsInGroup() then
            if SendAddon(PREFIX, msg, "PARTY") then sent = true end
        end
    end

    SM:Debug("send", msg, sent and "ok" or "FAILED")
    return sent
end

-- Hintergrund-Nachrichten (Anwesenheit, Zuhörer-Status, Bürgschaften, ältere Meldungen erneut)
-- gehen nur EINMAL raus: über den versteckten Channel, oder - wenn der aus ist - über die Gilde.
-- So entsteht kein dreifacher Verkehr über Channel, Gilde und Gruppe.
function Beacon:Broadcast(msg)
    if SM.Guard:SelfBlocked() then return false end
    if SM.Probe and SM.Probe.on then return SM.Probe:Outgoing(nil, msg) end
    local idx = SM.db.beacon.useChannel and GetChannelIndex()
    local ok
    if idx then
        ok = SendAddon(PREFIX, msg, "CHANNEL", idx)
    elseif IsInGuild() then
        ok = SendAddon(PREFIX, msg, "GUILD")
    end
    SM:Debug("background", msg, ok and "ok" or "FAILED")
    return ok and true or false
end

-- Eigene Fraktion als ein Buchstabe ("A" / "H"), nil wenn unbekannt
local function MyFaction()
    local fac = type(UnitFactionGroup) == "function" and UnitFactionGroup("player")
    return (fac == "Alliance" and "A") or (fac == "Horde" and "H") or nil
end
Beacon.MyFaction = MyFaction

---------------------------------------------------------------------------
-- Empfangen
---------------------------------------------------------------------------
-- Zerlegt eine B-Nachricht (v3 mit Quest-Zone, v2 mit Quest-Feldern, v1 ohne). Gibt eine Tabelle oder nil zurück.
--   v3: B;3;id;kind;mapID;x;y;voice;ttl;questID;stand;belohnung;questzone;questname;titel
--   v2: B;2;id;kind;mapID;x;y;voice;ttl;questID;stand;belohnung;questname;titel
--   v1: B;1;id;kind;mapID;x;y;voice;ttl;titel
local function ParseBeacon(text)
    local ver, id, kind, mapID, x, y, voice, ttl, qid, prog, rew, qzone, qname, title =
        text:match("^B;(3);(%d+);(%a+);(%d+);(%d+);(%d+);([012][qnh]*);(%d+);(%d+);([%d,]*);([%w,]*);([^;]*);([^;]*);(.*)$")
    if ver then
        return { id = id, kind = kind, mapID = mapID, x = x, y = y, voice = voice, ttl = ttl,
                 qid = qid, prog = prog, rew = rew, qzone = qzone, qname = qname, title = title }
    end
    ver, id, kind, mapID, x, y, voice, ttl, qid, prog, rew, qname, title =
        text:match("^B;(2);(%d+);(%a+);(%d+);(%d+);(%d+);([01]);(%d+);(%d+);([%d,]*);([%w,]*);([^;]*);(.*)$")
    if ver then
        return { id = id, kind = kind, mapID = mapID, x = x, y = y, voice = voice, ttl = ttl,
                 qid = qid, prog = prog, rew = rew, qzone = "", qname = qname, title = title }
    end
    ver, id, kind, mapID, x, y, voice, ttl, title =
        text:match("^B;(1);(%d+);(%a+);(%d+);(%d+);(%d+);([01]);(%d+);(.*)$")
    if ver then
        return { id = id, kind = kind, mapID = mapID, x = x, y = y, voice = voice, ttl = ttl,
                 qid = "0", prog = "", rew = "", qzone = "", qname = "", title = title }
    end
end

-- Stand-Update eines vorhandenen Beacons: U;2;id;erledigt,gesamt,zustand
function Beacon:HandleUpdate(text, short)
    local id, prog = text:match("^U;2;(%d+);([%d,]+)$")
    if not id then return end
    local b = self.cache[short .. ":" .. id]
    if not b or not b.questID then return end
    local now = GetTime()
    if b.updated and (now - b.updated) < UPDATE_MIN_INTERVAL then return end
    local d, t, s = Q.DecodeProgress(prog)
    if not d then return end
    b.done, b.total, b.qstate, b.updated = d, t, s, now
    SM:Fire("BEACON_UPDATED", b)
end

-- S;1;id;stufe+kürzel - die Sprachchat-Stufe eines laufenden Beacons hat sich geändert
local VOICE_MIN_INTERVAL = 8   -- Sek.: so oft nimmt der Empfänger höchstens eine Änderung an
function Beacon:HandleVoice(text, short)
    local id, v = text:match("^S;1;(%d+);([012][qnh]*)$")
    if not id then return end
    local b = self.cache[short .. ":" .. id]
    if not b then return end
    local now = GetTime()
    if b.voiceChanged and (now - b.voiceChanged) < VOICE_MIN_INTERVAL then return end
    b.voiceChanged = now
    b.voice = SM.Social.VoiceLevel(v:sub(1, 1))
    local flags = SM.Social.ParseFlags(v:sub(2))
    b.quiet, b.newbie, b.helper = flags.quiet, flags.newbie, flags.helper
    SM:Fire("BEACON_UPDATED", b)
end

-- Sprachchat-Stufe meiner laufenden Beacons ändern, ohne dass die Zeit neu startet.
-- Gibt true + Text zurück, oder false + Grund.
local VOICE_SEND_LOCK = 10
function Beacon:SetOwnVoice(level)
    level = SM.Social.VoiceLevel(level)
    local own = {}
    for _, b in pairs(self.cache) do if b.own then own[#own + 1] = b end end
    if #own == 0 then return false end
    local now = GetTime()
    local wait = math.ceil(VOICE_SEND_LOCK - (now - (self.lastVoiceSent or -math.huge)))
    if wait > 0 and not SM:IsTestMode() then return false, L.VOICE_WAIT:format(wait) end
    local flagStr = SM.Social:OwnFlags()
    local changed = 0
    for _, b in ipairs(own) do
        if b.voice ~= level then
            b.voice = level
            if self:Transmit(("S;1;%d;%d%s"):format(b.id, level, flagStr)) then changed = changed + 1 end
            SM:Fire("BEACON_UPDATED", b)
        end
    end
    if changed == 0 then return false end
    self.lastVoiceSent = now
    return true, L.VOICE_CHANGED:format(L["FORM_VOICE_" .. level])
end

function Beacon:HandleMessage(text, dist, sender)
    local db = SM.db.beacon
    local short = ShortName(sender)
    if short == self.playerName then return end -- eigenes Echo
    if SM:IsDND() then return end                -- Nicht stören: nichts empfangen
    if SM.Guard:IsBlocked(short) then return end -- gesperrt (Troll-Schutz): wird überall ignoriert

    local kindChar = text:sub(1, 1)

    if kindChar == "X" then
        local ver, what = text:match("^X;(%d+);(%a+)$")
        ver = tonumber(ver)
        if (ver == 1 or ver == 2) and what == "all" then
            self:RemoveBySender(short, "cancelled")
        end
        return
    end
    if kindChar == "U" then
        self:HandleUpdate(text, short)
        return
    end
    if kindChar == "S" then
        self:HandleVoice(text, short)
        return
    end
    if kindChar == "C" or kindChar == "A" then
        -- "Ich komme" / "Fast da!": nur als Flüster-Nachricht an den Ersteller gültig
        if dist == "WHISPER" and SM.Eta and SM.Eta.enabled then
            SM.Eta:HandleWhisper(text, short, sender)
        end
        return
    end
    if kindChar ~= "B" then return end

    local m = ParseBeacon(text)
    if m then m.kind = KIND_ALIAS[m.kind] or m.kind end
    if not m or not KINDS[m.kind] then
        SM:Debug("dropped malformed message from", short)
        return
    end

    local x, y, mapID, ttl = tonumber(m.x), tonumber(m.y), tonumber(m.mapID), tonumber(m.ttl)
    if x > 10000 or y > 10000 then return end
    -- Beacons der anderen Fraktion ausblenden: anschreiben könnte man sie ohnehin nicht
    local fac = (m.rew == "A" or m.rew == "H") and m.rew or nil
    local mine = MyFaction()
    if fac and mine and fac ~= mine then return end

    local title = SanitizeTitle(m.title)
    if SM.Filter:Check(title) then
        SM:Debug("filtered title from", short)
        return
    end

    -- Quest-Angaben: der Name kommt von einem Fremden, deshalb gilt der Filter
    -- (etwas milder, denn Quests heißen manchmal "Dungeon" oder "Raid ...").
    local qid = tonumber(m.qid) or 0
    if qid > 9999999 then qid = 0 end
    local qname = SanitizeTitle(m.qname)
    if qid > 0 and SM.Filter:Check(qname, true) then
        SM:Debug("filtered quest name from", short)
        return
    end
    local qzone = SanitizeZone(m.qzone)
    if qzone ~= "" and SM.Filter:Check(qzone, true) then qzone = "" end -- nur die Zone weglassen

    local key = short .. ":" .. m.id
    if self.cache[key] then return end                -- Duplikat (Channel + Gilde)
    if SM.Guard:IsBeaconHidden(key) then return end   -- als unpassend gemeldet
    if IsPlayerIgnored(short) then return end

    local now = GetTime()
    local last = self.recvLast[short]
    if last and (now - last) < RECV_MIN_INTERVAL then
        SM:Debug("rate-limited", short)
        return
    end
    if self:Count() >= MAX_CACHE then
        SM:Debug("cache full, dropped", key)
        return
    end

    if self:CountBySender(short) >= db.maxPerPlayer then
        self:RemoveOldestOf(short)
    end

    self.recvLast[short] = now
    local minutes = math.min(Clamp(ttl, MIN_TTL, MAX_TTL), db.ttl)

    local b = {
        key = key, sender = short, from = sender, id = tonumber(m.id),
        kind = m.kind, mapID = mapID, x = x / 10000, y = y / 10000,
        voice = SM.Social.VoiceLevel(m.voice:sub(1, 1)),
        title = title, created = now, expires = now + minutes * 60, own = false,
    }
    if qid > 0 then
        b.questID = qid
        b.questName = (qname ~= "") and qname or nil
        b.qzone = (qzone ~= "") and qzone or nil
        b.done, b.total, b.qstate = Q.DecodeProgress(m.prog)
        if not b.done then b.done, b.total, b.qstate = 0, 0, Q.STATE_PROGRESS end
        b.updated = now
    end
    local flags = SM.Social.ParseFlags(m.voice:sub(2))
    b.quiet, b.newbie, b.helper = flags.quiet, flags.newbie, flags.helper
    if title == "" then title = b.questName or DefaultTitle(m.kind); b.title = title end
    self:Add(b)

    if db.notify and self:PassesFilter(b) and not SM:Calm() and self:Relevant(b) then
        local line = L.BEACON_NEW:format(short, title, KindName(m.kind))
        -- Wiedersehen: bekannte Spieler fallen gleich auf
        if SM.Social:Known(short) then line = line .. " |cff2A6F2A(" .. L.KNOWN_SHORT .. ")|r" end
        SM:Print(line)
    end
end

---------------------------------------------------------------------------
-- Senden / Erstellen / Abbrechen
---------------------------------------------------------------------------
-- Baut die Nachricht und kürzt den Text, bis sie in die 255 Byte passt.
-- Im früheren Feld für Belohnungen steht jetzt die Fraktion ("A" / "H"): Ältere Versionen
-- lesen dort nur Belohnungen wie "c123" und übergehen den Buchstaben einfach.
local function BuildMessage(f)
    local title = f.title
    while true do
        local msg = string.format("B;%d;%d;%s;%d;%d;%d;%s;%d;%d;%s;%s;%s;%s;%s",
            PROTO_B, f.id, f.kind, f.mapID, f.xi, f.yi,
            SM.Social.VoiceLevel(f.voice) .. (f.flags or ""), f.ttl,
            f.qid or 0, f.prog or "", f.faction or "", f.qzone or "", f.qname or "", title)
        if #msg <= MAX_MSG_BYTES then return msg end
        if #title > 8 then
            title = TrimUTF8(title, #title - 8)
        else
            return msg
        end
    end
end

function Beacon:LevelOK()
    if SM.Probe and SM.Probe.on and SM.Probe.lowLevel then return false end
    local lvl = type(UnitLevel) == "function" and UnitLevel("player") or 0
    return (tonumber(lvl) or 0) >= SM.Guard.MIN_BEACON_LEVEL
end

-- Gibt true zurück oder false, "Fehlertext". questID ist optional (nur bei der Art "quest").
-- voice: Sprachchat-Stufe 0 = nur Text, 1 = Sprachchat, 2 = Sprachchat, Zuhören okay (true = 1).
-- minutes (optional): eigene Laufzeit, z. B. ein Lagerfeuer-Pin, der so lange lebt wie das Feuer
-- at (optional): { mapID, x, y } - eine Stelle von der Weltkarte (nur in deiner Zone, test8b)
function Beacon:Create(kind, title, voice, questID, minutes, at)
    voice = SM.Social.VoiceLevel(voice)
    local flagStr = SM.Social:OwnFlags()
    local flags = SM.Social.ParseFlags(flagStr)
    if not self.enabled then return false, L.ERR_DISABLED end
    if SM:IsDND() then return false, L.ERR_DND end
    -- Eigene Beacons erst ab Stufe 10 (bremst Wegwerf-Charaktere aus); mitmachen geht immer.
    if not Beacon:LevelOK() then return false, L.ERR_LEVEL:format(SM.Guard.MIN_BEACON_LEVEL) end
    local db = SM.db.beacon

    kind = tostring(kind or ""):lower()
    kind = KIND_ALIAS[kind] or kind
    if not KINDS[kind] then return false, L.ERR_KIND end

    local now = GetTime()
    local wait = math.ceil(self:Cooldown() - (now - self.lastSent))
    if wait > 0 then return false, L.ERR_COOLDOWN:format(wait) end

    if self:CountBySender(self.playerName) >= db.maxPerPlayer then
        return false, L.ERR_MAX:format(db.maxPerPlayer)
    end

    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    local px, py
    if pos and pos.GetXY then px, py = pos:GetXY() end
    if not (px and py) or (px == 0 and py == 0) then
        return false, L.ERR_NO_POS
    end
    if at then
        if at.mapID ~= mapID or not (at.x and at.y) then return false, L.MAP_MEET_ZONE end
        px, py = at.x, at.y
    end

    title = SanitizeTitle(title)
    local banned, word, why = SM.Filter:Check(title)
    if banned then return false, SM.Filter:Message(word, why) end

    -- Quest aus dem eigenen Questlog (Name und Stand kommen von hier)
    local qdata
    if questID then
        if kind ~= "quest" then return false, L.ERR_QUEST_KIND end
        local _, byID = Q:ScanLog()
        local e = byID[questID]
        if not e then return false, L.ERR_QUEST_NOTINLOG end
        qdata = {
            id = questID, name = SanitizeTitle(e.title), zone = SanitizeZone(e.zone),
            done = e.done, total = e.total, state = e.state,
        }
    end

    -- Außerhalb der Quest-Zone (z. B. in Orgrimmar für eine Quest im Arathihochland): Treffpunkt
    -- ist der Flugmeister deiner Fraktion in der Quest-Zone, ohne Flugmeister das Gasthaus.
    -- Gibt es beides nicht, bleibt der Treffpunkt bei dir.
    local meetAt
    if qdata and not at then
        local qmap = SM:MapByName(qdata.zone)
        if qmap and qmap ~= mapID then
            local mx, my, what = SM:MeetPointIn(qmap)
            if mx then mapID, px, py, meetAt = qmap, mx, my, what end
        end
    end

    local autoTitle = (title == "")
    if autoTitle then title = (qdata and qdata.name ~= "" and qdata.name) or DefaultTitle(kind) end

    self.seq = self.seq + 1
    local id = self.seq
    local xi = Clamp(math.floor(px * 10000 + 0.5), 0, 10000)
    local yi = Clamp(math.floor(py * 10000 + 0.5), 0, 10000)
    local ttl = Clamp(tonumber(minutes) or db.ttl, MIN_TTL, MAX_TTL)

    -- Ist der Text nur der Quest-Name, wird er nicht doppelt gesendet.
    local sendTitle = title
    if qdata and title == qdata.name then sendTitle = "" end
    if autoTitle and not qdata then sendTitle = "" end -- Standardtext bildet jeder selbst

    local msg = BuildMessage({
        id = id, kind = kind, mapID = mapID, xi = xi, yi = yi, voice = voice, flags = flagStr, ttl = ttl,
        faction = MyFaction(),
        qid = qdata and qdata.id or 0,
        prog = qdata and Q.EncodeProgress(qdata.done, qdata.total, qdata.state) or "",
        qzone = qdata and qdata.zone or "",
        qname = qdata and qdata.name or "",
        title = sendTitle,
    })

    if not self:Transmit(msg) then return false, L.ERR_NO_TRANSPORT end

    self.lastSent = now
    local b = {
        key = self.playerName .. ":" .. id, sender = self.playerName, id = id,
        kind = kind, mapID = mapID, x = xi / 10000, y = yi / 10000,
        voice = voice, quiet = flags.quiet, newbie = flags.newbie, helper = flags.helper, title = title,
        created = now, expires = now + ttl * 60, own = true,
    }
    if qdata then
        b.questID, b.questName = qdata.id, qdata.name
        b.qzone = (qdata.zone ~= "") and qdata.zone or nil
        b.done, b.total, b.qstate = qdata.done, qdata.total, qdata.state
        b.sentDone, b.sentTotal, b.sentState = qdata.done, qdata.total, qdata.state
        self.lastQuestUpdate = now -- das Beacon trägt den aktuellen Stand schon
    end
    self:Add(b)
    local text = L.BEACON_SET:format(KindName(kind), title)
    if meetAt then
        text = text .. "\n" .. (meetAt == "flight" and L.BEACON_AT_FLIGHT or L.BEACON_AT_INN):format(MapName(mapID))
    end
    return true, text
end

function Beacon:CancelOwn()
    local n = self:RemoveBySender(self.playerName, "cancelled")
    if n > 0 then self:Transmit(string.format("X;%d;all", PROTO)) end
    return n
end

---------------------------------------------------------------------------
-- Eigener Quest-Stand: aktualisiert sich selbst (höchstens alle 30 Sekunden)
---------------------------------------------------------------------------
function Beacon:OwnQuestBeacons()
    local list = {}
    for _, b in pairs(self.cache) do
        if b.own and b.questID then list[#list + 1] = b end
    end
    return list
end

function Beacon:CheckQuestUpdates()
    if SM:IsDND() then return end -- auch ein schon geplanter Versand respektiert "Nicht stören"
    local own = self:OwnQuestBeacons()
    if #own == 0 then return end
    local _, byID = Q:ScanLog()
    for _, b in ipairs(own) do
        local d, t, s = Q:StateFor(b.questID, byID)
        d, t = d or b.done, t or b.total   -- abgegeben/aufgegeben: letzte Zahlen behalten
        local changed = (d ~= b.sentDone) or (t ~= b.sentTotal) or (s ~= b.sentState)
        b.done, b.total, b.qstate = d, t, s
        if changed then
            local msg = string.format("U;%d;%d;%s", PROTO, b.id, Q.EncodeProgress(d, t, s))
            if self:Transmit(msg) then
                b.sentDone, b.sentTotal, b.sentState = d, t, s
            end
            SM:Fire("BEACON_UPDATED", b)
        end
    end
end

-- Wird bei jeder Questlog-Änderung gerufen; sendet nie öfter als alle 30 Sekunden.
function Beacon:QueueQuestUpdate()
    if self.questPending or SM:IsDND() then return end
    if #self:OwnQuestBeacons() == 0 then return end
    local wait = QUEST_UPDATE_INTERVAL - (GetTime() - self.lastQuestUpdate)
    local function run()
        self.questPending = false
        self.lastQuestUpdate = GetTime()
        self:CheckQuestUpdates()
    end
    if wait <= 0 then
        run()
    else
        self.questPending = true
        C_Timer.After(wait, run)
    end
end

---------------------------------------------------------------------------
-- Ort: eigene Zone und Zonen-Filter
---------------------------------------------------------------------------
function Beacon:PlayerMapID()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
end

-- Wo ist die Quest zu machen? Gibt zurück: Ortsname, Kartenname des Beacons, ob beide verschieden sind.
-- Steht die Quest im eigenen Questlog, gilt die dortige Zone (in der eigenen Sprache),
-- sonst die vom Sender mitgeschickte. Ohne Quest-Zone ist der Ort einfach die Karte des Beacons.
function Beacon:Where(b, byID)
    local mapName = MapName(b.mapID)
    if not b.questID then return mapName, mapName, false end
    local zone = Q:LocalZone(b.questID, byID) or b.qzone
    if not zone or zone == "" then return mapName, mapName, false end
    return zone, mapName, zone ~= mapName
end

-- Soll ein neues Beacon im Chat gemeldet werden? Automatisch (seit test8 ohne Einstellung):
-- nur wenn es in deiner Zone liegt oder die Quest in deinem Questlog steht. So kommen keine
-- Meldungen aus Zonen, in die du gar nicht willst.
function Beacon:Relevant(b, byID)
    if self:InPlayerZone(b, self:PlayerMapID()) then return true end
    if b.questID then
        local stand = Q:OwnStand(b.questID, byID)
        if stand == "log" or stand == "ready" then return true end
    end
    return false
end

-- true, wenn das Beacon in der Zone des Spielers liegt (oder die Zone unbekannt ist).
function Beacon:InPlayerZone(b, mapID)
    mapID = mapID or self:PlayerMapID()
    if not mapID then return true end
    return b.mapID == mapID
end

---------------------------------------------------------------------------
-- Kontakt aufnehmen: anflüstern (Linksklick) und einladen (Rechtsklick)
---------------------------------------------------------------------------
local function SendWhisper(text, target)
    return SM:SendChat(text, "WHISPER", target)
end

local function OpenWhisperBox(target)
    if ChatFrame_SendTell then
        pcall(ChatFrame_SendTell, target)
    elseif ChatFrame_OpenChat then
        pcall(ChatFrame_OpenChat, "/w " .. target .. " ")
    end
end

-- Schickt eine freundliche Begrüßung (höchstens einmal pro Minute und Spieler)
-- und öffnet das Flüsterfenster. Gibt true zurück, wenn gerade eine Begrüßung ging.
-- Wird auch vom Radar und von den Kontakten benutzt (short = Name ohne Realm, target = Name zum Anflüstern).
function Beacon:SayHello(short, target, text)
    local now = GetTime()
    local last = self.whisperLock[short]
    local sentNow = false
    if not last or (now - last) >= WHISPER_LOCK or SM:IsTestMode() then
        if SendWhisper(text, target) then
            self.whisperLock[short] = now
            sentNow = true
        end
    end
    OpenWhisperBox(target)
    return sentNow
end

function Beacon:OpenWhisper(target)
    OpenWhisperBox(target)
end

function Beacon:Greet(b)
    if not b or b.own then return false end
    local sent = self:SayHello(b.sender, b.from or b.sender, SM.Social:BeaconGreeting(b.title))
    -- Dem anderen Antwort-Knöpfe anbieten (falls er das Addon hat; sonst passiert nichts)
    if sent then SM.Social:SendHello(b.from or b.sender, "b", b.id) end
    if SM.Contacts then SM.Contacts:Add(b.from or b.sender, "beacon", b.questName or b.title) end
    return sent
end

function Beacon:InviteName(name)
    return SM:InvitePlayer(name)
end

function Beacon:Invite(b)
    if not b or b.own then return false end
    local ok = self:InviteName(b.from or b.sender)
    if ok and SM.Contacts then SM.Contacts:Add(b.from or b.sender, "beacon", b.questName or b.title) end
    return ok
end

---------------------------------------------------------------------------
-- Modul-Lebenszyklus
---------------------------------------------------------------------------
function Beacon:OnEnable()
    self.playerName = UnitName("player")
    self.seq = time() % 1000000   -- neue IDs nach /reload, damit kein Duplikat-Konflikt entsteht
    RegisterPrefix(PREFIX)

    SM:RegisterEvent(self, "CHAT_MSG_ADDON", function(_, prefix, text, dist, sender)
        if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" then return end
        self:HandleMessage(text, dist, sender)
    end)

    -- Quest-Fortschritt: nicht jeder Client kennt jedes Ereignis (Core fängt das ab)
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_WATCH_UPDATE",
                             "QUEST_TURNED_IN", "QUEST_REMOVED" }) do
        SM:RegisterEvent(self, event, function()
            if Q:IsOwnEvent() then return end -- vom Auf-/Zuklappen des Addons selbst ausgelöst
            Q:Invalidate()
            self:QueueQuestUpdate()
        end)
    end

    SM:RegisterEvent(self, "CHAT_MSG_CHANNEL_NOTICE", function(_, _, _, _, channelName)
        if channelName and channelName:find(CHANNEL, 1, true) then
            C_Timer.After(0.2, HideChannelFromChat)
        end
    end)

    if ChatFrame_AddMessageEventFilter and not self.filterAdded then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", NoticeFilter)
        self.filterAdded = true
    end

    self.pruneTimer = C_Timer.NewTicker(PRUNE_INTERVAL, function() self:Prune() end)
    self.connectTimer = C_Timer.NewTicker(CONNECT_INTERVAL, function() self:Connect() end)
    C_Timer.After(CONNECT_DELAY, function() self:Connect() end)
end

function Beacon:OnDisable()
    if self.pruneTimer then self.pruneTimer:Cancel(); self.pruneTimer = nil end
    if self.connectTimer then self.connectTimer:Cancel(); self.connectTimer = nil end
    if GetChannelIndex() then LeaveChannelByName(CHANNEL) end
    for key in pairs(self.cache) do self:Remove(key, "disabled") end
    self.questPending = false
end

