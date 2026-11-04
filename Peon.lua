local ADDON, SM = ...

-- Peon-Sprüche aus Warcraft III als Ton - aber nur Töne, die schon im WoW-Client stecken
-- (abgespielt über ihre Datei-Nummer). Das Addon liefert keine Blizzard-Tondateien mit.
-- Höchstens ein Spruch alle 30 Sekunden. Am Anfang aus; an und aus nur mit /sm peon (seit test8 kein
-- eigener Schalter mehr in den Optionen). "Sei leise!" macht alles stumm.
--
-- Datei-Nummern der Töne im Spiel (Dateinamen im Client):
--   558137 peonready1.ogg            "Ready to work."  (Bereit zu arbeiten)
--   558147 peonyes3.ogg              "Work work."      (Arbeit, Arbeit)
--   558132 peonbuildingcomplete1.ogg "Work complete."  (Arbeit vollbracht)
-- Für "Mehr Arbeit?" ist die Nummer noch offen: /sm peon scan (Dev-Zusatz)
-- spielt die Töne rund um diese Nummern nacheinander ab, damit wir sie im Spiel zuordnen können.
local Peon = {}
SM.Peon = Peon

local LOCK = 30   -- Sek. zwischen zwei Sprüchen

Peon.SOUNDS = {
    beacon   = 558137,  -- Beacon gesetzt: "Bereit zu arbeiten!"
    coming   = 558147,  -- jemand kommt zu deinem Beacon: "Arbeit, Arbeit."
    ready    = 558132,  -- Quest deines Beacons ist abgabebereit: "Arbeit vollbracht!"
    turnedin = nil,     -- nach dem Abgeben: "Mehr Arbeit?" (Nummer noch offen)
}

Peon.last = -math.huge

-- Spielt den Spruch zu einem Ereignis. Gibt true zurück, wenn ein Ton lief.
function Peon:Say(event, force)
    if not SM.db or not SM.db.peon then return false end
    if SM:IsSilent() then return false end
    local id = self.SOUNDS[event]
    if not id or type(PlaySoundFile) ~= "function" then return false end
    local now = GetTime()
    if not force and (now - self.last) < LOCK then return false end
    local ok, willPlay = pcall(PlaySoundFile, id, "Master")
    if ok and willPlay ~= false then
        self.last = now
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
SM:RegisterCallback("BEACON_ADDED", function(b)
    if b and b.own then Peon:Say("beacon") end
end)

-- Stand der Quest im eigenen Beacon: abgabebereit / abgegeben
SM:RegisterCallback("BEACON_UPDATED", function(b)
    if not (b and b.own and b.questID) then return end
    local Q = SM.QuestInfo
    if b.qstate == Q.STATE_READY and b.peonState ~= Q.STATE_READY then
        Peon:Say("ready")
    elseif b.qstate == Q.STATE_TURNEDIN and b.peonState ~= Q.STATE_TURNEDIN then
        Peon:Say("turnedin")
    end
    b.peonState = b.qstate
end)

-- (Zum Ausprobieren der Sprüche gibt es /sm peon im privaten Dev-Zusatz.)

-- /sm peon: an/aus (auch /sm peon an|aus). Beim Einschalten ein Spruch zur Probe.
function Peon:Toggle(rest)
    rest = (rest or ""):lower()
    local on
    if rest == "an" or rest == "on" then on = true
    elseif rest == "aus" or rest == "off" then on = false
    else on = not SM.db.peon end
    SM.db.peon = on
    SM:Print(on and SM.L.PEON_ON or SM.L.PEON_OFF)
    if on then self:Say("beacon", true) end
    return on
end

SM:RegisterCommand("peon", function(rest) Peon:Toggle(rest) end)
