local ADDON, SM = ...
local L = SM.L

-- Kontakte: Spieler, mit denen du über das Addon zusammengekommen bist
-- (Beacon angeflüstert/eingeladen, "Ich komme" in beide Richtungen, Instant-Runde, Winken).
-- Gespeichert je Realm in SocializeMeForeverDB.contacts[Realm][Name].
-- Kein abschaltbares Modul: die Liste füllt sich nur durch die anderen Module.
local Contacts = {}
SM.Contacts = Contacts

local MAX_CONTACTS = 100

local function ShortName(name)
    return (name and name:match("^([^-]+)")) or name
end

local function Realm()
    local r = type(GetRealmName) == "function" and GetRealmName() or nil
    return (r and r ~= "") and r or "?"
end

-- Die Liste dieses Realms (wird bei Bedarf angelegt).
function Contacts:Store()
    local all = SM.db.contacts
    local realm = Realm()
    if type(all[realm]) ~= "table" then all[realm] = {} end
    return all[realm]
end

-- Hält die Liste klein: die am längsten nicht gesehenen fliegen zuerst raus.
function Contacts:Prune(store)
    local list = {}
    for _, e in pairs(store) do list[#list + 1] = e end
    if #list <= MAX_CONTACTS then return end
    table.sort(list, function(a, b) return (a.last or 0) < (b.last or 0) end)
    for i = 1, #list - MAX_CONTACTS do store[list[i].name] = nil end
end

-- Merkt sich einen Spieler. source: "beacon", "circle" (Instant), "wave" ...; note: Beacon-Text bzw. Thema.
function Contacts:Add(name, source, note)
    local short = ShortName(name)
    if not short or short == "" then return end
    if short == (UnitName and UnitName("player")) then return end
    local store = self:Store()
    local e = store[short]
    local now = time()
    if not e then
        e = { name = short, full = name, first = now, count = 0 }
        store[short] = e
    end
    e.last, e.source, e.count = now, source or e.source, (e.count or 0) + 1
    if type(note) == "string" and note ~= "" then e.note = note end
    if name:find("-", 1, true) then e.full = name end
    self:Prune(store)
    SM:Fire("CONTACTS_CHANGED")
    return e
end

function Contacts:Get(name)
    return self:Store()[ShortName(name)]
end

-- Alle Kontakte dieses Realms, zuletzt gesehene zuerst.
function Contacts:List()
    local list = {}
    for _, e in pairs(self:Store()) do list[#list + 1] = e end
    table.sort(list, function(a, b)
        if (a.last or 0) ~= (b.last or 0) then return (a.last or 0) > (b.last or 0) end
        return a.name < b.name
    end)
    return list
end

function Contacts:Remove(name)
    local store = self:Store()
    local short = ShortName(name)
    if not store[short] then return false end
    store[short] = nil
    SM:Fire("CONTACTS_CHANGED")
    return true
end

---------------------------------------------------------------------------
-- Aktionen (werden über Knöpfe ausgelöst, also mit echtem Mausklick)
---------------------------------------------------------------------------
local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, res = pcall(fn, ...)
    return ok, res
end

-- Steht der Spieler schon auf deiner Freundesliste?
function Contacts:IsFriend(name)
    local short = ShortName(name)
    if C_FriendList and C_FriendList.GetFriendInfo then
        local ok, info = Call(C_FriendList.GetFriendInfo, short)
        if ok then return info ~= nil end
    end
    local count = 0
    if C_FriendList and C_FriendList.GetNumFriends then
        local ok, n = Call(C_FriendList.GetNumFriends)
        count = ok and n or 0
    elseif type(GetNumFriends) == "function" then
        count = GetNumFriends() or 0
    end
    local byIndex = (C_FriendList and C_FriendList.GetFriendInfoByIndex) or GetFriendInfo
    for i = 1, count do
        local ok, fname = Call(byIndex, i)
        if ok and type(fname) == "table" then fname = fname.name end
        if ok and ShortName(fname) == short then return true end
    end
    return false
end

function Contacts:Whisper(e)
    SM.Beacon:OpenWhisper(e.full or e.name)
    e.last = time()
    return true
end

function Contacts:Invite(e)
    return SM.Beacon:InviteName(e.full or e.name)
end

function Contacts:AddFriend(e)
    local ok = SM:AddFriendName(e.name)
    if ok then e.friend = true; SM:Fire("CONTACTS_CHANGED") end
    return ok
end

-- Ignorieren (die Oberfläche fragt vorher nach). Danach verschwinden seine Beacons und Runden.
function Contacts:Ignore(e)
    local ok = SM:IgnoreName(e.name)
    if not ok then return false end
    if SM.Beacon then SM.Beacon:RemoveBySender(e.name, "ignored") end
    if SM.Circle then SM.Circle:Forget(e.name) end
    self:Remove(e.name)
    return true
end


---------------------------------------------------------------------------
-- Anzeige-Hilfen
---------------------------------------------------------------------------
-- "heute 21:40", "gestern 18:05" oder "28.10." (Format kommt aus den Texten)
function Contacts.WhenText(t)
    if not t then return "" end
    local today = date("%Y%m%d")
    local day = date("%Y%m%d", t)
    if day == today then return L.WHEN_TODAY:format(date("%H:%M", t)) end
    if day == date("%Y%m%d", time() - 86400) then return L.WHEN_YESTERDAY:format(date("%H:%M", t)) end
    return date(L.WHEN_DATE, t)
end

function Contacts.SourceText(e)
    local src = L["SRC_" .. (e.source or "beacon")]
    if e.note and e.note ~= "" then return src .. ": " .. e.note end
    return src
end
