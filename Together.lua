local ADDON, SM = ...
local L = SM.L
local Social = SM.Social

-- Miteinander, Teil 2:
--   * Kürzel "neu im Spiel" / "hilft gern" (neben "eher ruhig")
--   * Antwort-Hilfe: wer über das Addon angeschrieben oder angewinkt wird, bekommt Antwort-Knöpfe
--   * Winken: die sanfteste Kontaktaufnahme (Alt+Klick in den Listen, Knopf bei den Kontakten)
--   * Wiedersehen: bekannte Spieler sind markiert und stehen oben
--   * Danke-Karte: nach einer Gruppe ein kleines "War schön mit ...?"
--
-- Kurze Nachrichten (nur geflüstert):
--   H;1;b;<beaconID>   ich habe dich wegen deines Beacons angeschrieben
--   W;1                ich winke dir zu

local PREFIX = "SMForever"
local WAVE_LOCK = 60          -- Sek.: einem Spieler höchstens einmal pro Minute zuwinken
local RECV_LOCK = 20          -- Sek.: je Spieler höchstens eine Antwort-Hilfe
local THANKS_MIN = 180        -- Sek.: so lange zusammen in der Gruppe, damit die Danke-Karte kommt
local MAX_CARD = 4

---------------------------------------------------------------------------
-- Kürzel: q = eher ruhig, n = neu im Spiel, h = hilft gern
---------------------------------------------------------------------------
function Social:OwnFlags()
    local s = SM.db and SM.db.social
    if not s then return "" end
    return (s.quiet and "q" or "") .. (s.newbie and "n" or "") .. (s.helper and "h" or "")
end

function Social.ParseFlags(str)
    str = str or ""
    return {
        quiet = str:find("q", 1, true) ~= nil,
        newbie = str:find("n", 1, true) ~= nil,
        helper = str:find("h", 1, true) ~= nil,
    }
end

-- Kürzel für die Listenzeile (farbig, mit Abstand davor) und Zeilen fürs Tooltip
function Social.FlagTags(t)
    local out = ""
    if t.quiet then out = out .. "  " .. SM.Hex("7A4A00") .. "(" .. L.QUIET_SHORT .. ")|r" end
    if t.newbie then out = out .. "  " .. SM.Hex("1F5D7A") .. "(" .. L.NEW_SHORT .. ")|r" end
    if t.helper then out = out .. "  " .. SM.Hex("2F5D1F") .. "(" .. L.HELPER_SHORT .. ")|r" end
    return out
end

function Social.AddFlagLines(t)
    if t.quiet then GameTooltip:AddLine(L.TT_QUIET, 0.9, 0.8, 0.6, true) end
    if t.newbie then GameTooltip:AddLine(L.TT_NEW, 0.6, 0.85, 1, true) end
    if t.helper then GameTooltip:AddLine(L.TT_HELPER, 0.6, 1, 0.6, true) end
end

---------------------------------------------------------------------------
-- Wiedersehen: kennst du den Spieler schon?
---------------------------------------------------------------------------
-- "Kennst du" heißt: ihr seid euch vor mindestens einer halben Stunde schon einmal begegnet.
-- (Wen du gerade eben angeschrieben hast, ist noch kein Wiedersehen.)
local KNOWN_AFTER = 1800

function Social:Known(name)
    if not (SM.Contacts and SM.db and name) then return nil end
    local e = SM.Contacts:Get(name)
    if not e or not e.first then return nil end
    if (time() - e.first) < KNOWN_AFTER then return nil end
    return e
end

function Social.KnownTag(e)
    if not e then return "" end
    return "  " .. SM.Hex("2A6F2A") .. "(" .. L.KNOWN_SHORT .. ")|r"
end

function Social.AddKnownLine(e)
    if not e then return end
    GameTooltip:AddLine(L.TT_KNOWN:format(SM.Contacts.WhenText(e.last), SM.Contacts.SourceText(e)), 0.6, 1, 0.6, true)
    if (e.together or 0) > 0 then GameTooltip:AddLine(L.TT_TOGETHER:format(e.together), 0.6, 1, 0.6) end
end

---------------------------------------------------------------------------
-- Senden: Begrüßungs-Hinweis und Winken
---------------------------------------------------------------------------
Social.waveLock = {}

function Social:SendHello(target, what, id)
    if not (SM.Beacon and target) then return end
    SM.Beacon:Whisper(target, ("H;1;%s;%s"):format(what, tostring(id)))
end

-- Winkt einem Spieler zu (über das Addon, also auch über Entfernung). Gibt true/false und Text zurück.
function Social:Wave(name, target)
    if not name or name == "" then return false, L.WAVE_FAIL end
    if not SM:Active() then return false, L.WAVE_FAIL end
    local now = GetTime()
    local last = self.waveLock[name]
    if last and (now - last) < WAVE_LOCK and not SM:IsTestMode() then return false, L.WAVE_WAIT:format(name) end
    if not SM.Beacon:Whisper(target or name, "W;1") then return false, L.WAVE_FAIL end
    self.waveLock[name] = now
    if SM.Contacts then SM.Contacts:Add(target or name, "wave") end
    return true, L.WAVE_SENT:format(name)
end

---------------------------------------------------------------------------
-- Antwort-Hilfe (Empfang)
---------------------------------------------------------------------------
Social.recvLast = {}

local function Whisper(text, target)
    SM:SendChat(text, "WHISPER", target)
end

-- Antwort-Zettel (test8b, UI\Note.lua): bleibt stehen, bis du ihn wegklickst - niemand soll ins
-- Leere winken. Jeder Absender bekommt seinen eigenen Zettel (sie stellen sich an).
local REPLY_ICON = "Interface\\Icons\\INV_Misc_Note_01"
function Social:AskReply(short, msg, opts)
    return SM.Note:Ask("reply:" .. tostring(short), msg, opts,
        { learn = "reply", sticky = true, hint = L.REPLY_HINT, sound = true, icon = REPLY_ICON, chat = (msg:gsub("\n", " ")) })
end

-- Sofort zeigen (Probe, Tests). options = { { label, action }, ... } (höchstens 4)
function Social:ShowReply(text, options)
    return SM.Note:Push({ key = "reply", learn = "reply", text = text, buttons = options, sticky = true,
                          hint = L.REPLY_HINT, sound = true, icon = REPLY_ICON })
end

-- Die üblichen Antworten auf eine Begrüßung
function Social:ReplyOptions(short, target, invite)
    return {
        { invite and L.REPLY_YES_INVITE or L.REPLY_YES, function()
            Whisper(L.REPLY_YES_TEXT, target)
            if invite then SM.Beacon:InviteName(target) end
        end },
        { L.REPLY_LATER, function() Whisper(L.REPLY_LATER_TEXT, target) end },
        { L.REPLY_NO, function() Whisper(L.REPLY_NO_TEXT, target) end },
        { L.REPLY_SELF, function() SM.Beacon:OpenWhisper(target) end },
    }
end

function Social:HandleMessage(text, dist, sender)
    if dist ~= "WHISPER" or SM:IsDND() or not SM:Active() then return end
    local short = (sender:match("^([^-]+)")) or sender
    if short == UnitName("player") or SM.Beacon:IsIgnored(short) or SM.Guard:IsBlocked(short) then return end
    local kind = text:sub(1, 1)
    if kind ~= "H" and kind ~= "W" then return end
    local now = GetTime()
    -- je Spieler höchstens alle 20 Sek. ein Fenster (gegen Spam). Im Testmodus und für die
    -- Probe-Spieler nicht, sonst geht beim Ausprobieren das zweite Fenster nicht mehr auf.
    local free = SM:IsTestMode() or SM:IsProbeName(short)
    if not free and self.recvLast[short] and (now - self.recvLast[short]) < RECV_LOCK then return end

    if kind == "W" then
        if text ~= "W;1" then return end
        self.recvLast[short] = now
        local known = self:Known(short)
        local msg = L.REPLY_WAVED:format(short)
        if known then msg = msg .. "\n" .. L.REPLY_KNOWN:format(SM.Contacts.WhenText(known.last)) end
        if SM.Contacts then SM.Contacts:Add(sender, "wave") end
        local opts = {
            { L.REPLY_WAVE_BACK, function() Social:Wave(short, sender) end },
            { L.REPLY_SAY_HI, function() Whisper(L.REPLY_HI_TEXT, sender) end },
            { L.REPLY_SELF, function() SM.Beacon:OpenWhisper(sender) end },
        }
        Social:AskReply(short, msg, opts)
        return
    end

    local id = text:match("^H;1;b;(%d+)$")
    if not id then return end
    local b = SM.Beacon:FindOwn(id)
    if not b then return end
    local msg, source, note = L.REPLY_BEACON:format(short, b.title), "beacon", b.title
    self.recvLast[short] = now
    local known = self:Known(short)
    if known then msg = msg .. "\n" .. L.REPLY_KNOWN:format(SM.Contacts.WhenText(known.last)) end
    if SM.Contacts then SM.Contacts:Add(sender, source, note) end
    local opts = self:ReplyOptions(short, sender, true)
    Social:AskReply(short, msg, opts)
end

---------------------------------------------------------------------------
-- Danke-Karte nach einer Gruppe
---------------------------------------------------------------------------
Social.groupSince = {}   -- Name -> { since = GetTime(), full = "Name-Realm" }
Social.wasInGroup = false

local function GroupMembers()
    local list = {}
    for i = 1, 4 do
        local name, realm = UnitName("party" .. i)
        if type(name) == "string" and name ~= "" and name ~= UNKNOWNOBJECT and name ~= UnitName("player") then
            list[#list + 1] = { name = name, full = (realm and realm ~= "") and (name .. "-" .. realm) or name }
        end
    end
    return list
end

function Social:TrackGroup()
    if not SM:Active() then return end
    -- Nur kleine Gruppen: in einem Schlachtzug gibt es keine Danke-Karte.
    if type(IsInRaid) == "function" and IsInRaid() then
        self.groupSince = {}
        self.wasInGroup = false
        return
    end
    local inGroup = (type(IsInGroup) == "function" and IsInGroup()) or false
    local now = GetTime()
    if inGroup then
        local present = {}
        for _, m in ipairs(GroupMembers()) do
            present[m.name] = true
            local g = self.groupSince[m.name]
            if not g then
                self.groupSince[m.name] = { since = now, full = m.full }
            else
                g.left = nil -- wieder da
            end
        end
        -- Wer schon gegangen ist, behält seine Zeit (für die Karte am Ende)
        for name, g in pairs(self.groupSince) do
            if not present[name] and not g.left then g.left = now end
        end
        self.wasInGroup = true
        return
    end
    if self.wasInGroup then
        self.wasInGroup = false
        local stayed = {}
        for name, g in pairs(self.groupSince) do
            if ((g.left or now) - g.since) >= THANKS_MIN then stayed[#stayed + 1] = { name = name, full = g.full } end
        end
        self.groupSince = {}
        table.sort(stayed, function(a, b) return a.name < b.name end)
        -- Wiedersehen: gemeinsame Gruppen bei bekannten Kontakten mitzählen
        for _, m in ipairs(stayed) do
            local e = self:Known(m.name)
            if e then e.together = (e.together or 0) + 1 end
        end
        -- test8b: keine Danke-Karte mehr - wer länger dabei war, landet von selbst in den Kontakten,
        -- dazu eine Chatzeile (Danke sagen, Freund, Zuwinken gehen dort mit Rechtsklick)
        for _, m in ipairs(stayed) do
            if SM.Contacts then SM.Contacts:Add(m.full or m.name, "group") end
        end
        if #stayed > 0 and SM.db.social.thanksCard and not SM:IsDND() then Social:ShowThanks(stayed) end
    end
end

-- Nach der Gruppe: eine Chatzeile mit den Namen (früher eine Karte mit Knöpfen)
function Social:ShowThanks(members)
    if not SM.db.social.thanksCard or SM:IsDND() then return false end
    local names = {}
    for i, m in ipairs(members or {}) do
        if i > MAX_CARD then break end
        names[#names + 1] = m.name
    end
    if #names == 0 then return false end
    SM:Print(L.THANKS_LINE:format(table.concat(names, ", ")))
    return true
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
SM:RegisterEvent(Social, "CHAT_MSG_ADDON", function(_, prefix, text, dist, sender)
    if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" then return end
    Social:HandleMessage(text, dist, sender)
end)

-- Eigener Besitzer, weil Social.lua dasselbe Ereignis schon für die Schnellsätze nutzt.
local Tracker = {}
local function OnRoster()
    if not SM.db then return end
    Social:TrackGroup()
end
SM:RegisterEvent(Tracker, "GROUP_ROSTER_UPDATE", OnRoster)
SM:RegisterEvent(Tracker, "PARTY_MEMBERS_CHANGED", OnRoster) -- ältere Clients
