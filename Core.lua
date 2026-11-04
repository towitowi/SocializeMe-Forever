-- SocializeMe Forever - Lizenz: siehe LICENSE.txt (eigene Änderungen für dich ja,
-- veränderte Versionen weitergeben nur mit Erlaubnis des Autors).
local ADDON, SM = ...
-- Eindeutiger globaler Name (das alte SocializeMe 1.x nutzte andere Namen; so kommt sich nichts in die Quere).
_G.SocializeMeForever = SM

local L = SM.L
local pairs, ipairs, type, pcall, select, tostring = pairs, ipairs, type, pcall, select, tostring

SM.COLOR = "|cffE5A65D"

-- Entwickler-Werkzeuge (Probe-Modus, Testmodus ohne Wartezeiten) gibt es nur mit dem privaten
-- Zusatz-Addon "SocializeMeForever_Dev" des Autors. Es setzt SM.DEV beim Laden auf true.
-- Ohne dieses Zusatz-Addon gelten alle Wartezeiten und Schutzregeln immer.
SM.DEV = false
SM.modules = {}      -- name -> module
SM.moduleOrder = {}  -- Ladereihenfolge

---------------------------------------------------------------------------
-- Standardwerte (Defaults). Alles hier ist im Einstellungsfenster änderbar.
-- Fehlende Schlüssel werden bei jedem Start automatisch ergänzt.
---------------------------------------------------------------------------
SM.defaults = {
    silentMode = false,      -- "Sei leise!": Sounds und Musik
    dnd = false,             -- "Nicht stören": keine Beacons senden/empfangen
    testMode = false,        -- nur im Dev-Build: keine Wartezeit zwischen Beacons
    debug = false,
    activeTab = "beacons",
    modules = {
        beacon = true,
        eta = true,
        pins = true,
        chill = true,
        lore = true,
    },
    beacon = {
        ttl = 30,            -- Minuten, die ein Beacon sichtbar bleibt
        cooldown = 60,       -- Sekunden zwischen eigenen Beacons
        maxPerPlayer = 3,    -- max. aktive Beacons pro Spieler
        useChannel = true,   -- versteckten Channel nutzen
        useGuild = true,     -- zusätzlich an die Gilde senden
        useParty = true,     -- zusätzlich an Gruppe/Schlachtzug senden
        notify = true,       -- Chat-Hinweis bei neuen Beacons anderer Spieler
        notifyZone = true,   -- Chat-Hinweis nur für Beacons in meiner Zone
        zoneFilter = "own",  -- Liste: "own" = nur meine Zone, "all" = alle Zonen
    },
    circle = {
        mode = "t",          -- SocializeMe Instant: "t" = Text (Gruppenchat), "v" = Voice (Sprachchat der Gruppe)
        topic = 1,           -- gewähltes Thema (1 = "Einfach plaudern", passt zu jeder Runde)
        notify = false,      -- Chatzeile, wenn eine neue Runde aufgeht
        travel = false,      -- Reise-Plauderei: beim Abflug eine Chatzeile mit Instant-Angebot
        via = "wow",         -- Sprachchat-Runden: "wow" (im Spiel eingebaut) oder "discord"
        -- discord = "<code>"   Einladung für eigene Discord-Runden (nur der Code von discord.gg/..., test8b)
    },
    contacts = {},           -- je Realm: Name -> { name, full, first, last, source, note, count }
    nav = {
        arrow = true,        -- Wegweiser-Pfeil anzeigen
        arrowScale = 100,    -- Größe des Pfeils in Prozent
        waypoint = true,     -- Wegpunkt auf der Karte des Spiels (und in TomTom) setzen
    },
    pins = {
        world = true,        -- Beacons auf der Weltkarte
        minimap = true,      -- Beacons auf der Minimap
        -- Filter für Karte UND Chat-Hinweise (eigene Beacons sieht man immer)
        kinds = { quest = true, campfire = true },
        logOnly = false,     -- Quest-Beacons nur, wenn die Quest in meinem Questlog ist
    },
    lore = {
        interval = 5,        -- Minuten zwischen Lore-Häppchen pro Zone
        onZone = true,       -- beim Betreten einer Zone: Willkommen + Häppchen im Chat
    },
    music = {
        mode = "auto",       -- "click" = nur wenn ich klicke, "auto" = einmal pro Sitzung anbieten (nie von selbst)
        source = "camp",     -- Musik-Quelle: "camp" (mitgeliefert), "tavern" (Gasthaus aus WoW), "own"
        onFishing = true,    -- Musik beim Angeln
        onSpot = true,       -- Musik an Aussichtspunkten
        onCampfire = true,   -- Musik, wenn ich mich ans Lagerfeuer setze (WoW Forever)
        waitTip = true,      -- Warte-Tipp nach dem eigenen Beacon
        player = true,       -- kleinen Player zeigen
        own = {},            -- gefundene eigene Lieder (Dateinamen)
    },
    spots = {},              -- Aussichtspunkte: { name, mapID, x, y, c = Art }
    places = {},             -- je Realm: geteilte Orte und wichtige Punkte (Tab Orte)
    peon = false,            -- Peon-Sprüche als Ton (nur Töne aus dem Spiel); die Einrichtung fragt danach
    social = {
        quiet = false,       -- Kürzel "eher ruhig" bei eigenen Beacons
        greeting = 1,        -- Begrüßung: 1 = freundlich, 2 = eher ruhig, 3 = kurz
        quickbar = true,     -- Schnellsätze in der Gruppe zeigen
        newbie = false,      -- Kürzel "neu im Spiel"
        helper = false,      -- Kürzel "hilft gern" (erklärt Neuen gern etwas)
        thanksCard = true,   -- nach einer Gruppe: "War schön mit ...?"
        funSounds = true,    -- Spaß-Töne in der Gruppe hören (und selbst spielen)
        soundTimes = {},     -- Zeiten der eigenen Spaß-Töne (für die Pause, auch nach /reload)
    },
    consent = {},            -- je Charakter ("Name-Realm"): { v = Regel-Version, t = Zeit }
    guard = {},              -- je Realm: Troll-Schutz (gesehene Addon-Nutzer, Meldungen, Sperren)
    ear = {},                -- "Ein offenes Ohr": nur die Position der Karte
    tipPos = {},             -- Position der Warte-Karte (falls verschoben)
    note = {},               -- Position des Zettels (nur, wenn du ihn verschoben hast)
    musicMini = {},          -- Position der Musikzeile (nur, wenn du sie verschoben hast)
    improve = true,          -- beim Verbessern helfen: Messungen und Feedback senden (abschaltbar)
    placeFix = {},           -- gemeinsames Nachmessen der Orte (Modules\PlaceFix.lua)
    feedback = {},           -- gesammeltes Feedback (Modules\Feedback.lua)
    window = { scale = 85 }, -- Fenstergröße in Prozent; Position wird zusätzlich gespeichert
    ui = {
        learned = {},        -- Fenster, die du immer gleich zumachst: kommen nur noch als Chatzeile
        quickClose = {},     -- je Fenster: so oft hintereinander gleich wieder zugemacht
        sounds = true,       -- kurze Hinweis-Töne (z. B. wenn jemand kommt oder dir schreibt)
        calm = true,         -- im Kampf und in Instanzen: keine Fenster, keine Musik von selbst
        locked = false,      -- Fenster festsetzen (nicht mehr verschiebbar)
        setupDone = false,   -- Einrichtung beim ersten Start erledigt
        tipsSeen = {},       -- Erst-Tipps je Tab schon gelesen ("Verstanden")
        moreOpen = false,    -- Optionen: Bereich "Mehr" aufgeklappt
        settingsCat = "general", -- zuletzt geöffnete Kategorie der Einstellungen
        mapHintUses = 0,     -- so oft Alt+Klick auf der Weltkarte benutzt (ab 3 kein Hinweis mehr)
        skin = "parchment",  -- Farbsatz aller Fenster (Media\Textures.lua, gilt nach Neu laden)
        hideTabs = {},       -- Einfach-Ansicht: ausgeblendete Tabs (neue Spieler: Orte und Kontakte)
        opacity = 100,       -- Hintergründe: 50-100 % deckend
    },
    language = "auto",       -- "auto" = Sprache des Spiels, sonst "deDE", "enUS" oder "zhCN"
    minimap = { pos = 45, hide = false, offset = 5 }, -- offset: Abstand der Button-Mitte zum Minimap-Rand
    volume = {
        music = 0.6,
        campfire = 0.5,
        alerts = 0.8,
    },
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

---------------------------------------------------------------------------
-- Ausgabe & Debug
---------------------------------------------------------------------------
function SM:Print(msg)
    print(self.COLOR .. "SocializeMe Forever:|r " .. tostring(msg))
end

function SM:Debug(...)
    if not (self.db and self.db.debug) then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    print("|cff888888[SM debug]|r " .. table.concat(parts, " "))
end

-- Fehler in Callbacks/Modulen sollen das Addon nie komplett lahmlegen.
local function SafeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        print("|cffff4444[SocializeMe Error]|r " .. tostring(err))
        -- für das Entwickler-Feedback merken (Modules\Feedback.lua)
        if SM.Feedback and SM.Feedback.NoteError then pcall(SM.Feedback.NoteError, SM.Feedback, err) end
    end
    return ok
end
SM.SafeCall = SafeCall

---------------------------------------------------------------------------
-- Einfache interne Callbacks (z. B. SILENT_CHANGED, DND_CHANGED, BEACON_ADDED)
---------------------------------------------------------------------------
SM.callbacks = {}

function SM:RegisterCallback(name, fn)
    local list = self.callbacks[name]
    if not list then list = {}; self.callbacks[name] = list end
    list[#list + 1] = fn
end

function SM:Fire(name, ...)
    local list = self.callbacks[name]
    if not list then return end
    for i = 1, #list do SafeCall(list[i], ...) end
end

---------------------------------------------------------------------------
-- Events: SM:RegisterEvent(owner, "EVENT", function(event, ...) end)
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}  -- event -> { owner -> fn }

local function Dispatch(event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in pairs(list) do SafeCall(fn, event, ...) end
end
eventFrame:SetScript("OnEvent", function(_, event, ...) Dispatch(event, ...) end)

-- Ein Ereignis so auslösen, als käme es vom Spiel (für den Probe-Modus im Dev-Build).
function SM:Dispatch(event, ...)
    Dispatch(event, ...)
end

function SM:RegisterEvent(owner, event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        -- Unbekannte Ereignisse (gibt es nicht auf jedem Client) dürfen nichts abbrechen.
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
            SM:Debug("event not available on this client:", event)
        end
    end
    list[owner] = fn
end

function SM:UnregisterAllEvents(owner)
    for event, list in pairs(handlers) do
        list[owner] = nil
        if next(list) == nil then
            handlers[event] = nil
            eventFrame:UnregisterEvent(event)
        end
    end
end

---------------------------------------------------------------------------
-- Module. Ein Modul darf OnEnable() und OnDisable() definieren.
---------------------------------------------------------------------------
function SM:NewModule(name)
    local mod = { name = name, enabled = false }
    self.modules[name] = mod
    self.moduleOrder[#self.moduleOrder + 1] = name
    local field = (name:gsub("^%l", string.upper))
    self[field] = mod
    return mod
end

function SM:IsModuleEnabled(name)
    return self.db and self.db.modules[name] and true or false
end

local function EnableModule(mod)
    if mod.enabled then return end
    mod.enabled = true
    if mod.OnEnable then SafeCall(mod.OnEnable, mod) end
end

local function DisableModule(mod)
    if not mod.enabled then return end
    mod.enabled = false
    SM:UnregisterAllEvents(mod)
    if mod.OnDisable then SafeCall(mod.OnDisable, mod) end
end

-- Alle eingeschalteten Module starten bzw. anhalten (Regeln bestätigt / gesperrt).
function SM:StartModules()
    for _, name in ipairs(self.moduleOrder) do
        if self.db.modules[name] ~= false then EnableModule(self.modules[name]) end
    end
end

function SM:StopModules()
    for _, name in ipairs(self.moduleOrder) do DisableModule(self.modules[name]) end
end

-- Darf das Addon gerade arbeiten? (Regeln bestätigt und nicht wegen Meldungen gesperrt)
function SM:Active()
    if not self.db then return false end
    if self.Rules and not self.Rules:Accepted() then return false end
    if self.Guard and self.Guard:SelfBlocked() then return false end
    return true
end

function SM:SetModuleEnabled(name, state)
    local mod = self.modules[name]
    if self.db then self.db.modules[name] = state and true or false end
    if not mod then return end
    if state and self:Active() then EnableModule(mod) elseif not state then DisableModule(mod) end
end

---------------------------------------------------------------------------
-- Alles, was an andere Spieler geht (Flüstern, Einladen, Freund, Ignorieren), läuft hier durch.
-- Im Probe-Modus (nur Dev-Build) landen Aktionen für Probe-Spieler ("Test...") nur im Chatfenster.
---------------------------------------------------------------------------
function SM:IsProbeName(name)
    return self.Probe and self.Probe.on and type(name) == "string" and name:match("^Test%a") ~= nil or false
end

function SM:SendChat(text, chatType, target)
    if chatType == "WHISPER" and self:IsProbeName(target) then
        self.Probe:Log(("-> %s: %s"):format(target, text))
        return true
    end
    local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not fn then return false end
    return (pcall(fn, text, chatType, nil, target))
end

-- Text auf höchstens n Zeichen kürzen, ohne ein Umlaut- oder Chinesisch-Zeichen zu zerschneiden
-- (in UTF-8 hat ein Zeichen 1 bis 4 Bytes)
function SM.TrimChars(text, n)
    local out, count = {}, 0
    for ch in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
        if count > n then break end
        out[#out + 1] = ch
    end
    return table.concat(out)
end

function SM:InvitePlayer(name)
    if self:IsProbeName(name) then self.Probe:Log("invite " .. name) return true end
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if not fn then return false end
    return (pcall(fn, name))
end

function SM:AddFriendName(name)
    if self:IsProbeName(name) then self.Probe:Log("friend " .. name) return true end
    local fn = (C_FriendList and C_FriendList.AddFriend) or AddFriend
    if not fn then return false end
    return (pcall(fn, name))
end

function SM:IgnoreName(name)
    if self:IsProbeName(name) then self.Probe:Log("ignore " .. name) return true end
    local fn = (C_FriendList and C_FriendList.AddIgnore) or AddIgnore
    if not fn then return false end
    return (pcall(fn, name))
end

---------------------------------------------------------------------------
-- "Sei leise!" (nur Sounds und Musik) und "Nicht stören" (keine Beacons).
-- Beides ist getrennt; andere Module hören auf SILENT_CHANGED / DND_CHANGED.
---------------------------------------------------------------------------
function SM:IsSilent()
    return self.db and self.db.silentMode or false
end

function SM:SetSilent(state)
    state = state and true or false
    if self.db.silentMode == state then return end
    self.db.silentMode = state
    self:Print(state and L.SILENT_ON or L.SILENT_OFF)
    self:Fire("SILENT_CHANGED", state)
end

---------------------------------------------------------------------------
-- WoW Forever oder Classic?
-- Ein paar Extras gibt es nur in WoW Forever (am Lagerfeuer sitzen, die mitgelieferten Orte
-- mit Foto-Tipps). In Classic sind sie ausgegraut, mit dem Hinweis "Nur in WoW Forever".
-- Erkannt wird Forever an der Projekt-Kennung des Spiels; zur Sicherheit zählt auch die
-- Interface-Nummer 1.60.x (16000 bis 19999). Nur mit dem Dev-Zusatz lässt sich das zum Testen
-- umschalten: db.devForever = true (wie Forever), false (wie Classic), nil (echte Erkennung).
---------------------------------------------------------------------------
function SM.DetectForever()
    if WOW_PROJECT_ID ~= nil and WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT then return true end
    local toc = type(GetBuildInfo) == "function" and tonumber((select(4, GetBuildInfo()))) or nil
    return (toc ~= nil and toc >= 16000 and toc < 20000) and true or false
end
SM.FOREVER = SM.DetectForever()

function SM:IsForever()
    if self.DEV and self.db and self.db.devForever ~= nil then return self.db.devForever and true or false end
    return self.FOREVER
end

-- Nur Dev-Zusatz: Forever nachspielen (true), Classic nachspielen (false) oder echt (nil)
function SM:SetForeverSim(state)
    if not self.DEV then return end
    self.db.devForever = state
    self:Fire("FOREVER_CHANGED", self:IsForever())
end

-- Testmodus gibt es nur im Dev-Build (SM.DEV).
function SM:IsTestMode()
    return (self.DEV and self.db and self.db.testMode) and true or false
end

function SM:SetTestMode(state)
    if not self.DEV then return end
    state = state and true or false
    if self.db.testMode == state then return end
    self.db.testMode = state
    self:Print(state and L.TEST_ON or L.TEST_OFF)
    self:Fire("TEST_CHANGED", state)
end

-- Beim Verbessern helfen (Einstellungen > Allgemein): aus = es geht kein Feedback und keine
-- Messung raus. Was andere gemessen haben, nutzt das Addon trotzdem.
function SM:HelpImprove()
    return not (self.db and self.db.improve == false)
end

function SM:IsDND()
    return self.db and self.db.dnd or false
end

-- minutes: nil = bis ich es ausschalte, Zahl = so viele Minuten, "logout" = bis zum Ausloggen
function SM:SetDND(state, minutes)
    state = state and true or false
    local db = self.db
    db.dndUntil, db.dndSession = nil, nil
    if state and type(minutes) == "number" and minutes > 0 then
        db.dndUntil = time() + math.floor(minutes * 60)
    elseif state and minutes == "logout" then
        db.dndSession = true
    end
    if db.dnd == state then
        if state and (db.dndUntil or db.dndSession) then self:Print(self:DNDText()) end
        return
    end
    db.dnd = state
    self:Print(state and self:DNDText() or L.DND_OFF_MSG)
    self:Fire("DND_CHANGED", state)
end

function SM:DNDText()
    local db = self.db
    if db.dndUntil then return L.DND_ON_UNTIL:format(date("%H:%M", db.dndUntil)) end
    if db.dndSession then return L.DND_ON_LOGOUT end
    return L.DND_ON_MSG
end

-- Zeitlich begrenztes "Nicht stören" läuft von selbst ab.
function SM:CheckDND()
    local db = self.db
    if db and db.dnd and db.dndUntil and time() >= db.dndUntil then self:SetDND(false) end
end

---------------------------------------------------------------------------
-- Ruhe: im Kampf und in Instanzen geht nichts von selbst auf und keine Musik startet.
---------------------------------------------------------------------------
function SM:Calm()
    if not (self.db and self.db.ui.calm) then return false end
    if InCombatLockdown and InCombatLockdown() then return true end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return true end
    if IsInInstance then
        local inside, kind = IsInInstance()
        if inside and kind ~= "none" then return true end
    end
    return false
end

-- Fenster, die von selbst aufgehen (Antwort-Hilfe, Danke-Karte, Warte-Tipp ...), laufen hier durch.
-- Das Addon lernt mit: Machst du ein Fenster dreimal hintereinander gleich wieder zu (innerhalb
-- von 5 Sekunden, ohne einen Knopf darin zu benutzen), kommt es ab dann nur noch als Chatzeile.
-- /sm fenster holt alle Fenster zurück. Nichts wird still verschluckt: ohne Fenster gibt es
-- immer die Chatzeile, /sm antwort öffnet das zuletzt nur gemeldete Fenster doch noch.
-- Im Kampf / in der Instanz: das Fenster wartet und kommt danach.
SM.pendingPopups = {}
local LEARN_SECONDS, LEARN_TIMES = 5, 3

function SM:PopupLearned(key)
    local l = self.db and self.db.ui.learned
    return l and l[key] and true or false
end

-- Fenster beobachten: Zugemacht ohne Knopf und schnell = weggeklickt. Jeder Knopf darin
-- (außer dem X) zählt als "benutzt" - dann fängt das Zählen von vorn an.
function SM:WatchPopup(key, f)
    if not f then return end
    if not f.smWatched then
        f.smWatched = true
        f:HookScript("OnHide", function(fr) SM:PopupHidden(fr) end)
    end
    local kids = f.GetChildren and { f:GetChildren() } or {}
    for _, c in ipairs(kids) do
        if not c.smHooked and c.HookScript and not c.isClose and c.GetObjectType and c:GetObjectType() == "Button" then
            c.smHooked = true
            -- beim Drücken (vor dem Klick, der das Fenster vielleicht schon schließt)
            c:HookScript("OnMouseDown", function() f.smUsed = true end)
        end
    end
    f.smKey, f.smShownAt, f.smUsed = key, GetTime(), false
end

function SM:PopupHidden(f)
    local key = f.smKey
    if not (key and self.db) then return end
    f.smKey = nil
    local ui = self.db.ui
    if f.smUsed or GetTime() - (f.smShownAt or 0) > LEARN_SECONDS then
        ui.quickClose[key] = nil -- gelesen oder benutzt: von vorn zählen
        return
    end
    local n = (ui.quickClose[key] or 0) + 1
    ui.quickClose[key] = n
    if n >= LEARN_TIMES then
        ui.learned[key], ui.quickClose[key] = true, nil
        self:Print(L.POPUP_LEARNED)
    end
end

-- /sm fenster: alle Fenster kommen wieder von selbst
function SM:ResetLearned()
    if not self.db then return 0 end
    local n = 0
    for _ in pairs(self.db.ui.learned) do n = n + 1 end
    self.db.ui.learned, self.db.ui.quickClose = {}, {}
    return n
end

-- Kurze Hinweis-Töne (Einstellung "Hinweis-Töne")
function SM:SoundsOn()
    return not (self.db and (self.db.ui.sounds == false or self.db.silentMode))
end

-- frame: das Fenster (oder eine Funktion, die es liefert) - zum Mitlernen
function SM:Popup(key, show, chatLine, frame)
    if self:PopupLearned(key) then
        self:Print((chatLine or L.POPUP_CHAT_DEFAULT) .. "  " .. L.POPUP_OPEN_HINT)
        self.lastPopup = show
        return false
    end
    local function run()
        show()
        local f = type(frame) == "function" and frame() or frame
        if f then self:WatchPopup(key, f) end
    end
    if self:Calm() then
        self.pendingPopups[key] = run
        return false
    end
    run()
    return true
end

function SM:FlushPopups()
    if self:Calm() then return end
    local list = self.pendingPopups
    self.pendingPopups = {}
    for _, show in pairs(list) do SafeCall(show) end
end

---------------------------------------------------------------------------
-- Musik: "off" (nie), "click" (nur wenn ich klicke), "auto" (anbieten - der kleine Zettel, test8b)
---------------------------------------------------------------------------
function SM:MusicMode()
    local m = self.db and self.db.music.mode
    if m == "off" or m == "click" then return m end
    return "auto"
end

-- Darf Musik laufen? auto = true, wenn sie von selbst starten würde.
function SM:MusicAllowed(auto)
    if self:IsSilent() then return false end
    local m = self:MusicMode()
    if m == "off" then return false end
    if auto then return m == "auto" and not self:Calm() end
    return true
end

---------------------------------------------------------------------------
-- Fensterpositionen: jedes verschiebbare Fenster meldet sich hier an, damit
-- "Fensterpositionen zurücksetzen" alles wieder an seinen Platz bringt.
---------------------------------------------------------------------------
SM.positionHolders = {}
function SM:RegisterPosition(getStore, getFrame, anchor)
    self.positionHolders[#self.positionHolders + 1] = { store = getStore, frame = getFrame, anchor = anchor }
end

function SM:ResetPositions()
    for _, h in ipairs(self.positionHolders) do
        local t = h.store()
        if t then t.point, t.relPoint, t.x, t.y = nil, nil, nil, nil end
        local f = h.frame()
        if f then f:ClearAllPoints(); h.anchor(f) end
    end
    self.db.minimap.pos = 45
    if self.MinimapButton then self.MinimapButton:UpdatePosition() end
    self:Print(L.POSITIONS_RESET)
end

-- Alle Einstellungen auf Anfang. Regeln, Troll-Schutz, Kontakte und eigene Orte bleiben -
-- sonst könnte man so eine Sperre loswerden.
local KEEP_ON_RESET = { consent = true, guard = true, ear = true, contacts = true, spots = true }
function SM:ResetSettings()
    local db = self.db
    for k in pairs(db) do
        if not KEEP_ON_RESET[k] then db[k] = nil end
    end
    CopyDefaults(self.defaults, db)
    db.ui.setupDone = true
end

---------------------------------------------------------------------------
-- Slash-Befehle: SM:RegisterCommand("name", fn, "alias1", "alias2")
---------------------------------------------------------------------------
local commands = {}

function SM:RegisterCommand(name, fn, ...)
    commands[name] = fn
    for i = 1, select("#", ...) do
        commands[(select(i, ...))] = fn
    end
end

-- Die Hilfe zeigt nur die Befehle, die man wirklich braucht - alles andere steht im Fenster.
local HELP_KEYS = { "HELP_WINDOW", "HELP_OPTIONS", "HELP_MUSIC", "HELP_PLACES", "HELP_LORE", "HELP_INSTANT",
                    "HELP_VOICE", "HELP_EAR", "HELP_DND", "HELP_SOUNDS", "HELP_REPORT", "HELP_RULES", "HELP_REPLY" }

local function PrintHelp()
    SM:Print(L.HELP_HEADER)
    for _, key in ipairs(HELP_KEYS) do print("  " .. L[key]) end
    if SM.DEV then -- nur mit dem privaten Dev-Zusatz
        for _, key in ipairs({ "HELP_TEST", "HELP_PROBE", "HELP_PINS", "HELP_DEVCMDS" }) do
            if rawget(L, key) then print("  " .. L[key]) end
        end
    end
end

SM:RegisterCommand("hilfe", PrintHelp, "help", "?")
-- /sm optionen: das Fenster gleich auf den Einstellungen öffnen
SM:RegisterCommand("optionen", function()
    if SM.Window then SM.Window:OpenTab("settings") end
end, "options", "settings", "einstellungen")
-- /sm antwort: das zuletzt nur im Chat gemeldete Fenster doch noch öffnen
SM:RegisterCommand("fenster", function()
    SM:ResetLearned()
    SM:Print(L.POPUP_RESET)
end, "windows")
SM:RegisterCommand("antwort", function()
    if SM.lastPopup then SafeCall(SM.lastPopup) else SM:Print(L.POPUP_NONE) end
end, "reply")

-- /sm dnd = an/aus, /sm dnd 30 = 30 Minuten, /sm dnd logout = bis zum Ausloggen
SM:RegisterCommand("dnd", function(rest)
    rest = (rest or ""):lower()
    local mins = tonumber(rest)
    if mins then SM:SetDND(true, mins)
    elseif rest == "logout" or rest == "ausloggen" then SM:SetDND(true, "logout")
    else SM:SetDND(not SM:IsDND()) end
end)

-- /sm ist kurz, aber auch andere Addons könnten es benutzen. /smf funktioniert immer.
SLASH_SOCIALIZEMEFOREVER1 = "/sm"
SLASH_SOCIALIZEMEFOREVER2 = "/smf"
SLASH_SOCIALIZEMEFOREVER3 = "/socializeme"
SlashCmdList["SOCIALIZEMEFOREVER"] = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" then
        if SM.Window then SM.Window:Toggle() else PrintHelp() end
        return
    end
    local fn = commands[cmd]
    if fn then
        SafeCall(fn, rest)
    else
        SM:Print(L.UNKNOWN_CMD)
    end
end

---------------------------------------------------------------------------
-- Tastenbelegungen (Bindings.xml): Hauptmenü > Tastaturbelegung > AddOns
---------------------------------------------------------------------------
local function BindingNames()
    _G.BINDING_HEADER_SOCIALIZEMEFOREVER = "SocializeMe Forever"
    _G.BINDING_NAME_SOCIALIZEMEFOREVER_TOGGLE = L.BIND_TOGGLE
    _G.BINDING_NAME_SOCIALIZEMEFOREVER_BEACON = L.BIND_BEACON
    _G.BINDING_NAME_SOCIALIZEMEFOREVER_WAVE = L.BIND_WAVE
    _G.BINDING_NAME_SOCIALIZEMEFOREVER_STOP = L.BIND_STOP
    _G.BINDING_NAME_SOCIALIZEMEFOREVER_MUSIC = L.BIND_MUSIC
    _G.BINDING_NAME_SOCIALIZEMEFOREVER_EAR = L.BIND_EAR
    _G.BINDING_NAME_SOCIALIZEMEFOREVER_CIRCLE = L.BIND_CIRCLE
end
BindingNames()

function SM:Bind(what)
    if what == "toggle" then
        if self.Window then self.Window:Toggle() end
    elseif what == "beacon" then
        if self.Window then self.Window:OpenBeaconForm() end
    elseif what == "wave" then
        -- dem anvisierten Spieler zuwinken
        if not (UnitIsPlayer and UnitIsPlayer("target")) then self:Print(L.BIND_WAVE_NOTARGET) return end
        local name, realm = UnitName("target")
        local full = (realm and realm ~= "") and (name .. "-" .. realm) or name
        local _, msg = self.Social:Wave(name, full)
        self:Print(msg)
    elseif what == "stop" then
        if self.Eta then self.Eta:Stop() end
    elseif what == "music" then
        if self.Chill then
            local _, msg = self.Chill:Toggle()
            self:Print(msg)
        end
    elseif what == "ear" then
        if self.EarUI then self.EarUI:Toggle() end
    elseif what == "circle" then
        if self.Window then self.Window:OpenTab("instant") end
    end
end

-- Daten aus Testversionen aufräumen, deren Funktionen es nicht mehr gibt
-- (Radar, Stadtführer, Berufe-Tafel, Zuhörer-Netzwerk des offenen Ohrs)
function SM.Tidy(db)
    if type(db.ear) == "table" then db.ear.listener, db.ear.chars, db.ear.net = nil, nil, nil end
    if type(db.modules) == "table" then
        for _, m in ipairs({ "radar", "city", "community", "ear" }) do db.modules[m] = nil end
    end
    db.radar, db.city = nil, nil
    -- Diese Werte haben (seit 1.3) keinen Schalter mehr - sie gelten fest für alle.
    local b = db.beacon
    b.ttl, b.cooldown, b.maxPerPlayer = 30, 60, 3
    b.useChannel, b.useGuild, b.useParty = true, true, true
    db.pins.kinds = { quest = true, campfire = true }
    db.pins.logOnly = false
    db.nav.waypoint, db.nav.arrowScale = true, 100
    db.music.onFishing, db.music.onSpot, db.music.onCampfire, db.music.player = true, true, true, true
    db.lore.interval = 5
    db.ui.calm, db.ui.locked = true, false
    db.minimap.offset = 5
    db.silentMode = nil
    db.music.own = nil
    if db.music.source ~= "tavern" then db.music.source = "camp" end
    for k in pairs(db.modules) do db.modules[k] = true end
    -- test8: Musik "nie" gibt es nicht mehr (Schalter "Musik von selbst": an = auch von selbst,
    -- aus = nur auf Klick)
    if db.music.mode == "off" then db.music.mode = "click" end
    -- test8: "Was darf von selbst kommen?" gibt es nicht mehr - die Fenster lernen mit
    db.ui.noPopups, db.ui.alerts = nil, nil
    if type(db.ui.learned) ~= "table" then db.ui.learned = {} end
    if type(db.ui.quickClose) ~= "table" then db.ui.quickClose = {} end
    if type(db.ui.tipsSeen) ~= "table" then db.ui.tipsSeen = {} end
    if db.activeTab == "info" then db.activeTab = "beacons" end
    if db.ui.settingsCat ~= "help" then db.ui.settingsCat = "general" end
    -- test8: ohne eigenen Schalter, gelten für alle (Hinweise kommen nur noch für deine Zone
    -- oder Quests in deinem Log, siehe Beacon.lua)
    db.music.waitTip, db.social.thanksCard, db.social.quickbar = true, true, true
    db.pins.world, db.pins.minimap, db.nav.arrow = true, true, true
    db.beacon.notify = true
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
SM:RegisterEvent(SM, "ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    local fresh = (SocializeMeForeverDB == nil) -- ganz neu: Einfach-Ansicht (test8b)
    SocializeMeForeverDB = SocializeMeForeverDB or {}
    CopyDefaults(SM.defaults, SocializeMeForeverDB)
    SM.db = SocializeMeForeverDB
    SM.Tidy(SM.db)
    if fresh then SM.db.ui.hideTabs = { places = true, contacts = true } end
    if type(SM.db.ui.hideTabs) ~= "table" then SM.db.ui.hideTabs = {} end
    -- Gewählte Sprache (sonst die des Spiels)
    local lang = SM.db.language
    local valid = false
    for _, code in ipairs(SM.LANGUAGES) do if code == lang then valid = true end end
    SM:ApplyLanguage(valid and lang or GetLocale())
    -- Skin und Durchsichtigkeit vor dem Aufbau der Fenster (test8b)
    SM.db.ui.skin = SM:ApplySkin(SM.db.ui.skin, SM.db.ui.opacity)
    BindingNames()
    -- "Nicht stören bis zum Ausloggen" endet mit dem neuen Login
    if SM.db.dndSession then SM.db.dnd, SM.db.dndSession = false, nil end
end)

-- Ist eine alte Test-Version (Ordner "SocializeMe_Forever", bis 0.9) noch installiert?
local function OldCopyLoaded()
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return fn and fn("SocializeMe_Forever") and true or false
end

SM:RegisterEvent(SM, "PLAYER_LOGIN", function()
    if not SM.db then return end
    if OldCopyLoaded() then SM:Print(L.OLD_COPY) end
    if SM.Guard then SM.Guard:Init() end
    -- Module laufen erst, wenn die Regeln bestätigt sind und keine Sperre besteht.
    if SM:Active() then SM:StartModules() end
    SM:Fire("READY") -- Oberfläche (Minimap-Button usw.) kann jetzt aufgebaut werden
    SM:Print(L.LOADED)
    if SM.Rules and not SM.Rules:Accepted() then
        SM:Print(L.RULES_PENDING)
        C_Timer.After(4, function() if not SM.Rules:Accepted() then SM.Rules:Show() end end)
    end
    if SM:IsTestMode() then SM:Print(L.TEST_ACTIVE) end -- nicht vergessen
    SM:CheckDND()
    C_Timer.NewTicker(30, function() SM:CheckDND() end)
    -- Einrichtung (3 kurze Fragen), sobald die Regeln bestätigt sind
    if SM.Rules and SM.Rules:Accepted() and not SM.db.ui.setupDone and SM.Setup then
        C_Timer.After(3, function() SM.Setup:Show() end)
    end
end)

-- Nach dem Kampf / beim Verlassen der Instanz: wartende Fenster zeigen
local Calm = {}
for _, ev in ipairs({ "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
    SM:RegisterEvent(Calm, ev, function()
        if SM.db then C_Timer.After(1, function() SM:FlushPopups() end) end
    end)
end

SM:RegisterCallback("RULES_ACCEPTED", function()
    if SM:Active() then SM:StartModules() end
    if not SM.db.ui.setupDone and SM.Setup then C_Timer.After(0.5, function() SM.Setup:Show() end) end
end)
