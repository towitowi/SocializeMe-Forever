local ADDON, SM = ...
local L = SM.L
local M = SM.Media
local Q = SM.QuestInfo

-- Laufzeit, Wegweiser und "Ich komme":
--   * Entfernung und Laufzeit (Luftlinie) zu einem Beacon
--   * Wegweiser-Pfeil und ein eigenes Ziel-Fähnchen auf Weltkarte und Minimap (am Rand der Minimap,
--     solange das Ziel weiter weg ist) statt Blizzards grünem Wegpunkt - auch wenn TomTom installiert ist
--     (alles in unserer Optik; TomTom bekommt keinen zweiten Wegpunkt mehr).
--     Bewusst OHNE Blizzards
--     großen Bildschirm-Pfeil (Super-Track) und ohne TomToms "Crazy Arrow": unser kleiner Pfeil
--     oben in der Mitte reicht, zwei Pfeile übereinander verwirren nur.
--   * "Ich komme": der Ersteller erfährt nur deine ungefähre Ankunftszeit (alle 30 Sek. neu), NICHT deine Position
--   * der Ersteller sieht im Tooltip seines Beacons, wer kommt und wann. Ab 3 Minuten vor der
--     Ankunft steht jede Minute eine Zeile im Chat ("Towi ist in ca. 2 Min. da.")
--   * "Ist da": kurz vor dem Ziel noch eine Zeile im Chat
local Eta = SM:NewModule("eta")

local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
local HBDPins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
local TARGET_SIZE = 16          -- Ziel-Fähnchen: etwas größer als ein Beacon-Pin

local PROTO = 2                 -- Version der kurzen Nachrichten C und A
local NEAR_SECONDS = 15         -- "Ist da": weniger als 15 Sekunden ...
local NEAR_YARDS = 50           -- ... oder weniger als 50 Meter
local ARRIVED_YARDS = 10        -- ab hier gilt man als angekommen
local TICK = 1                  -- Sekunden: Prüfung unterwegs
local ETA_RESEND = 30           -- Sek.: so oft schickt der Ankommende seine Restzeit neu
local DEFAULT_SPEED = 7         -- Laufgeschwindigkeit ohne Reittier, falls das Spiel nichts liefert
local COUNTDOWN_FROM = 180      -- Sek.: ab 3 Minuten vor der Ankunft ...
                                -- ... jede Minute eine Chatzeile für den Ersteller
local WATCH_TICK = 5            -- Sek.: Ersteller prüft so oft die Restzeiten
local COME_MIN_INTERVAL = 5     -- Sek.: Mindestabstand empfangener "Ich komme" je Spieler und Beacon
local ALERT_MIN_INTERVAL = 60   -- Sek.: höchstens ein "Ist da" je Spieler und Beacon
local MAX_COMING = 8            -- so viele Ankommende zeigt ein Beacon höchstens an

Eta.target = nil                -- das Beacon, zu dem gerade navigiert wird
Eta.announced = false           -- "Ich komme" wurde gesendet

local function Num(v)
    return type(v) == "number" and v or nil
end

-- Name für Anzeigen: Quest-Name (in deiner Sprache), sonst der Text des Beacons.
local function DisplayName(b)
    local name = b.questID and (Q:LocalTitle(b.questID) or b.questName)
    if name and name ~= "" then return name end
    return b.title
end

---------------------------------------------------------------------------
-- Position, Entfernung, Richtung
---------------------------------------------------------------------------
-- Weltkoordinaten des Beacons (einmal berechnet und am Beacon gemerkt).
local function BeaconWorld(b)
    if b.wInst == nil then
        if HBD then
            local x, y, inst = HBD:GetWorldCoordinatesFromZone(b.x, b.y, b.mapID)
            if x and y and inst then
                b.wx, b.wy, b.wInst = x, y, inst
            else
                b.wInst = false
            end
        else
            b.wInst = false
        end
    end
    if b.wInst then return b.wx, b.wy, b.wInst end
end

-- Position auf der Karte (0-1) und Kartengröße in Yards - nur für den Notfall ohne Bibliothek.
local function MapPosition(mapID)
    if not (C_Map and C_Map.GetPlayerMapPosition and C_Map.GetMapWorldSize) then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    local px, py
    if pos and pos.GetXY then px, py = pos:GetXY() end
    if not px or not py or (px == 0 and py == 0) then return end
    local w, h = C_Map.GetMapWorldSize(mapID)
    if not Num(w) or w <= 0 or not Num(h) or h <= 0 then return end
    return px, py, w, h
end

-- Gibt die Entfernung in Yards zurück. Ohne Ergebnis: nil und der Grund
-- ("map" = andere Karte/anderer Kontinent, "pos" = Position unbekannt).
function Eta:Distance(b)
    if HBD then
        local bx, by, binst = BeaconWorld(b)
        if not bx then return nil, "pos" end
        local px, py, pinst = HBD:GetPlayerWorldPosition()
        if not px then return nil, "pos" end
        if pinst ~= binst then return nil, "map" end
        return (HBD:GetWorldDistance(binst, px, py, bx, by))
    end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return nil, "pos" end
    if mapID ~= b.mapID then return nil, "map" end
    local px, py, w, h = MapPosition(mapID)
    if not px then return nil, "pos" end
    local dx, dy = (b.x - px) * w, (b.y - py) * h
    return math.sqrt(dx * dx + dy * dy)
end

local atan2 = math.atan2 or math.atan

-- Richtung zum Beacon als Winkel (Bogenmaß, 0 = Norden, gegen den Uhrzeigersinn - wie GetPlayerFacing).
function Eta:Bearing(b)
    if HBD then
        local bx, by, binst = BeaconWorld(b)
        local px, py, pinst = HBD:GetPlayerWorldPosition()
        if not (bx and px) or binst ~= pinst then return nil end
        return (HBD:GetWorldVector(binst, px, py, bx, by))
    end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID or mapID ~= b.mapID then return nil end
    local px, py, w, h = MapPosition(mapID)
    if not px then return nil end
    local east, north = (b.x - px) * w, -(b.y - py) * h
    local angle = atan2(-east, north)
    if angle < 0 then angle = angle + math.pi * 2 end
    return angle
end

-- Laufgeschwindigkeit in Yards pro Sekunde: aktuelle, sonst die mögliche (Reittier!), sonst 7.
function Eta:Speed()
    local cur, run
    if type(GetUnitSpeed) == "function" then cur, run = GetUnitSpeed("player") end
    cur, run = Num(cur), Num(run)
    local speed = (cur and cur > 0) and cur or run
    if not speed or speed <= 0 then speed = DEFAULT_SPEED end
    return speed
end

---------------------------------------------------------------------------
-- Texte
---------------------------------------------------------------------------
function Eta.FormatDistance(yards)
    return L.DIST_FMT:format(math.max(1, math.floor(yards + 0.5)))
end

-- Auf 5 Sekunden gerundet, damit die Anzeige nicht flackert.
function Eta.FormatTime(seconds)
    seconds = math.max(5, math.ceil((seconds or 0) / 5) * 5)
    if seconds < 60 then return L.TIME_SEC:format(seconds) end
    return L.TIME_MIN:format(math.floor(seconds / 60), seconds % 60)
end

-- Zeile fürs Tooltip. nil = nichts anzeigen (eigenes Beacon, Position unbekannt).
function Eta:Describe(b)
    if not b or b.own then return nil end
    local d, why = self:Distance(b)
    if not d then
        if why == "map" then return L.TT_ETA_MAP end
        return nil
    end
    if d <= ARRIVED_YARDS + 5 then return L.TT_ETA_HERE end
    return L.TT_ETA:format(Eta.FormatDistance(d), Eta.FormatTime(d / self:Speed()))
end

---------------------------------------------------------------------------
-- Wegpunkte: eigenes Ziel-Fähnchen (Weltkarte + Minimap), immer in unserer Optik.
-- Nur wenn beides fehlt, nimmt das Addon Blizzards Wegpunkt.
---------------------------------------------------------------------------
local function TargetTooltip(f)
    local t = Eta.target
    if not t then return end
    GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L.TARGET_TT, 0.6, 0.85, 0.85)
    GameTooltip:AddLine(DisplayName(t), 1, 0.82, 0)
    local d = Eta:Describe(t)
    if d then GameTooltip:AddLine(d, 1, 1, 1) end
    GameTooltip:AddLine(L.TARGET_TT_HINT, 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

function Eta:TargetPin(which)
    self.targetPins = self.targetPins or {}
    local f = self.targetPins[which]
    if f then return f end
    local TEX = "Interface\\AddOns\\SocializeMeForever\\Media\\"
    f = CreateFrame("Button", nil, UIParent)
    f:SetSize(TARGET_SIZE, TARGET_SIZE)
    f:EnableMouse(true)
    f:RegisterForClicks("RightButtonUp")
    f.disc = f:CreateTexture(nil, "ARTWORK")
    f.disc:SetAllPoints(f)
    f.disc:SetTexture(TEX .. "pin_target")
    f.ring = f:CreateTexture(nil, "OVERLAY")
    f.ring:SetAllPoints(f)
    f.ring:SetTexture(TEX .. "pin_frame")
    f:SetScript("OnEnter", TargetTooltip)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnClick", function() Eta:Stop() end)
    self.targetPins[which] = f
    return f
end

function Eta:SetWaypoints(b)
    self:ClearWaypoints()
    if not SM.db.nav.waypoint then return end

    if HBDPins then
        local w, m = self:TargetPin("world"), self:TargetPin("mini")
        local flag = _G.HBD_PINS_WORLDMAP_SHOW_PARENT or 1
        local okW, addedW = pcall(HBDPins.AddWorldMapIconMap, HBDPins, self, w, b.mapID, b.x, b.y, flag)
        -- true, true: auch in der Nachbarzone zeigen und am Rand der Minimap bleiben, solange es weit weg ist
        local okM, addedM = pcall(HBDPins.AddMinimapIconMap, HBDPins, self, m, b.mapID, b.x, b.y, true, true)
        if okM and addedM and Minimap and Minimap.GetFrameLevel then m:SetFrameLevel(Minimap:GetFrameLevel() + 3) end
        self.ownTarget = (okW and addedW) or (okM and addedM) or false
        if self.ownTarget then w:Show(); m:Show() end
    end

    if not self.ownTarget and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local can = true
        if C_Map.CanSetUserWaypointOnMap then can = C_Map.CanSetUserWaypointOnMap(b.mapID) end
        if can then
            -- nur die Markierung auf der Karte, kein Super-Track (der zeigt einen zweiten großen Pfeil)
            self.sysWaypoint = pcall(function()
                C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(b.mapID, b.x, b.y))
            end)
        end
    end
end

function Eta:ClearWaypoints()
    if self.ownTarget then
        self.ownTarget = false
        if HBDPins then
            pcall(HBDPins.RemoveAllWorldMapIcons, HBDPins, self)
            pcall(HBDPins.RemoveAllMinimapIcons, HBDPins, self)
        end
        for _, f in pairs(self.targetPins or {}) do f:Hide() end
    end
    if self.sysWaypoint then
        self.sysWaypoint = false
        if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
    end
    if self.tomtomUID then
        if TomTom and type(TomTom.RemoveWaypoint) == "function" then pcall(TomTom.RemoveWaypoint, TomTom, self.tomtomUID) end
        self.tomtomUID = nil
    end
end

---------------------------------------------------------------------------
-- Wegweiser-Pfeil
---------------------------------------------------------------------------
local ARROW_W, ARROW_H = 310, 54
local ARROW_TOP = -90           -- Standardplatz: oben in der Mitte, unter der Zonenanzeige

function Eta:BuildArrow()
    if self.arrow then return end
    local f = CreateFrame("Frame", "SocializeMeForeverArrow", UIParent)
    self.arrow = f
    f:SetSize(ARROW_W, ARROW_H)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(fr) SM.UI.DragStart(fr) end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relPoint, x, y = frame:GetPoint()
        local n = SM.db.nav
        n.point, n.relPoint, n.x, n.y = point, relPoint, x, y
    end)
    local n = SM.db.nav
    f:SetScale((n.arrowScale or 100) / 100)
    if n.point then
        f:SetPoint(n.point, UIParent, n.relPoint or n.point, n.x or 0, n.y or 0)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, ARROW_TOP)
    end

    local UI = SM.UI -- wird erst nach den Modulen geladen
    local panel = UI.Panel(f, nil, M.colors.wood)
    panel:SetAllPoints(f)
    UI.AddGrain(panel, ARROW_W, ARROW_H, "ARTWORK")
    -- 1.3.1: kein Kasten mehr - nur Pfeil und Text (der Holz-Hintergrund deckte zu viel ab)
    for _, r in ipairs({ panel:GetRegions() }) do
        if r and r.SetAlpha then r:SetAlpha(0) end
    end
    -- Pfeil, Texte und X liegen auf der Holzfläche (ein Kind-Frame würde sonst alles am Rahmen verdecken)

    f.arrowTex = panel:CreateTexture(nil, "OVERLAY")
    f.arrowTex:SetSize(34, 34)
    f.arrowTex:SetPoint("LEFT", f, "LEFT", 10, 0)
    f.arrowTex:SetTexture(M.tex.arrow)
    local t = M.wood.accent
    f.arrowTex:SetVertexColor(t[1], t[2], t[3])

    local tx = M.wood.text
    f.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 52, -9)
    f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -9)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.title:SetTextColor(tx[1], tx[2], tx[3])
    f.title:SetShadowOffset(1, -1) -- ohne Kasten: Schatten, damit man es auf jedem Boden lesen kann
    f.title:SetShadowColor(0, 0, 0, 1)

    f.info = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.info:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
    f.info:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    f.info:SetJustifyH("LEFT")
    f.info:SetWordWrap(false)
    f.info:SetTextColor(M.wood.textOff[1] + 0.2, M.wood.textOff[2] + 0.2, M.wood.textOff[3] + 0.2)
    f.info:SetShadowOffset(1, -1) -- ohne Kasten: Schatten, damit man es auf jedem Boden lesen kann
    f.info:SetShadowColor(0, 0, 0, 1)

    -- 1.3.1: auch das X ohne Kasten - nur ein weißes X mit Schatten (Maus darauf: gelb)
    local close = CreateFrame("Button", nil, panel)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    close.label = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    close.label:SetPoint("CENTER", 0, 0)
    close.label:SetText("X")
    close.label:SetTextColor(1, 1, 1)
    close.label:SetShadowOffset(1, -1)
    close.label:SetShadowColor(0, 0, 0, 1)
    close:SetScript("OnClick", function() Eta:Stop() end)
    close:SetScript("OnEnter", function(btn) btn.label:SetTextColor(1, 0.82, 0) end)
    close:SetScript("OnLeave", function(btn) btn.label:SetTextColor(1, 1, 1) end)
    f.close = close

    -- Was man mit dem Pfeil machen kann
    f:SetScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L.ARROW_TT_TITLE, 1, 0.82, 0)
        GameTooltip:AddLine(L.ARROW_TT_DRAG, 1, 1, 1)
        GameTooltip:AddLine(L.ARROW_TT_STOP, 1, 1, 1)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local acc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + (elapsed or 0)
        if acc < 0.1 then return end
        acc = 0
        Eta:UpdateArrow()
    end)
    f:Hide()
end

function Eta:UpdateArrow()
    local b, f = self.target, self.arrow
    if not b or not f then return end
    f.title:SetText(DisplayName(b))

    local d, why = self:Distance(b)
    if d then
        f.info:SetText(L.TT_ETA:format(Eta.FormatDistance(d), Eta.FormatTime(d / self:Speed())))
    elseif why == "map" then
        f.info:SetText(L.ARROW_MAP)
    else
        f.info:SetText(L.ARROW_NOPOS)
    end

    local angle = d and self:Bearing(b)
    local facing = type(GetPlayerFacing) == "function" and GetPlayerFacing() or nil
    if angle and facing then
        f.arrowTex:SetAlpha(1)
        if f.arrowTex.SetRotation then f.arrowTex:SetRotation(angle - facing) end
    else
        f.arrowTex:SetAlpha(0.35)
    end
end

---------------------------------------------------------------------------
-- Navigation starten / beenden (Seite des Ankommenden)
---------------------------------------------------------------------------
function Eta:Stop(silent)
    local had = self.target ~= nil
    self.target, self.announced = nil, false
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if self.arrow then self.arrow:Hide() end
    self:ClearWaypoints()
    if had and not silent then SM:Print(L.NAV_STOPPED) end
    return had
end

-- Restzeit in Sekunden (1-3599) oder 0, wenn unbekannt (z. B. andere Karte).
function Eta:SecondsTo(b)
    local d = self:Distance(b)
    if not d then return 0 end
    return math.max(1, math.min(3599, math.floor(d / self:Speed() + 0.5)))
end

-- "Ich komme" mit der aktuellen Restzeit (nur die Zeit, keine Position).
function Eta:SendComing(b)
    local ok = SM.Beacon:Whisper(b.from or b.sender, ("C;%d;%d;%d"):format(PROTO, b.id, self:SecondsTo(b)))
    if ok then self.lastEtaSent = GetTime() end
    return ok
end

-- "Ist da" an den Ersteller (höchstens einmal je Ziel).
function Eta:SendNear(b)
    if not self.announced or b.nearSent then return end
    b.nearSent = true
    SM.Beacon:Whisper(b.from or b.sender, ("A;%d;%d"):format(PROTO, b.id))
end

function Eta:Tick()
    local b = self.target
    if not b then return end
    if not b.point and SM.Beacon.cache[b.key] ~= b then -- abgelaufen oder zurückgezogen
        self:Stop(true)
        SM:Print(L.NAV_GONE)
        return
    end
    local d = self:Distance(b)
    if d and d <= ARRIVED_YARDS then
        self:SendNear(b)
        self:Stop(true)
        if b.point then
            -- ein Ort (Stadtführer, Orte-Tab): sagen, was hier ist
            local line = L.NAV_ARRIVED_AT:format(b.title or "?")
            if b.desc and b.desc ~= "" then line = line .. " - " .. b.desc end
            SM:Print(line)
        else
            SM:Print(L.NAV_ARRIVED)
        end
        return
    end
    if not self.announced then return end
    if d and not b.nearSent and (d <= NEAR_YARDS or d / self:Speed() <= NEAR_SECONDS) then
        self:SendNear(b)
    elseif not b.nearSent and (GetTime() - (self.lastEtaSent or 0)) >= ETA_RESEND then
        self:SendComing(b) -- neue Restzeit, damit die Vorwarnung beim Ersteller rechtzeitig kommt
    end
end

-- Beim ersten Wegweiser je Sitzung: wie man ihn wieder beendet.
function Eta:StopHint()
    if self.stopHintShown then return end
    self.stopHintShown = true
    SM:Print(L.NAV_STOP_HINT)
end

-- Zeigt den Weg zu einem Beacon. announce = true: der Ersteller erfährt "Ich komme" (nur die Ankunftszeit).
-- Gibt true/false und einen Text für die Statuszeile zurück.
function Eta:Go(b, announce)
    if not self.enabled then return false, L.NAV_OFF end
    if not b or b.own then return false, L.NAV_OWN end

    self:Stop(true)
    self.target = b
    b.nearSent = false

    local msg = L.NAV_START:format(DisplayName(b))
    if announce then
        if self:SendComing(b) then
            self.announced = true
            msg = L.NAV_COMING:format(b.sender)
            if SM.Contacts then SM.Contacts:Add(b.from or b.sender, "beacon", DisplayName(b)) end
        else
            msg = L.NAV_COMING_FAIL:format(b.sender)
        end
    end

    self:SetWaypoints(b)
    if SM.db.nav.arrow then
        self:BuildArrow()
        self.arrow:Show()
        self:UpdateArrow()
    end
    self.ticker = C_Timer.NewTicker(TICK, function() self:Tick() end)
    self:StopHint()
    SM:Fire("NAV_STARTED", b)
    return true, msg
end

-- Weg zu einem festen Punkt (z. B. einem Aussichtspunkt): point = { mapID, x, y, title }.
function Eta:GoTo(point)
    if not self.enabled then return false, L.NAV_OFF end
    if not (point and point.mapID and point.x and point.y) then return false, L.NAV_NONE end
    self:Stop(true)
    point.point = true
    self.target = point
    self:SetWaypoints(point)
    if SM.db.nav.arrow then
        self:BuildArrow()
        self.arrow:Show()
        self:UpdateArrow()
    end
    self.ticker = C_Timer.NewTicker(TICK, function() self:Tick() end)
    self:StopHint()
    SM:Fire("NAV_STARTED", point)
    return true, L.NAV_START:format(point.title or "?")
end

---------------------------------------------------------------------------
-- Seite des Erstellers: "Ich komme" (C) und "Ist da" (A) - nur als Flüster-Nachricht gültig
---------------------------------------------------------------------------
local function CountComing(b)
    local n = 0
    for _ in pairs(b.coming) do n = n + 1 end
    return n
end

-- Restzeit eines Ankommenden jetzt (aus seiner letzten Meldung heruntergezählt), nil = unbekannt.
local function Remaining(c, now)
    if not c.eta or c.eta <= 0 then return nil end
    return math.max(0, c.eta - (now - c.at))
end

local function PlayAlertSound(kit, fallback)
    if not SM:SoundsOn() or type(PlaySound) ~= "function" then return end
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT[kit]) or fallback)
end

-- Ab 3 Minuten: jede volle Minute eine Zeile ("in ca. 3 Min.", "2 Min.", "1 Min.")
function Eta:Countdown(b, name, c, rest)
    if c.near or rest > COUNTDOWN_FROM then return end
    local minutes = math.max(1, math.ceil(rest / 60))
    if c.lastMin and minutes >= c.lastMin then return end
    c.lastMin = minutes
    SM:Print(L.ETA_COUNTDOWN:format(name, minutes))
end

-- Prüft alle Ankommenden meiner Beacons (Countdown im Chat ab 3 Minuten).
function Eta:CheckComers()
    local now, any = GetTime(), false
    for _, b in pairs(SM.Beacon.cache) do
        if b.own and b.coming then
            for name, c in pairs(b.coming) do
                if c.expires <= now then
                    b.coming[name] = nil
                else
                    any = true
                    local rest = Remaining(c, now)
                    if rest then self:Countdown(b, name, c, rest) end
                end
            end
        end
    end
    if not any and self.watcher then self.watcher:Cancel(); self.watcher = nil end
end

function Eta:WatchComers()
    if self.watcher then return end
    self.watcher = C_Timer.NewTicker(WATCH_TICK, function() self:CheckComers() end)
end

function Eta:HandleWhisper(text, short, sender)
    if SM:IsDND() or SM.Beacon:IsIgnored(short) then return end
    local now = GetTime()
    local kind = text:sub(1, 1)

    if kind == "C" then
        local id, secs = text:match("^C;2;(%d+);(%d+)$")
        id, secs = tonumber(id), tonumber(secs)
        local b = id and SM.Beacon:FindOwn(id)
        if not b then return end
        b.coming = b.coming or {}
        local c = b.coming[short]
        if c and (now - c.at) < COME_MIN_INTERVAL then return end
        if not c and CountComing(b) >= MAX_COMING then return end
        secs = math.min(secs, 3599)
        if c then
            c.eta, c.at = secs, now
            c.expires = now + math.max(120, math.min(secs * 2, 900))
        else
            c = { eta = secs, at = now, expires = now + math.max(120, math.min(secs * 2, 900)) }
            b.coming[short] = c
            SM:Print((secs > 0 and L.ETA_COMING or L.ETA_COMING_UNKNOWN):format(short, Eta.FormatTime(secs)))
            if SM.Contacts then SM.Contacts:Add(sender, "beacon", DisplayName(b)) end
            if SM.Peon then SM.Peon:Say("coming") end
        end
        self:CheckComers()
        self:WatchComers()
    elseif kind == "A" then
        local id = tonumber(text:match("^A;2;(%d+)$"))
        local b = id and SM.Beacon:FindOwn(id)
        if not b then return end
        b.coming = b.coming or {}
        local c = b.coming[short]
        if not c then
            if CountComing(b) >= MAX_COMING then return end
            c = { eta = 0, at = now, expires = now + 120 }
            b.coming[short] = c
        end
        if c.alertAt and (now - c.alertAt) < ALERT_MIN_INTERVAL then return end
        c.alertAt, c.near, c.expires = now, true, now + 120
        self:ArrivedNotice(b, short, c)
    end
end

-- Kurz vor der Ankunft: eine Chatzeile und ein leiser Ton (bei Sprachchat-Beacons mit Erinnerung)
function Eta:ArrivedNotice(b, name, c)
    SM:Print(L.ETA_ARRIVED:format(name))
    PlayAlertSound("TELL_MESSAGE", 3081)
    if not c.voiceHint and SM.Social.VoiceLevel(b.voice) > 0 then
        c.voiceHint = true
        SM:Print(SM.Social.VoiceLevel(b.voice) == 2 and L.ETA_VOICE_2 or L.ETA_VOICE)
    end
end

-- Zeilen fürs Tooltip deines Beacons: wer ist auf dem Weg?
function Eta:ComingLines(b)
    local lines = {}
    if not b.coming then return lines end
    local now = GetTime()
    local names = {}
    for name, c in pairs(b.coming) do
        if c.expires > now then names[#names + 1] = name else b.coming[name] = nil end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local c = b.coming[name]
        local rest = Remaining(c, now)
        if c.near then
            lines[#lines + 1] = L.TT_COMING_NEAR:format(name)
        elseif rest then
            lines[#lines + 1] = L.TT_COMING_ROW:format(name, Eta.FormatTime(rest))
        else
            lines[#lines + 1] = L.TT_COMING_UNKNOWN:format(name)
        end
    end
    return lines
end

---------------------------------------------------------------------------
-- Modul-Lebenszyklus, Befehle
---------------------------------------------------------------------------
function Eta:OnDisable()
    self:Stop(true)
    if self.watcher then self.watcher:Cancel(); self.watcher = nil end
end

SM:RegisterCallback("BEACON_REMOVED", function(b)
    if Eta.enabled and Eta.target == b then
        Eta:Stop(true)
        SM:Print(L.NAV_GONE)
    end
end)

-- Größe des Pfeils (Einstellungen: Karte & Weg)
function Eta:ApplyArrowScale()
    if self.arrow then self.arrow:SetScale((SM.db.nav.arrowScale or 100) / 100) end
end

SM:RegisterPosition(function() return SM.db.nav end, function() return Eta.arrow end,
    function(f) f:SetPoint("TOP", UIParent, "TOP", 0, ARROW_TOP) end)
