local ADDON, SM = ...
local L = SM.L

-- SocializeMe Instant: spontan mit 2 bis 4 anderen plaudern - "SocializeMe Voice" im
-- Sprachchat der Gruppe oder "SocializeMe Text" im Gruppenchat. Bewusst kein 1:1 mit Fremden:
-- eine Runde ist für 3 bis 5 Leute, das ist sicherer und für Schüchterne leichter.
-- Die Oberfläche ist der Tab "Instant" (UI/InstantPanel.lua).
--
-- So läuft es:
--   * Du klickst "Jetzt reden" (Voice) oder "Jetzt schreiben" (Text). Das Thema ist freiwillig:
--     voreingestellt ist "Einfach plaudern", das passt zu jeder Runde; ein eigenes prüft der Filter.
--   * Gibt es eine offene Runde, die passt, fragst du dort an. Der Gastgeber lädt dich in seine
--     Gruppe ein - die Einladung nimmst du selbst an.
--   * Sonst eröffnest du selbst eine Runde (ab Stufe 10, wie bei Beacons). Wer passt, sieht sie
--     und kann anfragen; dein Addon lädt dann ein, solange Platz ist. Offen bleibt die Runde,
--     bis 5 Leute da sind, du sie schließt oder nach 15 Minuten.
--   * Themen gibt es nur schöne: Schweres (Krieg, Politik ...) und alles Sexuelle lässt der
--     Filter nicht durch - beim Senden UND beim Empfangen.
--   * Es geht nichts von selbst in den Chat. Die Knöpfe "Hallo sagen" und "Thema nennen"
--     schreiben erst, wenn du klickst.
--   * Wer möchte, bekommt eine Chatzeile, wenn eine neue Runde aufgeht (Haken im Tab, aus).
--   * Reise-Plauderei (Haken im Tab, aus): beim Abflug mit dem Flugmeister eine Chatzeile,
--     dass du unterwegs mit /sm instant plaudern kannst. Höchstens alle 20 Minuten.
--
-- Probe-Modus (nur mit dem privaten Dev-Zusatz): Circle.sim spielt eine Gruppe nach
-- ({ leader = Name, names = { ... } }) und Circle.simChat zeigt Gruppenchat nur bei dir an.
-- Ohne Dev-Zusatz sind beide immer nil - dann zählt nur die echte Gruppe des Spiels.
--
-- Nachrichten (Präfix SMForever):
--   Z;1;o;id;art;thema;anzahl[;text]   Runde offen (an alle, jede Minute neu)
--                                      art t = Text, v = WoW-Sprachchat, d = Discord (seit test8);
--                                      thema 1-11 oder 0 = eigener text. Ältere Versionen kennen "d"
--                                      nicht und zeigen Discord-Runden gar nicht (statt sie falsch
--                                      als WoW-Sprachchat anzuzeigen).
--   Z;1;x;id                           Runde zu (voll oder beendet)
--   Z;1;j;id                           (geflüstert) ich möchte dazu
--   Z;1;a;id / Z;1;d;id                (geflüstert) Einladung kommt / leider nicht (voll, zu)
--   Z;1;l;id;code                      (geflüstert, test8b) Discord-Einladung der Runde: nur
--                                      discord.gg/<code>. Geht nur an Eingeladene, die schon in der
--                                      Gruppe sind - nie an alle, nie in den Chat. Beim Empfänger
--                                      steht er als anklickbare Zeile im eigenen Chat (Klick = kopieren).
local Circle = SM:NewModule("circle")

local PROTO = 1
local MAX_SIZE = 5
Circle.NUM_TOPICS = 11
local OPEN_TIME = 900           -- Sek.: so lange bleibt eine eigene Runde offen
Circle.OPEN_TIME = OPEN_TIME
local ANNOUNCE_EVERY = 60       -- Sek.: so oft wird die offene Runde neu gemeldet
local HEARD_KEEP = 150          -- Sek.: fremde Runden ohne neue Meldung verschwinden danach
local RECV_MIN = 20             -- Sek.: Mindestabstand empfangener Meldungen je Gastgeber
local JOIN_WAIT = 30            -- Sek.: so lange warten wir auf die Antwort des Gastgebers
local JOIN_LOCK = 10            -- Sek.: Anfragen je Spieler beim Gastgeber
local TOPIC_MAX = 40            -- Zeichen für ein eigenes Thema
local NOTIFY_GAP = 120          -- Sek.: höchstens so oft eine Chatzeile "neue Runde"
local TRAVEL_GAP = 1200         -- Sek.: höchstens so oft die Reise-Zeile beim Abflug
local CODE_MIN, CODE_MAX = 2, 32   -- Länge eines Discord-Einladungscodes

Circle.rounds = {}      -- id -> { id, host, full, mode, topic, text, n, seen }
Circle.own = nil        -- { id, mode, topic, text, opened, invited = { name = true } }
Circle.joining = nil    -- { id, host, full, at }
Circle.member = nil     -- { id, host, mode, topic, text } - ich bin in einer Runde
Circle.recvLast = {}
Circle.joinLast = {}

local function ShortName(name)
    return (name and name:match("^([^-]+)")) or name
end

local function Me() return UnitName("player") end

local function Whisper(target, msg)
    return SM.Beacon and SM.Beacon:Whisper(target, msg)
end

-- Text für Addon-Nachrichten: ohne Trennzeichen, höchstens 40 Zeichen (UTF-8-sicher gekürzt)
local function CleanTopic(text)
    text = tostring(text or ""):gsub("[;|%c]", " "):gsub("%s+", " ")
    text = text:match("^%s*(.-)%s*$")
    return SM.TrimChars(text, TOPIC_MAX)
end
Circle.CleanTopic = CleanTopic

function Circle.TopicName(topic, text)
    if topic == 0 then return (text and text ~= "") and text or L.CIRCLE_TOPIC_1 end
    return L["CIRCLE_TOPIC_" .. tostring(topic)] or L.CIRCLE_TOPIC_1
end

function Circle.ModeName(mode)
    if mode == "d" then return L.CIRCLE_MODE_DISCORD end
    return mode == "v" and L.CIRCLE_MODE_VOICE or L.CIRCLE_MODE_TEXT
end

-- Sprachchat-Runden: über das Spiel (v) oder über Discord (d)
function Circle.IsVoice(mode) return mode == "v" or mode == "d" end

---------------------------------------------------------------------------
-- Discord-Link (test8b): nur Discord-Einladungen - discord.gg/<code>, discord.com/invite/<code>
-- (auch mit https:// oder www.). Gemerkt und weitergegeben wird nur der Code.
---------------------------------------------------------------------------
local function ValidCode(code)
    return type(code) == "string" and #code >= CODE_MIN and #code <= CODE_MAX and code:match("^[%w%-]+$") ~= nil
end
Circle.ValidCode = ValidCode

function Circle.DiscordCode(text)
    local s = tostring(text or ""):gsub("%s", "")
    s = s:gsub("^[Hh][Tt][Tt][Pp][Ss]?://", ""):gsub("^[Ww][Ww][Ww]%.", "")
    local host, path = s:match("^([^/]+)/(.+)$")
    if not host then return nil end
    host = host:lower()
    local code
    if host == "discord.gg" then
        code = path:match("^([%w%-]+)/?$")
    elseif host == "discord.com" or host == "discordapp.com" then
        code = path:match("^[Ii][Nn][Vv][Ii][Tt][Ee]/([%w%-]+)/?$")
    end
    if not ValidCode(code) then return nil end
    return code
end

function Circle.DiscordURL(code) return "https://discord.gg/" .. tostring(code or "") end
function Circle.DiscordShort(code) return "discord.gg/" .. tostring(code or "") end

-- Anklickbarer Link für den eigenen Chat (Klick = Kopierfeld, siehe UI/CopyDialog.lua)
function Circle.DiscordChatLink(code)
    return ("|cff7289da|Hsmforever:discord:%s|h[%s]|h|r"):format(code, Circle.DiscordShort(code))
end

---------------------------------------------------------------------------
-- Gruppe: die echte des Spiels - oder im Probe-Modus die nachgespielte (Circle.sim)
---------------------------------------------------------------------------
local function InGroup()
    if Circle.sim then return true end
    return type(IsInGroup) == "function" and IsInGroup() and true or false
end
Circle.InGroup = InGroup

local function GroupSize()
    if Circle.sim then return 1 + #Circle.sim.names end
    if InGroup() then
        local n = type(GetNumGroupMembers) == "function" and GetNumGroupMembers() or 1
        return math.max(1, n or 1)
    end
    return 1
end
Circle.GroupSize = GroupSize

local function InParty(name)
    if Circle.sim then
        for _, n in ipairs(Circle.sim.names) do if n == name then return true end end
        return false
    end
    return type(UnitInParty) == "function" and UnitInParty(name) and true or false
end

local function CanInvite()
    if Circle.sim then return Circle.sim.leader == Me() end
    if not InGroup() then return true end
    if type(IsInRaid) == "function" and IsInRaid() then return false end
    return type(UnitIsGroupLeader) == "function" and UnitIsGroupLeader("player") or false
end

-- Wer ist mit mir in der Gruppe? (Namen ohne Realm)
function Circle:Members()
    local list = {}
    if self.sim then
        for _, n in ipairs(self.sim.names) do list[#list + 1] = n end
    elseif InGroup() and type(UnitName) == "function" then
        for i = 1, 4 do
            local n = UnitName("party" .. i)
            if n and n ~= Me() then list[#list + 1] = n end
        end
    end
    return list
end

-- Ein Satz in den Gruppenchat (im Probe-Modus nur bei dir angezeigt)
local function PartyChat(text)
    if Circle.sim then
        if Circle.simChat then Circle.simChat(Me(), text) end
    else
        SM:SendChat(text, "PARTY")
    end
end

---------------------------------------------------------------------------
-- Thema prüfen
---------------------------------------------------------------------------
-- Gibt true zurück oder false + Text. Eigene Themen gehen durch den Filter (auch "schwer").
function Circle:CheckTopic(topic, text)
    if topic ~= 0 then
        if topic < 1 or topic > self.NUM_TOPICS then return false, L.CIRCLE_BAD_TOPIC end
        return true
    end
    text = CleanTopic(text)
    if text == "" then return false, L.CIRCLE_NO_TOPIC end
    local bad, word, kind = SM.Filter:CheckTopic(text)
    if bad then return false, SM.Filter:Message(word, kind) end
    return true
end

---------------------------------------------------------------------------
-- Passende Runden der anderen
---------------------------------------------------------------------------
local function Fits(r, mode, topic, text)
    if r.mode ~= mode or r.n >= MAX_SIZE then return false end
    -- "Einfach plaudern" passt zu allem, sonst dasselbe Thema
    if topic == 1 or r.topic == 1 then return true end
    if topic == 0 or r.topic == 0 then
        return topic == r.topic and (text or ""):lower() == (r.text or ""):lower()
    end
    return topic == r.topic
end

-- Runden eines Spielers vergessen (gesperrt oder ignoriert)
function Circle:Forget(name)
    local short = ShortName(name)
    for id, r in pairs(self.rounds) do
        if r.host == short then self.rounds[id] = nil end
    end
    SM:Fire("CIRCLE_CHANGED")
end

function Circle:Prune()
    local now = GetTime()
    for id, r in pairs(self.rounds) do
        if (now - r.seen) > HEARD_KEEP then self.rounds[id] = nil end
    end
end

-- Alle offenen Runden (für die Liste im Fenster), passende zuerst
function Circle:List(mode, topic, text)
    self:Prune()
    local list = {}
    for _, r in pairs(self.rounds) do
        if r.n < MAX_SIZE and not SM.Beacon:IsIgnored(r.host) and not SM.Guard:IsBlocked(r.host) then
            r.fits = (mode ~= nil) and Fits(r, mode, topic, text) or false
            list[#list + 1] = r
        end
    end
    table.sort(list, function(a, b)
        if a.fits ~= b.fits then return a.fits end
        if a.n ~= b.n then return a.n > b.n end    -- fast volle Runden zuerst
        return a.seen > b.seen
    end)
    return list
end

---------------------------------------------------------------------------
-- Suchen, anfragen, eröffnen
---------------------------------------------------------------------------
local function Busy(self)
    if self.own then return L.CIRCLE_BUSY_OWN end
    if self.member then return L.CIRCLE_BUSY_IN end
    if self.joining then return L.CIRCLE_BUSY_ASK end
    if InGroup() then return L.CIRCLE_IN_GROUP end
end

-- Für die Karten im Tab: wie viele Runden und Leute sind gerade offen (je Art; die Sprachchat-
-- Karte zählt WoW-Sprachchat und Discord zusammen)?
function Circle:Stats(mode)
    local rounds, people = 0, 0
    for _, r in ipairs(self:List()) do
        if r.mode == mode or (mode == "v" and r.mode == "d") then rounds = rounds + 1; people = people + r.n end
    end
    return rounds, people
end

-- "Runde suchen": passende Runde anfragen, sonst selbst eine eröffnen.
-- Gibt true/false und einen Text zurück.
function Circle:Search(mode, topic, text)
    if not self.enabled then return false, L.CIRCLE_OFF end
    if SM:IsDND() then return false, L.ERR_DND end
    mode = (mode == "v" or mode == "d") and mode or "t"
    topic = tonumber(topic) or 1
    local ok, why = self:CheckTopic(topic, text)
    if not ok then return false, why end
    if topic == 0 then text = CleanTopic(text) else text = nil end
    local busy = Busy(self)
    if busy then return false, busy end
    for _, r in ipairs(self:List(mode, topic, text)) do
        if r.fits then return self:Join(r) end
    end
    return self:Open(mode, topic, text)
end

-- "Jetzt plaudern": ein Klick, ohne Thema. Tritt der passendsten offenen Runde bei - Text oder
-- Sprachchat wie zuletzt (am Anfang Text), nie automatisch einer Discord-Runde. Gibt es keine,
-- eröffnet es eine Runde "Einfach plaudern" (openMode: t, v oder d - wie du sie gern hättest).
function Circle:QuickChat(mode, openMode)
    if not self.enabled then return false, L.CIRCLE_OFF end
    if SM:IsDND() then return false, L.ERR_DND end
    mode = (mode == "v") and "v" or "t"
    local busy = Busy(self)
    if busy then return false, busy end
    for _, r in ipairs(self:List(mode, 1, nil)) do
        if r.fits and r.mode ~= "d" then return self:Join(r) end
    end
    return self:Open(openMode or mode, 1, nil)
end

-- Bei einer Runde anfragen
function Circle:Join(r)
    if not r then return false, L.CIRCLE_GONE end
    if SM:IsDND() then return false, L.ERR_DND end
    local busy = Busy(self)
    if busy then return false, busy end
    self.joining = { id = r.id, host = r.host, full = r.full, at = GetTime(), round = r }
    Whisper(r.full, ("Z;%d;j;%s"):format(PROTO, r.id))
    local token = self.joining
    C_Timer.After(JOIN_WAIT, function()
        if Circle.joining == token then
            Circle.joining = nil
            SM:Print(L.CIRCLE_NO_ANSWER:format(r.host))
            SM:Fire("CIRCLE_CHANGED")
        end
    end)
    SM:Fire("CIRCLE_CHANGED")
    return true, L.CIRCLE_ASKED:format(r.host, Circle.TopicName(r.topic, r.text))
end

-- Eigene Runde eröffnen (ab Stufe 10)
function Circle:Open(mode, topic, text)
    if not SM.Beacon:LevelOK() then return false, L.CIRCLE_LEVEL:format(SM.Guard.MIN_BEACON_LEVEL) end
    if not CanInvite() then return false, L.CIRCLE_IN_GROUP end
    self.own = { id = tostring(math.random(100000, 999999)), mode = mode, topic = topic, text = text,
                 opened = GetTime(), invited = {}, invitedFull = {}, linkSent = {} }
    -- Discord-Runde: der gemerkte Einladungslink gilt gleich (im Tab Instant änderbar)
    if mode == "d" and ValidCode(SM.db.circle.discord) then self.own.link = SM.db.circle.discord end
    if not self:Announce() then
        self.own = nil
        return false, L.ERR_NO_TRANSPORT
    end
    if self.ticker then self.ticker:Cancel() end
    self.ticker = C_Timer.NewTicker(ANNOUNCE_EVERY, function() Circle:Tick() end)
    SM:Fire("CIRCLE_CHANGED")
    local msg = L.CIRCLE_OPENED:format(Circle.TopicName(topic, text), Circle.ModeName(mode))
    if mode == "d" and not self.own.link then msg = msg .. " " .. L.CIRCLE_DISCORD_ENTER end
    return true, msg
end

function Circle:Announce()
    local o = self.own
    if not o then return false end
    local msg = ("Z;%d;o;%s;%s;%d;%d"):format(PROTO, o.id, o.mode, o.topic, GroupSize())
    if o.topic == 0 then msg = msg .. ";" .. o.text end
    return SM.Beacon:Broadcast(msg)
end

function Circle:Tick()
    local o = self.own
    if not o then return end
    if SM:IsDND() or (GetTime() - o.opened) >= OPEN_TIME or GroupSize() >= MAX_SIZE then
        self:Close(GroupSize() >= MAX_SIZE and "full" or "time")
        return
    end
    self:Announce()
end

-- Eigene Runde schließen. why: "full", "time" oder nil (selbst geschlossen)
function Circle:Close(why)
    local o = self.own
    if not o then return false end
    SM.Beacon:Broadcast(("Z;%d;x;%s"):format(PROTO, o.id))
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    self.own = nil
    -- Kam jemand dazu, geht es als Runde weiter
    if GroupSize() > 1 then
        self.member = { id = o.id, host = Me(), mode = o.mode, topic = o.topic, text = o.text,
                        invited = o.invited, invitedFull = o.invitedFull, linkSent = o.linkSent, link = o.link }
    end
    if why == "full" then SM:Print(L.CIRCLE_FULL)
    elseif why == "time" then SM:Print(GroupSize() > 1 and L.CIRCLE_TIME_GROUP or L.CIRCLE_TIME_ALONE) end
    SM:Fire("CIRCLE_CHANGED")
    return true
end

-- Runde verlassen (Gruppe verlassen)
function Circle:Leave()
    if self.own then self:Close() end
    self.member, self.joining = nil, nil
    if self.sim then
        self.sim = nil
    else
        local leave = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
        if InGroup() and leave then pcall(leave) end
    end
    SM:Fire("CIRCLE_CHANGED")
    return true, L.CIRCLE_LEFT
end

---------------------------------------------------------------------------
-- In der Runde: kurze Sätze in den Gruppenchat (nur auf Klick)
---------------------------------------------------------------------------
function Circle:Current()
    return self.member or self.own
end

-- Meine Runde als Gastgeber (noch offen oder schon zu, aber ich bin Gastgeber)
function Circle:Hosting()
    if self.own then return self.own end
    if self.member and self.member.host == Me() then return self.member end
    return nil
end

-- Discord-Link setzen (Gastgeber). Leer = entfernen. Wird gemerkt und gilt gleich für die
-- laufende Discord-Runde: wer schon da ist, bekommt ihn sofort. Gibt ok und einen Text zurück.
function Circle:SetDiscord(text)
    local s = tostring(text or ""):gsub("%s", "")
    local c = self:Hosting()
    if s == "" then
        SM.db.circle.discord = nil
        if c then c.link = nil end
        SM:Fire("CIRCLE_CHANGED")
        return true, L.CIRCLE_DISCORD_CLEARED
    end
    local code = Circle.DiscordCode(s)
    if not code then return false, L.CIRCLE_DISCORD_BAD end
    SM.db.circle.discord = code
    if c and c.mode == "d" then
        c.link = code
        self:SendLinks()
    end
    SM:Fire("CIRCLE_CHANGED")
    return true, L.CIRCLE_DISCORD_SAVED
end

-- Den Link an alle schicken, die ich eingeladen habe und die jetzt in der Gruppe sind
-- (jeder bekommt ihn einmal; ändert sich der Link, noch einmal). Gibt die Anzahl zurück.
function Circle:SendLinks()
    local c = self:Hosting()
    if not (c and c.mode == "d" and ValidCode(c.link) and c.invited) then return 0 end
    c.linkSent = c.linkSent or {}
    local n = 0
    for short in pairs(c.invited) do
        if InParty(short) and c.linkSent[short] ~= c.link then
            local target = (c.invitedFull and c.invitedFull[short]) or short
            if Whisper(target, ("Z;%d;l;%s;%s"):format(PROTO, c.id, c.link)) then
                c.linkSent[short] = c.link
                n = n + 1
            end
        end
    end
    return n
end

-- Beim Mitspieler: der Link als anklickbare Zeile im eigenen Chat
function Circle:ShowLink(code, host)
    SM:Print(L.CIRCLE_DISCORD_LINK:format(host or "?", Circle.DiscordChatLink(code)))
end

function Circle:SayHello()
    if not InGroup() then return false, L.CIRCLE_NOT_IN end
    PartyChat(L.CIRCLE_HELLO_TEXT)
    return true
end

function Circle:SayTopic()
    local c = self:Current()
    if not c or not InGroup() then return false, L.CIRCLE_NOT_IN end
    PartyChat(L.CIRCLE_TOPIC_TEXT:format(Circle.TopicName(c.topic, c.text)))
    return true
end

-- Opt-in: eine Chatzeile, wenn eine neue Runde aufgeht (nie ein Fenster)
function Circle:Notify(r)
    if not SM.db.circle.notify or self.own or self.member or self.joining or InGroup() then return end
    if SM:IsDND() or SM:Calm() then return end
    local now = GetTime()
    if self.lastNotify and (now - self.lastNotify) < NOTIFY_GAP then return end
    self.lastNotify = now
    SM:Print(L.CIRCLE_NEW_ROUND:format(Circle.ModeName(r.mode), Circle.TopicName(r.topic, r.text), r.host))
end

-- Opt-in: beim Abflug eine Chatzeile "unterwegs plaudern?" (nie ein Fenster)
function Circle:OnTaxi()
    if not SM.db.circle.travel or self.own or self.member or self.joining or InGroup() then return false end
    if SM:IsDND() or SM:Calm() then return false end
    local now = GetTime()
    if self.lastTravel and (now - self.lastTravel) < TRAVEL_GAP then return false end
    self.lastTravel = now
    local n = #self:List()
    SM:Print(n > 0 and L.TRAVEL_LINE_ROUNDS:format(n) or L.TRAVEL_LINE)
    return true
end

---------------------------------------------------------------------------
-- Empfangen
---------------------------------------------------------------------------
function Circle:HandleMessage(text, dist, sender)
    local short = ShortName(sender)
    if not short or short == Me() then return end
    if SM.Guard:IsBlocked(short) or SM.Beacon:IsIgnored(short) then return end
    local what, rest = text:match("^Z;1;(%a);(.*)$")
    if not what then return end
    local now = GetTime()

    if what == "o" then
        local id, mode, topic, n, topicText = rest:match("^(%d+);([tvd]);(%d+);(%d)(.*)$")
        topic, n = tonumber(topic), tonumber(n)
        if not id or not topic or topic > self.NUM_TOPICS or not n or n < 1 then return end
        local last = self.recvLast[short]
        if last and (now - last) < RECV_MIN and not (self.rounds[id] and self.rounds[id].host == short) then return end
        self.recvLast[short] = now
        topicText = topicText:match("^;(.*)$")
        if topic == 0 then
            topicText = CleanTopic(topicText)
            -- Fremde Themen prüfen wir selbst noch einmal (ein anderes Addon könnte alles senden)
            if topicText == "" or SM.Filter:CheckTopic(topicText) then return end
        else
            topicText = nil
        end
        local r = self.rounds[id]
        if r and r.host ~= short then return end   -- fremde ID übernehmen geht nicht
        local new = { id = id, host = short, full = sender, mode = mode, topic = topic,
                      text = topicText, n = math.min(n, MAX_SIZE), seen = now }
        self.rounds[id] = new
        if not r and new.n < MAX_SIZE then self:Notify(new) end
        SM:Fire("CIRCLE_CHANGED")

    elseif what == "x" then
        local id = rest:match("^(%d+)$")
        local r = id and self.rounds[id]
        if r and r.host == short then self.rounds[id] = nil; SM:Fire("CIRCLE_CHANGED") end

    elseif what == "j" and dist == "WHISPER" then
        local id = rest:match("^(%d+)$")
        local o = self.own
        if not o or o.id ~= id then
            Whisper(sender, ("Z;%d;d;%s"):format(PROTO, tostring(id)))
            return
        end
        local last = self.joinLast[short]
        if last and (now - last) < JOIN_LOCK and not SM:IsTestMode() then return end
        self.joinLast[short] = now
        if GroupSize() >= MAX_SIZE or not CanInvite() then
            Whisper(sender, ("Z;%d;d;%s"):format(PROTO, id))
            return
        end
        o.invited[short] = now
        o.invitedFull = o.invitedFull or {}
        o.invitedFull[short] = sender
        Whisper(sender, ("Z;%d;a;%s"):format(PROTO, id))
        SM:InvitePlayer(sender)
        if SM.Contacts then SM.Contacts:Add(sender, "circle", Circle.TopicName(o.topic, o.text)) end
        SM:Print(L.CIRCLE_INVITING:format(short))
        SM:Fire("CIRCLE_CHANGED")

    elseif (what == "a" or what == "d") and dist == "WHISPER" then
        local id = rest:match("^(%d+)$")
        local j = self.joining
        if not j or j.id ~= id or j.host ~= short then return end
        if what == "a" then
            j.accepted = true
            SM:Print(L.CIRCLE_INVITE_COMING:format(short))
        else
            self.joining = nil
            self.rounds[id] = nil
            SM:Print(L.CIRCLE_DECLINED:format(short))
        end
        SM:Fire("CIRCLE_CHANGED")

    elseif what == "l" and dist == "WHISPER" then
        -- Discord-Link vom Gastgeber meiner Discord-Runde (sonst von niemandem)
        local id, code = rest:match("^(%d+);([%w%-]+)$")
        if not ValidCode(code) then return end
        local m, j = self.member, self.joining
        if m and m.id == id and m.host == short and m.mode == "d" then
            if m.link == code then return end
            m.link = code
            self:ShowLink(code, short)
        elseif j and j.id == id and j.host == short and j.round and j.round.mode == "d" then
            j.link = code   -- kommt gleich nach dem Beitreten (siehe OnRoster)
        else
            return
        end
        SM:Fire("CIRCLE_CHANGED")
    end
end

-- Gruppe hat sich geändert: angekommen? voll? allein?
function Circle:OnRoster()
    local inGroup = InGroup()
    local j = self.joining
    if j and inGroup and InParty(j.host) then
        local r = j.round or {}
        self.member = { id = j.id, host = j.host, mode = r.mode, topic = r.topic, text = r.text, link = j.link }
        self.joining = nil
        if SM.Contacts then SM.Contacts:Add(j.full, "circle", Circle.TopicName(r.topic, r.text)) end
        SM:Print(L.CIRCLE_JOINED:format(Circle.TopicName(r.topic, r.text)))
        if r.mode == "d" then
            SM:Print(L.CIRCLE_DISCORD_HINT)
            if j.link then self:ShowLink(j.link, j.host) end
        elseif r.mode == "v" then
            SM:Print(L.CIRCLE_VOICE_HINT)
            if SM.VoiceCard then SM.VoiceCard:OfferOnce("circlevoice") end
        end
    end
    if self.own then
        if GroupSize() >= MAX_SIZE then self:Close("full") else self:Announce() end
    end
    self:SendLinks() -- wer gerade angekommen ist, bekommt den Discord-Link
    if self.member and not inGroup then
        self.member = nil
        SM:Print(L.CIRCLE_ENDED)
    end
    SM:Fire("CIRCLE_CHANGED")
end

---------------------------------------------------------------------------
-- Modul
---------------------------------------------------------------------------
function Circle:OnEnable()
    SM:RegisterEvent(self, "CHAT_MSG_ADDON", function(_, prefix, text, dist, sender)
        if prefix ~= "SMForever" or type(text) ~= "string" or type(sender) ~= "string" or not SM:Active() then return end
        if text:sub(1, 2) == "Z;" then self:HandleMessage(text, dist, sender) end
    end)
    SM:RegisterEvent(self, "GROUP_ROSTER_UPDATE", function() self:OnRoster() end)
    -- Abflug: Wenn du beim Flugmeister ein Ziel wählst (oder das Spiel dir die Steuerung nimmt),
    -- schauen wir ein paar Sekunden lang, ob du wirklich auf dem Flugtier sitzt.
    if not Circle.taxiHooked and type(hooksecurefunc) == "function" and type(TakeTaxiNode) == "function" then
        Circle.taxiHooked = true
        hooksecurefunc("TakeTaxiNode", function() Circle:WatchTaxi() end)
    end
    SM:RegisterEvent(self, "PLAYER_CONTROL_LOST", function() self:WatchTaxi() end)
end

-- Bis zu 8 Sekunden lang jede Sekunde nachsehen, ob der Flug begonnen hat
function Circle:WatchTaxi()
    if not self.enabled or type(UnitOnTaxi) ~= "function" then return end
    local token = {}
    self.taxiWatch = token
    local tries = 0
    local function Check()
        if Circle.taxiWatch ~= token then return end
        tries = tries + 1
        if UnitOnTaxi("player") then
            Circle.taxiWatch = nil
            Circle:OnTaxi()
        elseif tries < 8 then
            C_Timer.After(1, Check)
        end
    end
    C_Timer.After(1, Check)
end

function Circle:OnDisable()
    if self.own then self:Close() end
    self.joining, self.member, self.sim = nil, nil, nil
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
end

SM:RegisterCallback("DND_CHANGED", function(on)
    if on and Circle.own then Circle:Close() end
end)

-- /sm instant: den Tab Instant öffnen
SM:RegisterCommand("instant", function()
    if SM.Window then SM.Window:OpenTab("instant") end
end)
