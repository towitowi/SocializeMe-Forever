local ADDON, SM = ...
local L = SM.L

-- Spaß-Töne in der Gruppe: acht kurze Töne aus dem Spiel (Murloc, Peon, Huhn ...), als zweite
-- Reihe in der Schnellsätze-Leiste.
--
-- Wer hört das? Ein Addon kann Töne nur bei dir selbst abspielen. Drückst du einen Knopf, geht
-- eine kurze Addon-Nachricht an deine Gruppe (S;1;<Ton>). Nur Gruppenmitglieder, die auch
-- SocializeMe haben und die Töne eingeschaltet lassen, hören ihn - niemand sonst in der Nähe.
--
-- Damit es nicht nervt:
--   * du: höchstens ein Ton alle 20 Sek. und 3 Töne in 5 Min. (bleibt auch nach /reload)
--   * beim Hören: dieselbe Grenze je Person. Wer mehr schickt (z. B. mit umgebautem Addon),
--     ist bis zum Logout stumm. Höchstens ein Ton alle 3 Sek. aus der ganzen Gruppe.
--   * nichts im Kampf, nichts in Schlachtfeldern, nichts bei "Nicht stören" oder "Töne aus"
--   * im Chat steht, wer welchen Ton gespielt hat - und wie man die Töne abschaltet
--     (Einstellungen > Miteinander oder /sm töne aus)
local Soundboard = {}
SM.Soundboard = Soundboard

local PREFIX = "SMForever"
local GAP = 20           -- Sek. zwischen zwei eigenen Tönen
local WINDOW = 300       -- Sek.: in diesem Zeitraum ...
local MAX_IN_WINDOW = 3  -- ... höchstens so viele Töne
local SLACK = 2          -- Sek. Spielraum beim Hören (Nachrichten kommen nicht auf die Sekunde an)
local GROUP_GAP = 3      -- Sek. zwischen zwei gehörten Tönen, egal von wem
local HINT_EVERY = 300   -- Sek.: so oft höchstens der Hinweis, wie man die Töne abschaltet

-- Dateinummern der Töne im Spiel (alle schon in Classic vorhanden). Bei mehreren Nummern
-- wird zufällig eine gespielt - so klingt der Peon nicht jedes Mal gleich.
Soundboard.SOUNDS = {
    { key = "m", name = "SND_MURLOC", files = { 556000 } },
    { key = "p", name = "SND_PEON", files = { 558136, 558139, 558140, 558147 } },
    { key = "c", name = "SND_CHICKEN", files = { 546069 } },
    { key = "s", name = "SND_SHEEP", files = { 560229 } },
    { key = "f", name = "SND_FROG", files = { 549323 } },
    -- Applaus: alle drei Klatscher kurz nacheinander (klingt wie Beifall, zählt als ein Ton)
    { key = "a", name = "SND_CLAP", files = { 539147, 539151, 539152 }, chain = 0.18 },
    { key = "w", name = "SND_FIREWORK", files = { 566373, 566585, 566862 } },
    { key = "d", name = "SND_DING", files = { 567431 } },
}
local BY_KEY = {}
for _, s in ipairs(Soundboard.SOUNDS) do BY_KEY[s.key] = s end

Soundboard.heard = {}       -- Spielername -> Liste der Zeiten (GetTime) seiner Töne
Soundboard.muted = {}       -- Spielername -> true: zu viele Töne, stumm bis zum Logout
Soundboard.lastHeard = -math.huge
Soundboard.lastHint = -math.huge

local function InGroup()
    return (type(IsInGroup) == "function" and IsInGroup()) or (type(IsInRaid) == "function" and IsInRaid()) or false
end

local function GroupChannel()
    if type(IsInRaid) == "function" and IsInRaid() then return "RAID" end
    return "PARTY"
end

local function InCombat()
    return type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player") and true or false
end

local function InBattleground()
    if type(IsInInstance) ~= "function" then return false end
    local _, kind = IsInInstance()
    return kind == "pvp" or kind == "arena"
end

-- Ist der Spieler gerade in meiner Gruppe?
local function InMyGroup(name)
    if type(UnitInParty) == "function" and UnitInParty(name) then return true end
    if type(UnitInRaid) == "function" and UnitInRaid(name) then return true end
    return false
end

-- Ton bei mir abspielen (über den Effekt-Regler, damit die WoW-Lautstärke gilt)
local function PlayLocal(s)
    if type(PlaySoundFile) ~= "function" then return false end
    if s.chain then
        local ok, willPlay = pcall(PlaySoundFile, s.files[1], "SFX")
        for i = 2, #s.files do
            C_Timer.After((i - 1) * s.chain, function() pcall(PlaySoundFile, s.files[i], "SFX") end)
        end
        return ok and willPlay ~= false
    end
    local id = s.files[math.random(#s.files)]
    local ok, willPlay = pcall(PlaySoundFile, id, "SFX")
    return ok and willPlay ~= false
end

function Soundboard:Enabled()
    return SM.db and SM.db.social.funSounds ~= false and true or false
end

function Soundboard:SetEnabled(state)
    SM.db.social.funSounds = state and true or false
    if SM.Social then SM.Social:UpdateBar() end
end

---------------------------------------------------------------------------
-- Selbst spielen
---------------------------------------------------------------------------
-- Eigene Töne der letzten 5 Minuten (time(), damit /reload die Pause nicht aufhebt)
local function OwnHistory(now)
    local s = SM.db.social
    local keep = {}
    for _, t in ipairs(type(s.soundTimes) == "table" and s.soundTimes or {}) do
        if type(t) == "number" and now - t < WINDOW and t <= now then keep[#keep + 1] = t end
    end
    s.soundTimes = keep
    return keep
end

-- Sekunden, bis der nächste eigene Ton erlaubt ist (0 = jetzt)
function Soundboard:Wait()
    if not SM.db then return 0 end
    local now = time()
    local hist = OwnHistory(now)
    local wait = 0
    local last = hist[#hist]
    if last then wait = math.max(wait, last + GAP - now) end
    if #hist >= MAX_IN_WINDOW then wait = math.max(wait, hist[#hist - MAX_IN_WINDOW + 1] + WINDOW - now) end
    return math.max(0, math.ceil(wait))
end

-- Gibt true zurück, wenn der Ton rausging. msg erklärt, warum nicht.
function Soundboard:Play(key)
    local s = BY_KEY[key]
    if not s or not SM.db then return false end
    if not self:Enabled() then return false, L.SND_OFF_HINT end
    if not SM:SoundsOn() then return false, L.SND_SOUNDS_OFF end
    if InCombat() then return false, L.SND_COMBAT end
    if InBattleground() then return false, L.SND_BATTLEGROUND end
    local sim = self.sim   -- Probe-Modus (Dev): nur bei dir, nichts geht raus
    if not sim and not InGroup() then return false, L.SND_NO_GROUP end
    local wait = self:Wait()
    if wait > 0 then return false, L.SND_WAIT:format(wait) end
    if sim then
        if type(sim) == "function" then sim("S;1;" .. key) end
    else
        local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
        if not fn or not pcall(fn, PREFIX, "S;1;" .. key, GroupChannel()) then return false, L.SND_FAILED end
    end
    local hist = OwnHistory(time())
    hist[#hist + 1] = time()
    PlayLocal(s)
    self:Fire()
    return true
end

-- Knöpfe in der Leiste dämpfen, solange Pause ist
function Soundboard:Fire()
    if SM.Social and SM.Social.RefreshSoundRow then SM.Social:RefreshSoundRow() end
    local wait = self:Wait()
    if wait > 0 then
        C_Timer.After(wait + 0.2, function() if SM.Social and SM.Social.RefreshSoundRow then SM.Social:RefreshSoundRow() end end)
    end
end

---------------------------------------------------------------------------
-- Hören
---------------------------------------------------------------------------
-- Prüft die Grenze je Person. false = zu viele (dann stumm bis zum Logout).
function Soundboard:WithinLimit(name, now)
    local list = self.heard[name] or {}
    local keep = {}
    for _, t in ipairs(list) do if now - t < WINDOW - SLACK then keep[#keep + 1] = t end end
    self.heard[name] = keep
    local last = keep[#keep]
    if last and now - last < GAP - SLACK then return false end
    if #keep >= MAX_IN_WINDOW then return false end
    keep[#keep + 1] = now
    return true
end

-- Ein Ton aus der Gruppe kommt an. Gibt true zurück, wenn er gespielt wurde.
function Soundboard:Receive(sender, key, fromProbe)
    local s = BY_KEY[key]
    if not s or not SM.db or not SM:Active() then return false end
    local short = (sender:match("^([^-]+)")) or sender
    if short == UnitName("player") then return false end
    if self.muted[short] then return false end
    if SM.Beacon and SM.Beacon:IsIgnored(short) then return false end
    if SM.Guard and SM.Guard:IsBlocked(short) then return false end
    if not fromProbe and not InMyGroup(short) then return false end
    local now = GetTime()
    -- Die Grenze zählt auch, wenn du die Töne gerade nicht hörst - wer spammt, bleibt stumm.
    if not self:WithinLimit(short, now) then
        self.muted[short] = true
        if self:Enabled() then SM:Print(L.SND_MUTED_SPAM:format(short)) end
        return false
    end
    if not self:Enabled() or not SM:SoundsOn() or SM:IsDND() then return false end
    if InCombat() or InBattleground() then return false end
    if now - self.lastHeard < GROUP_GAP then return false end
    self.lastHeard = now
    PlayLocal(s)
    SM:Print(L.SND_HEARD:format(short, L[s.name]))
    -- der Hinweis zum Abschalten als eigene Zeile - am Zeilenende wurde er übersehen
    if now - self.lastHint >= HINT_EVERY then
        self.lastHint = now
        SM:Print(L.SND_ANNOY_HINT)
    end
    return true
end

function Soundboard:HandleMessage(text, dist, sender)
    if dist ~= "PARTY" and dist ~= "RAID" then return end
    local key = text:match("^S;1;(%a)$")
    if key then self:Receive(sender, key) end
end

SM:RegisterEvent(Soundboard, "CHAT_MSG_ADDON", function(_, prefix, text, dist, sender)
    if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" then return end
    if text:sub(1, 2) == "S;" then Soundboard:HandleMessage(text, dist, sender) end
end)

-- /sm töne [aus|an]
local function Command(rest)
    rest = (rest or ""):lower()
    if rest == "aus" or rest == "off" or rest == "stopp" or rest == "stop" then
        Soundboard:SetEnabled(false)
        SM:Print(L.SND_NOW_OFF)
    elseif rest == "an" or rest == "ein" or rest == "on" then
        Soundboard:SetEnabled(true)
        SM:Print(L.SND_NOW_ON)
    else
        Soundboard:SetEnabled(not Soundboard:Enabled())
        SM:Print(Soundboard:Enabled() and L.SND_NOW_ON or L.SND_NOW_OFF)
    end
    if SM.Window and SM.Window.frame and SM.Window.frame:IsShown() then SM.Window:RefreshSettings() end
end
-- "Töne" klein geschrieben bleibt in WoW "tÖne" (Umlaute werden nicht umgewandelt)
SM:RegisterCommand("töne", Command, "tÖne", "toene", "tone", "sounds", "sound")
