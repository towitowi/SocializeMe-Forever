local ADDON, SM = ...
local L = SM.L

-- Lagerfeuer
--
-- WoW Forever hat ein eigenes Camping-System: In der Nähe eines Feuers bekommt man einen Buff,
-- und wer sich 1 Minute hinsetzt, bekommt die Lager-Boni. Daran erkennt das Addon, dass du am
-- Feuer sitzt: Dann fragt ein kleiner Zettel nach Musik oder einer Geschichte (Musik nur einmal
-- pro Spielsitzung, sie startet nie von selbst). In Classic Era & Co. gibt es dieses System nicht.
--
-- Zündest du selbst ein Feuer an, bietet das Addon an, einen Lagerfeuer-Beacon zu setzen
-- (andere sehen auf der Karte, dass hier ein Feuer brennt - so lange wie das Feuer); Musik
-- fragt der kleine Zettel (einmal pro Spielsitzung).
-- Ein Lagerfeuer-Beacon ist ein ganz normaler Beacon: anschreiben, einladen, Weg zeigen.
-- Die Spell-IDs stammen aus öffentlichen Übersichten zu WoW Forever und werden im Spiel geprüft.
local Campfire = SM:NewModule("campfire")

local AURA_NEAR = 1283391        -- "Campfire Nearby" (in der Nähe eines Feuers)
local AURA_SIT = 1289723         -- "Welcoming Campfire" (sitzt und wartet auf die Boni)
local FIRE_SPELLS = {
    [818] = 5,                   -- Einfaches Lagerfeuer (Classic): Pin 5 Minuten
    [1229737] = 10,              -- Forever: Basic Campfire, brennt etwa 10 Minuten
    [1283400] = 10,              -- Forever: Journeyman Campfire
    [1291341] = 10,              -- Forever: Expert Campfire
}
local SIT_REPEAT = 600           -- Sek.: so oft höchstens die Frage am Feuer
local TICK = 5

Campfire.near = false
Campfire.sitting = false
Campfire.lastSit = -math.huge

local function HasAura(id)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(id) ~= nil
    end
    if not UnitBuff then return false end
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, sid = UnitBuff("player", i)
        if not name then break end
        if sid == id then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Am Feuer sitzen (nur WoW Forever)
---------------------------------------------------------------------------
function Campfire:CheckAuras()
    local near, sit = HasAura(AURA_NEAR), HasAura(AURA_SIT)
    local now = GetTime()
    if near then
        self.lastNearFire = now
        if SM.Chill then SM.Chill.lastCamp = now end
    end
    if sit and not self.sitting then self:OnSit() end
    self.near, self.sitting = near, sit
end

-- Musik auf Klick am Lagerfeuer: gilt als "Lagerfeuer-Musik" und endet von selbst, wenn du
-- eine Hauptstadt oder Instanz betrittst (test8b).
function Campfire:CampMusic()
    local Ch = SM.Chill
    if not Ch then return end
    local ok, msg = Ch:Play(nil, false)
    if ok then Ch:MarkOccasion(); Ch.lastCamp = GetTime() else SM:Print(msg) end
end

function Campfire:OnSit()
    if not SM:IsForever() then return false end   -- das Camping-System gibt es nur in Forever
    local now = GetTime()
    if (now - self.lastSit) < SIT_REPEAT or SM:IsDND() then return end
    self.lastSit = now
    local Ch = SM.Chill
    if not Ch then return end
    if Ch.playing then Ch.lastCamp = now end
    -- Musik nie von selbst (test8b): einmal pro Spielsitzung fragt der kleine Zettel
    -- "Musik / Geschichte". Danach (oder ohne Musik) bietet derselbe Zettel nur die Geschichte an.
    if Ch:Offer("campsit") then return end
    SM.Note:Ask("campstory", L.CAMP_SIT_ASK_STORY, { { L.CAMP_BTN_STORY, function() SM.LoreReader:Open() end } })
end

---------------------------------------------------------------------------
-- Feuer angezündet: Pin setzen? Musik?
---------------------------------------------------------------------------
function Campfire:OnLight(spellID)
    local minutes = FIRE_SPELLS[spellID]
    if not minutes or SM:IsDND() then return end
    local Ch = SM.Chill
    if not (SM.Beacon and SM.Beacon.enabled and SM.Beacon:LevelOK()) then
        if Ch then Ch:Offer("camplight") end -- nur Musik (einmal pro Spielsitzung)
        return
    end
    -- ein Zettel: Pin setzen? - und, falls noch nicht gefragt, gleich die Musik dazu
    local buttons = { { L.CAMP_BTN_PIN, function() self:SetPin(minutes) end } }
    local hint
    if Ch and Ch:CanOffer("camplight") then
        Ch.offered = true
        buttons[2] = { L.CAMP_BTN_MUSIC, function() Campfire:CampMusic() end }
        hint = L.MUSIC_UNTIL
    end
    SM.Note:Ask("camplight", L.CAMP_LIT_ASK, buttons, { hint = hint })
end

function Campfire:SetPin(minutes)
    local voice = (SM.Window and SM.Window.voiceLevel) or 0
    local ok, msg = SM.Beacon:Create("campfire", L.CAMP_PIN_TITLE, voice, nil, minutes)
    SM:Print(ok and L.CAMP_PIN_SET:format(minutes) or msg)
    return ok
end

---------------------------------------------------------------------------
-- Modul
---------------------------------------------------------------------------
function Campfire:OnEnable()
    SM:RegisterEvent(self, "UNIT_AURA", function(_, unit)
        if unit == "player" then self:CheckAuras() end
    end)
    SM:RegisterEvent(self, "UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
        if unit == "player" and FIRE_SPELLS[spellID] then self:OnLight(spellID) end
    end)
    self.ticker = C_Timer.NewTicker(TICK, function() self:CheckAuras() end)
end

function Campfire:OnDisable()
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
end
