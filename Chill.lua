local ADDON, SM = ...
local L = SM.L
local M = SM.Media

-- Chill-Modus: Lagerfeuer-Musik, Angel-Trigger, Aussichtspunkte und der Warte-Tipp.
--   * Musik nur aus dem Spiel selbst (im Addon liegt keine Musik): "Lagerfeuer" = ruhige
--     Draußen-Musik (Wald, Ebene, Zauberwald, Gebirge), "Gasthaus" = die Gasthaus-Stücke.
--     Gespielt wird mit PlayMusic über die Datei-Nummer: die Spielmusik pausiert, StopMusic
--     bringt sie zurück. Lautstärke = Musik-Lautstärke des Spiels.
--   * Musik startet NIE von selbst (test8b): beim Angeln, beim Wiederkommen an einen gemerkten
--     Ort und am Lagerfeuer fragt ein kleiner Zettel unten rechts, ob du Musik hören magst -
--     insgesamt einmal pro Spielsitzung. Zwei Minuten ohne Angeln (und weg vom Ort / Feuer)
--     endet die so gestartete Musik wieder.
--   * Angeln: beim Auswerfen ein Lore-Häppchen (und einmal der Musik-Zettel).
--   * Aussichtspunkte: "Hier merken" im Tab Orte merkt sich deinen Standort. Kommst du wieder
--     hin, gibt es Lore (und einmal der Musik-Zettel). Direkt nach dem Merken nicht.
--   * Warte-Ideen: 90 Sekunden nach deinem Treffpunkt, wenn noch niemand kommt, steht im Tab
--     Treffpunkte eine Zeile mit einer Idee in der Nähe und "Weg zeigen" (test8b, kein Fenster mehr).
-- "Sei leise!" beendet die Musik sofort und verhindert jeden automatischen Start.
local Chill = SM:NewModule("chill")

-- Musik vom Zettel läuft weiter, bis du eine Hauptstadt oder Instanz betrittst (test8b)
local CAPITALS = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
Chill.CAPITALS = CAPITALS
local WATCH_TICK = 5            -- Sek.: Prüfung für Aussichtspunkte und Auto-Stopp
local SPOT_YARDS = 25           -- so nah gilt man als "am Aussichtspunkt"
local SPOT_REPEAT = 600         -- Sek.: derselbe Aussichtspunkt meldet sich frühestens wieder
local MAX_SPOTS = 50
local WAIT_TIP_DELAY = 90       -- Sek. nach dem eigenen Beacon
local WAIT_TIP_MAX_YARDS = 600  -- Aussichtspunkte weiter weg werden nicht vorgeschlagen

-- Angeln (Zauber-IDs der verschiedenen Ränge/Erweiterungen)
local FISHING_IDS = { [7620] = true, [7731] = true, [7732] = true, [18248] = true, [33095] = true,
                      [51294] = true, [88868] = true, [110410] = true, [131474] = true, [131490] = true }

Chill.playing = false
Chill.index = 0
Chill.auto = false
Chill.lastFish = -math.huge
Chill.lastNear = -math.huge
Chill.spotSeen = {}
Chill.spotHold = {}     -- gerade gemerkte Orte: melden sich erst, wenn du einmal weg warst

---------------------------------------------------------------------------
-- Musik: zwei Quellen, beide aus dem Spiel selbst (Blizzards Dateien, abgespielt über ihre
-- Datei-Nummer aus der Dateiliste des Spiels). Es sind Stücke, die es seit Classic in jedem
-- Client gibt. Sie laufen in Schleife, bis du "Weiter" drückst.
--   camp   = ruhige Draußen-Musik: Wald (Elwynn), Ebene (Mulgore), Zauberwald (Eschental), Gebirge
--   tavern = Gasthaus der Allianz und der Horde
-- g = Name der Gruppe, n = Teil
---------------------------------------------------------------------------
Chill.SOURCES = { "camp", "tavern" }

Chill.CAMP = {
    { id = 53492, g = "forest", n = 1 }, { id = 53493, g = "forest", n = 2 }, { id = 53494, g = "forest", n = 3 },
    { id = 53495, g = "forestnight", n = 1 }, { id = 53496, g = "forestnight", n = 2 },
    { id = 53680, g = "plains", n = 1 }, { id = 53681, g = "plains", n = 2 },
    { id = 53682, g = "plainsnight", n = 1 }, { id = 53683, g = "plainsnight", n = 2 },
    { id = 53453, g = "enchanted", n = 1 }, { id = 53454, g = "enchanted", n = 2 }, { id = 53455, g = "enchanted", n = 3 },
    { id = 53577, g = "mountain", n = 1 }, { id = 53580, g = "mountainnight", n = 1 },
}

Chill.TAVERN = {
    { id = 53737, g = "alliance", n = 1 }, { id = 53738, g = "alliance", n = 2 },
    { id = 53744, g = "horde", n = 1 }, { id = 53745, g = "horde", n = 2 }, { id = 53746, g = "horde", n = 3 },
}
local ROMAN = { "I", "II", "III" }

function Chill:Source()
    return SM.db.music.source == "tavern" and "tavern" or "camp"
end

function Chill:Playlist(src)
    src = src or self:Source()
    local list = {}
    local function add(t, prefix)
        list[#list + 1] = { file = t.id, title = L[prefix .. t.g] .. (t.n and (" " .. ROMAN[t.n]) or "") }
    end
    if src == "tavern" then
        -- Gasthaus der eigenen Fraktion zuerst, mit "Weiter" kommt danach die andere
        local own = self:OwnTavern()
        for _, t in ipairs(self.TAVERN) do if t.g == own then add(t, "TAVERN_") end end
        for _, t in ipairs(self.TAVERN) do if t.g ~= own then add(t, "TAVERN_") end end
    else
        for _, t in ipairs(self.CAMP) do add(t, "CAMP_MUSIC_") end
    end
    return list
end

-- "alliance" oder "horde" (passend zu den Gruppen in Chill.TAVERN), sonst nil
function Chill:OwnTavern()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if faction == "Alliance" then return "alliance" elseif faction == "Horde" then return "horde" end
    return nil
end

-- Zufälliger Start: beim Gasthaus nur unter den Stücken der eigenen Fraktion (die stehen vorn)
function Chill:RandomStart()
    local n = #self:Playlist()
    if n == 0 then return 1 end
    if self:Source() == "tavern" then
        local own, k = self:OwnTavern(), 0
        for _, t in ipairs(self.TAVERN) do if t.g == own then k = k + 1 end end
        if k > 0 then return math.random(k) end
    end
    return math.random(n)
end

function Chill:SetSource(src)
    if src ~= "tavern" then src = "camp" end
    SM.db.music.source = src
    self.index = 0
    if self.playing then return self:Play(self:RandomStart(), false) end
    self:RefreshPlayer()
    return true
end

-- Spielt Lied Nummer index (1 = erstes) der gewählten Quelle. auto = von selbst gestartet
-- (Angeln, Aussichtspunkt, Lagerfeuer).
function Chill:Play(index, auto)
    if not self.enabled then return false, L.MUSIC_OFF_MOD end
    if SM:IsSilent() then return false, L.MUSIC_SILENT end
    if SM:MusicMode() == "off" then return false, L.MUSIC_OFF_SETTING end
    if auto and not SM:MusicAllowed(true) then return false, L.MUSIC_CLICK_ONLY end
    local list = self:Playlist()
    if #list == 0 then return false, L.MUSIC_NONE end
    index = index or (self.index > 0 and self.index) or 1
    if index > #list then index = 1 elseif index < 1 then index = #list end
    local track = list[index]
    if type(PlayMusic) ~= "function" then return false, L.MUSIC_FAIL end
    local okCall, willPlay = pcall(PlayMusic, track.file)
    if not okCall or willPlay == false then
        -- Stück spielt in diesem Client nicht: fürs Entwickler-Feedback merken
        if SM.Feedback and SM.Feedback.enabled then SM.Feedback:NoteMusic(track.file) end
        return false, L.MUSIC_FAIL
    end
    self.playing, self.index, self.track = true, index, track
    self.auto = auto and true or false
    if self.auto then self.autoMap = self:CurrentMap() end
    -- Ist die Spielmusik in den Soundeinstellungen aus, hört man auch diese Musik nicht: einmal Bescheid sagen.
    if not self.cvarHint and type(GetCVar) == "function" and GetCVar("Sound_EnableMusic") == "0" then
        self.cvarHint = true
        SM:Print(L.MUSIC_CVAR_OFF)
    end
    -- Nach dem Ende das nächste Lied; Stücke ohne bekannte Länge laufen in Schleife, bis "Weiter".
    local token = {}
    self.token = token
    if track.length then
        C_Timer.After(track.length + 1, function()
            if self.token == token and self.playing then self:Play(self.index + 1, self.auto) end
        end)
    end
    self:ShowPlayer()
    SM:Fire("MUSIC_CHANGED")
    return true, L.MUSIC_PLAYING:format(track.title)
end

-- Von selbst starten: ein zufälliges Stück der gewählten Quelle
function Chill:PlayAuto()
    return self:Play(self:RandomStart(), true)
end

function Chill:Stop()
    local was = self.playing
    self.playing, self.auto, self.token, self.track, self.autoMap = false, false, nil, nil, nil
    if was and type(StopMusic) == "function" then pcall(StopMusic) end -- Spielmusik kommt zurück
    if self.player then
        -- von selbst aufgegangen: wieder zu; selbst geöffnet: bleibt offen
        if self.manual then self:RefreshPlayer() else self.player:Hide() end
    end
    if self.mini then self.mini:Hide(); if SM.Note and SM.Note.frame and SM.Note.frame:IsShown() then SM.Note:Place() end end
    if was then SM:Fire("MUSIC_CHANGED") end
    return was
end

function Chill:Toggle()
    if self.playing then
        self:Stop()
        return true, L.MUSIC_STOPPED
    end
    return self:Play(nil, false)
end

-- Weiter / Zurück: Musik vom Lagerfeuer o. ä. bleibt dabei "Anlass-Musik" (endet in Hauptstadt/Instanz)
function Chill:Skip(delta)
    local keep, map = self.auto, self.autoMap
    local ok, msg = self:Play(self.index + delta, false)
    if ok and keep then self.auto, self.autoMap = true, map end
    return ok, msg
end
function Chill:Next() return self:Skip(1) end
function Chill:Prev() return self:Skip(-1) end

---------------------------------------------------------------------------
-- Musik-Player: öffnest du selbst (/sm musik, Einstellungen > Musik) oder er erscheint,
-- solange Musik läuft (abschaltbar). Oben die Quelle, unten Zurück / Abspielen-Stopp / Weiter.
-- Das X schließt nur das Fenster - die Musik läuft weiter, bis du "Stopp" drückst.
-- "Stopp" beendet nur die Musik; der Player bleibt offen.
---------------------------------------------------------------------------
local PLAYER_W, PLAYER_H = 300, 84

-- Tooltips des Players nie über den Player legen: steht er oben am Bildschirm, kommt der
-- Tooltip darunter, sonst darüber (vorher verdeckte er die Knöpfe).
local function TipOwner(frame)
    local top, screen = frame:GetTop(), UIParent:GetHeight()
    local below = top and screen and top * (frame:GetEffectiveScale() or 1) > screen * (UIParent:GetEffectiveScale() or 1) * 0.6
    GameTooltip:SetOwner(frame, below and "ANCHOR_BOTTOM" or "ANCHOR_TOP", 0, below and -4 or 4)
end

function Chill:BuildPlayer()
    if self.player then return end
    local UI = SM.UI
    local f = CreateFrame("Frame", "SocializeMeForeverPlayer", UIParent)
    self.player = f
    f:SetSize(PLAYER_W, PLAYER_H)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(fr) SM.UI.DragStart(fr) end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relPoint, x, y = frame:GetPoint()
        local m = SM.db.music
        m.point, m.relPoint, m.x, m.y = point, relPoint, x, y
    end)
    local m = SM.db.music
    if m.point then
        f:SetPoint(m.point, UIParent, m.relPoint or m.point, m.x or 0, m.y or 0)
    else
        f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -260, 180)
    end

    local panel = UI.Panel(f, nil, M.colors.wood)
    panel:SetAllPoints(f)
    UI.AddGrain(panel, PLAYER_W, PLAYER_H, "ARTWORK")

    local tx = M.wood.text
    f.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -7)
    f.title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -26, -7)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.title:SetTextColor(tx[1], tx[2], tx[3])
    f.title:SetShadowOffset(0, 0)

    -- Quelle
    f.sources = {}
    for i, src in ipairs(Chill.SOURCES) do
        local b = UI.Button(panel, nil, 92, 20, L["MUSIC_SRC_" .. src])
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", 8 + (i - 1) * 96, -24)
        b:SetScript("OnClick", function()
            local ok, msg = Chill:SetSource(src)
            if not ok and msg then SM:Print(msg) end
        end)
        b:SetScript("OnEnter", function()
            TipOwner(f)
            GameTooltip:AddLine(L["MUSIC_SRC_" .. src], 1, 0.82, 0)
            GameTooltip:AddLine(L["MUSIC_SRC_TT_" .. src], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.sources[src] = b
    end

    local function Btn(text, w, x, fn)
        local b = UI.Button(panel, nil, w, 20, text)
        b:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", x, 7)
        b:SetScript("OnClick", fn)
        return b
    end
    f.prev = Btn(L.MUSIC_PREV, 80, 8, function() Chill:Prev() end)
    f.stop = Btn(L.MUSIC_STOP, 116, 92, function()
        if Chill.playing then
            Chill.manual = true   -- Stopp im Player: das Fenster bleibt offen (schließen geht mit X)
            Chill:Stop()
        else
            local ok, msg = Chill:Play(nil, false)
            if not ok then SM:Print(msg) end
        end
    end)
    f.next = Btn(L.MUSIC_NEXT, 80, 212, function() Chill:Next() end)

    local close = UI.CloseButton(panel, function() Chill:HidePlayer() end)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -3)
    f.close = close

    f:SetScript("OnEnter", function(frame)
        TipOwner(frame)
        GameTooltip:AddLine(L.MUSIC_TT_TITLE, 1, 0.82, 0)
        GameTooltip:AddLine(L.MUSIC_TT_DRAG, 1, 1, 1)
        GameTooltip:AddLine(L.MUSIC_TT_CLOSE, 1, 1, 1, true)
        GameTooltip:AddLine(L.MUSIC_TT_MINIMAP, 1, 1, 1)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
end

function Chill:RefreshPlayer()
    local f = self.player
    if not f then return end
    local t = self.playing and self.track
    f.title:SetText(t and L.MUSIC_NOW:format(t.title) or L.MUSIC_IDLE)
    f.stop:SetText(self.playing and L.MUSIC_STOP or L.MUSIC_PLAY)
    local src = self:Source()
    for s, b in pairs(f.sources) do
        if s == src then b:LockHighlight() else b:UnlockHighlight() end
    end
    if self.playing then f.prev:Enable(); f.next:Enable() else f.prev:Disable(); f.next:Disable() end
end

-- manual = selbst geöffnet (bleibt auch ohne Musik offen). Startet Musik von selbst bzw. über
-- den Zettel, kommt nur eine kleine Zeile "Es läuft: ... [Stopp]" (test8b) - der ganze Player
-- nur, wenn du ihn selbst öffnest (/sm musik, Optionen) oder er schon offen ist.
function Chill:ShowPlayer(manual)
    if manual then self.manual = true end
    if manual or self.manual or (self.player and self.player:IsShown()) then
        if self.mini then self.mini:Hide(); if SM.Note and SM.Note.frame and SM.Note.frame:IsShown() then SM.Note:Place() end end
        self:BuildPlayer()
        self:RefreshPlayer()
        self.player:Show()
        return
    end
    if not SM.db.music.player then return end
    self:ShowMini()
end

-- Die kleine Zeile: was läuft, und ein Knopf zum Stoppen. Maus darüber erklärt, wie man die
-- Musik stoppt und wie der ganze Player aufgeht.
function Chill:BuildMini()
    if self.mini then return self.mini end
    local UI = SM.UI
    local f = CreateFrame("Frame", "SocializeMeForeverMusicMini", UIParent)
    self.mini = f
    f:SetSize(340, 26)
    f:SetFrameStrata("HIGH") -- test8f: wie der Zettel, damit nichts die Klicks abfängt
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    SM:MakeMovable(f, function() return SM.db.musicMini end)
    local panel = UI.Panel(f, nil, M.colors.wood)
    panel:SetAllPoints(f)
    local tx = M.wood.text
    f.text = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("LEFT", panel, "LEFT", 8, 0)
    f.text:SetPoint("RIGHT", panel, "RIGHT", -122, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetWordWrap(false)
    f.text:SetTextColor(tx[1], tx[2], tx[3])
    f.text:SetShadowOffset(0, 0)
    -- [<] [Stopp] [>] (test8e: ganz kleine Knöpfe für Zurück / Weiter)
    f.next = UI.Button(panel, "SocializeMeForeverMusicMiniNext", 22, 20, ">")
    f.next:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
    f.next:SetScript("OnClick", function() Chill:Next() end)
    f.stop = UI.Button(panel, "SocializeMeForeverMusicMiniStop", 66, 20, L.MUSIC_STOP)
    f.stop:SetPoint("RIGHT", f.next, "LEFT", -3, 0)
    f.stop:SetScript("OnClick", function() Chill:Stop() end)
    f.prev = UI.Button(panel, "SocializeMeForeverMusicMiniPrev", 22, 20, "<")
    f.prev:SetPoint("RIGHT", f.stop, "LEFT", -3, 0)
    f.prev:SetScript("OnClick", function() Chill:Prev() end)
    for b, label in pairs({ [f.prev] = L.MUSIC_PREV, [f.next] = L.MUSIC_NEXT }) do
        b:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:AddLine(label, 1, 0.82, 0)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local function Tip(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        GameTooltip:AddLine(L.MUSIC_TT_TITLE, 1, 0.82, 0)
        GameTooltip:AddLine(L.MUSIC_MINI_TT, 1, 1, 1, true)
        GameTooltip:Show()
    end
    f:SetScript("OnEnter", Tip)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.stop:SetScript("OnEnter", Tip)
    f.stop:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
    return f
end

function Chill:ShowMini()
    local f = self:BuildMini()
    local t = self.playing and self.track
    f.text:SetText(t and L.MUSIC_NOW:format(t.title) or L.MUSIC_IDLE)
    self:PlaceMini()
    f:Show()
    -- ein offener Zettel rückt über die Zeile
    if SM.Note and SM.Note.frame and SM.Note.frame:IsShown() then SM.Note:Place() end
end

-- test8b: unten rechts (ca. 2 cm Abstand) - oder dort, wohin du sie geschoben hast
function Chill:PlaceMini()
    local f = self.mini
    if not f then return end
    f:ClearAllPoints()
    local t = SM.db.musicMini or {}
    if t.point then
        f:SetPoint(t.point, UIParent, t.relPoint or t.point, t.x or 0, t.y or 0)
    else
        SM:PlaceCorner(f)
    end
end

function Chill:HidePlayer()
    self.manual = false
    if self.player then self.player:Hide() end
    -- jedes Mal: sonst weiß man beim zweiten Schließen nicht mehr, wie man die Musik beendet
    if self.playing then
        SM:Print(L.MUSIC_CLOSED_HINT)
        -- test8f: läuft die Musik weiter, kommt die kleine Zeile mit Stopp zurück
        if SM.db.music.player then self:ShowMini() end
    end
end

-- /sm musik: Player auf/zu
function Chill:TogglePlayer()
    if not self.enabled then SM:Print(L.MUSIC_OFF_MOD) return end
    if self.player and self.player:IsShown() then self:HidePlayer() else self:ShowPlayer(true) end
end

---------------------------------------------------------------------------
-- Musik-Zettel (test8b): Musik startet nie von selbst. Der Zettel (UI\Note.lua) an der Stelle des
-- Players (unten rechts) fragt, ob du Musik hören magst - insgesamt einmal pro Spielsitzung,
-- beim Angeln, beim Wiederkommen an einen gemerkten Ort oder am Lagerfeuer. Nach 20 Sekunden
-- verschwindet er von selbst (solange die Maus nicht darauf ist). Am Lagerfeuer bietet derselbe
-- Zettel auch eine Geschichte an. Schalter: Optionen > "Lagerfeuer-Musik anbieten".
---------------------------------------------------------------------------
Chill.offered = false

---------------------------------------------------------------------------
-- Musik vom Zettel (test8b): läuft weiter, bis du eine Hauptstadt oder Instanz betrittst -
-- dort soll wieder die Musik des Spiels laufen. Der Zettel sagt das in einem Satz.
---------------------------------------------------------------------------
function Chill:CurrentMap()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

-- Musik gehört zu einem Anlass (Angeln, Ort, Lagerfeuer): merken, wo sie anfing
function Chill:MarkOccasion()
    self.auto = true
    self.autoMap = self:CurrentMap()
end

function Chill:CheckAutoStop()
    if not (self.playing and self.auto) then return false end
    local inInstance = type(IsInInstance) == "function" and IsInInstance()
    local map = self:CurrentMap()
    if inInstance or (map and CAPITALS[map] and map ~= self.autoMap) then
        self:Stop()
        return true
    end
    return false
end

SM:RegisterEvent(Chill, "ZONE_CHANGED_NEW_AREA", function()
    if Chill.enabled then C_Timer.After(2, function() Chill:CheckAutoStop() end) end
end)

-- Der Zettel selbst steckt in UI\Note.lua (ein Zettel für alles). Hier nur kurze Wege dorthin.
function Chill:ShowNote(text, buttons, key)
    SM.Note:Display({ key = key or "music", text = text, buttons = buttons, tip = L.MUSIC_OFFER_TT })
    return SM.Note.frame
end

function Chill:HideNote()
    if SM.Note then SM.Note:Hide("addon") end
end

-- Musik für den Anlass (Angeln, Ort): angeklickt, also gilt "Nur auf Klick" nicht als Hindernis.
-- Sie endet wieder, wenn du nicht mehr angelst und weg vom Ort bist (wie früher von selbst).
function Chill:PlayOccasion()
    local ok, msg = self:Play(self:RandomStart(), false)
    if ok then self:MarkOccasion() else SM:Print(msg) end
    return ok
end

-- Einmal pro Spielsitzung fragen. occasion: "fish", "spot", "campsit", "camplight".
-- Gibt true zurück, wenn gefragt wird (auch wenn der Zettel erst nach dem Kampf kommt).
-- Einmal pro Spielsitzung fragen gilt nur für Angeln und Aussichtspunkte. Am Lagerfeuer (Hinsetzen,
-- Anzünden) gibt es den Musik-Knopf immer, solange keine Musik läuft (test8d).
function Chill:CanOffer(occasion)
    local camp = (occasion == "campsit" or occasion == "camplight")
    if not self.enabled or self.playing or (self.offered and not camp) then return false end
    if SM:IsDND() or not SM:MusicAllowed(true) then return false end
    local m = SM.db.music
    if (occasion == "fish" and not m.onFishing) or (occasion == "spot" and not m.onSpot)
        or ((occasion == "campsit" or occasion == "camplight") and m.onCampfire == false) then
        return false
    end
    return true
end

function Chill:Offer(occasion)
    if not self:CanOffer(occasion) then return false end
    self.offered = true
    local function Camp()
        if SM.Campfire and SM.Campfire.CampMusic then SM.Campfire:CampMusic() else Chill:PlayOccasion() end
    end
    local text, buttons
    -- in einem Satz, wann die Musik von selbst endet
    local hint = L.MUSIC_UNTIL
    if occasion == "campsit" then
        text = L.CAMP_SIT_ASK
        buttons = { { L.CAMP_BTN_MUSIC, Camp }, { L.CAMP_BTN_STORY, function() SM.LoreReader:Open() end } }
    elseif occasion == "camplight" then
        text = L.MUSIC_OFFER
        buttons = { { L.MUSIC_PLAY, Camp } }
    else
        text = L.MUSIC_OFFER
        buttons = { { L.MUSIC_PLAY, function() Chill:PlayOccasion() end } }
    end
    SM.Note:Ask("musicoffer", text, buttons, { chat = L.MUSIC_OFFER_CHAT, tip = L.MUSIC_OFFER_TT, hint = hint })
    return true
end

---------------------------------------------------------------------------
-- Angeln
---------------------------------------------------------------------------
local fishingName
function Chill:IsFishing(spellID)
    if FISHING_IDS[spellID] then return true end
    if not fishingName and type(GetSpellInfo) == "function" then fishingName = GetSpellInfo(7620) end
    local name = spellID and type(GetSpellInfo) == "function" and GetSpellInfo(spellID)
    return fishingName ~= nil and name == fishingName
end

function Chill:OnFishing()
    self.lastFish = GetTime()
    if SM.Feedback and SM.Feedback.enabled then SM.Feedback:NoteFishing() end
    if SM.Lore and SM.Lore.enabled then SM.Lore:Offer("fish") end
    self:Offer("fish")
end

---------------------------------------------------------------------------
-- Aussichtspunkte
---------------------------------------------------------------------------
local function PlayerSpot()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y
    if pos and pos.GetXY then x, y = pos:GetXY() end
    if not x or not y or (x == 0 and y == 0) then return nil end
    return mapID, x, y
end

-- Name in der Sprache des Addons (ZoneNames.lua), sonst wie im Spiel
local function ZoneName(mapID)
    return SM:MapName(mapID)
end

function Chill:AddSpot(name)
    local mapID, x, y = PlayerSpot()
    if not mapID then return false, L.ERR_NO_POS end
    return self:AddSpotAt(name, mapID, x, y)
end

-- Name eines eigenen Orts. Ohne selbst getippten Namen wird er bei jeder Anzeige neu in der
-- aktuellen Addon-Sprache gebildet ("<Zone> Aussichtspunkt 2" / "<zone> viewpoint 2"),
-- damit er nach einem Sprachwechsel nicht in der alten Sprache stehen bleibt.
function Chill:SpotName(s)
    if not s then return "" end
    if s.name and s.name ~= "" then return s.name end
    return L.SPOT_DEFAULT:format(ZoneName(s.mapID), s.n or 1)
end

-- Ältere Versionen haben den Standardnamen fest gespeichert: solche Namen wieder freigeben.
local AUTO_NAMES = { "^.- Aussichtspunkt (%d+)$", "^.- viewpoint (%d+)$", "^.- 观景点 (%d+)$" }
function Chill:FreeAutoNames()
    for _, sp in ipairs(SM.db.spots or {}) do
        if type(sp.name) == "string" then
            for _, pat in ipairs(AUTO_NAMES) do
                local n = sp.name:match(pat)
                if n then sp.name, sp.n = nil, tonumber(n); break end
            end
        end
    end
end

-- Ort an einer bestimmten Stelle merken (auch für eingefügte, geteilte Orte)
function Chill:AddSpotAt(name, mapID, x, y)
    local spots = SM.db.spots
    if #spots >= MAX_SPOTS then return false, L.SPOT_FULL:format(MAX_SPOTS) end
    name = tostring(name or ""):gsub("|", ""):gsub("%c", "")
    name = name:match("^%s*(.-)%s*$")
    local spot = { mapID = mapID, x = math.floor(x * 10000 + 0.5) / 10000, y = math.floor(y * 10000 + 0.5) / 10000 }
    if name == "" then spot.n = #spots + 1 else spot.name = SM.TrimChars(name, 40) end
    spots[#spots + 1] = spot
    -- gerade gemerkt: du stehst ja schon da - keine "angekommen"-Meldung und kein Musik-Zettel
    -- (test8b). Erst wenn du einmal weg warst und wiederkommst.
    self.spotHold[spot.mapID .. ":" .. spot.x .. ":" .. spot.y] = true
    return true, L.SPOT_ADDED:format(self:SpotName(spot))
end

function Chill:RemoveSpot(i)
    local s = SM.db.spots[i]
    if not s then return false end
    table.remove(SM.db.spots, i)
    return true, s
end

-- Abstand zu einem Aussichtspunkt in Yards (nil = unbekannt / andere Karte)
function Chill:SpotDistance(spot)
    if not SM.Eta then return nil end
    -- Die Weltkoordinaten nicht am gespeicherten Punkt ablegen (SavedVariables sauber halten)
    local tmp = { mapID = spot.mapID, x = spot.x, y = spot.y }
    return (SM.Eta:Distance(tmp))
end

-- Der nächste Aussichtspunkt (für den Warte-Tipp)
function Chill:NearestSpot(maxYards)
    local best, bestD
    for _, s in ipairs(SM.db.spots) do
        local d = self:SpotDistance(s)
        if d and d <= maxYards and (not bestD or d < bestD) then best, bestD = s, d end
    end
    return best, bestD
end

function Chill:Watch()
    local now = GetTime()
    for _, s in ipairs(SM.db.spots) do
        local d = self:SpotDistance(s)
        local key = s.mapID .. ":" .. s.x .. ":" .. s.y
        if d and d > SPOT_YARDS then self.spotHold[key] = nil end
        if d and d <= SPOT_YARDS then
            self.lastNear = now
            if not self.spotHold[key] and (not self.spotSeen[key] or (now - self.spotSeen[key]) >= SPOT_REPEAT) then
                self.spotSeen[key] = now
                if not SM:IsDND() then SM:Print(L.SPOT_ARRIVED:format(self:SpotName(s))) end
                if SM.Lore and SM.Lore.enabled then SM.Lore:Offer("spot", s.mapID) end
                self:Offer("spot")
            end
        end
    end
    self:CheckAutoStop()
end

---------------------------------------------------------------------------
-- Warte-Tipp nach dem eigenen Beacon: bis zu drei Ideen, was du in der Wartezeit in der Nähe
-- tun kannst - reparieren (nur wenn die Ausrüstung es braucht), ein schöner Ort, ein Angelplatz,
-- dein Klassenlehrer (bei gerader Stufe), Briefkasten, Angellehrer, Auktionshaus, Gasthaus oder
-- Flugmeister. Die Punkte kommen aus Modules\WaitData.lua (in Hauptstädten und wichtigen Orten)
-- und aus dem, was sich das Addon nur bei dir merkt (Modules\Places.lua, es wird nichts
-- gesendet). Jeder Punkt hat "Weg zeigen". Ist nichts in der Nähe, gibt es allgemeine Ideen.
-- Unten: "Kurz plaudern" (Tab Instant) und Musik.
---------------------------------------------------------------------------
local TIP_ROWS = 3               -- so viele Ideen werden ausgesucht (durchblättern per Klick)
local REPAIR_BELOW = 0.5        -- unter 50 % beim schlechtesten Teil schlagen wir Reparieren vor

-- Zustand der Ausrüstung: das schlechteste Teil (0 bis 1), nil wenn unbekannt
function Chill.Durability()
    if type(GetInventoryItemDurability) ~= "function" then return nil end
    local lowest
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local p = cur / max
            if not lowest or p < lowest then lowest = p end
        end
    end
    return lowest
end

local function Point(mapID, x, y, title) return { mapID = mapID, x = x, y = y, title = title } end

-- Die Ideen für den Warte-Tipp: { icon, text, point (oder nil) }, höchstens drei
local EXTRA = { "mail", "fishtrainer", "auction", "inn", "flight" }

function Chill:WaitIdeas()
    local ideas = {}
    local function add(icon, text, point)
        if #ideas < TIP_ROWS then ideas[#ideas + 1] = { icon = icon, text = text, point = point } end
    end
    local P = SM.Places
    local Fmt = SM.Eta.FormatDistance
    local pois = (P and P.enabled) and P:NearbyPOIs(WAIT_TIP_MAX_YARDS) or {}
    local function nearest(kind)
        for _, e in ipairs(pois) do if e.poi == kind and e.dist then return e end end
    end
    local poiIcon = P and P.POI_ICON or {}
    local catIcon = P and P.CAT_ICON or {}
    local function addPoi(kind, text)
        local e = nearest(kind)
        if e then add(poiIcon[kind], text:format(Fmt(e.dist)), Point(e.mapID, e.x, e.y, L["POI_" .. kind])) end
        return e
    end

    -- 1) Reparieren - nur wenn nötig
    local dur = Chill.Durability()
    if dur and dur < REPAIR_BELOW then
        local pct = math.floor(dur * 100 + 0.5)
        local r = nearest("repair")
        if r then
            add(poiIcon.repair, L.WAIT_REPAIR:format(pct, Fmt(r.dist)), Point(r.mapID, r.x, r.y, L.POI_repair))
        else
            add(poiIcon.repair, L.WAIT_REPAIR_ANY:format(pct))
        end
    end
    -- 2) schöne Orte und Angelplätze in der Nähe
    local mapID = P and P.enabled and P:PlayerPos()
    if mapID then
        local view, fish
        for _, it in ipairs(P:ForZone(mapID, "all")) do
            if it.kind == "place" and it.dist and it.dist <= WAIT_TIP_MAX_YARDS then
                if it.cat == "fish" then fish = fish or it else view = view or it end
            end
        end
        if view then add(catIcon[view.cat] or catIcon.view, L.WAIT_PLACE:format(view.name, Fmt(view.dist)), Point(view.mapID, view.x, view.y, view.name)) end
        if fish then add(catIcon.fish, L.WAIT_FISHSPOT:format(fish.name, Fmt(fish.dist)), Point(fish.mapID, fish.x, fish.y, fish.name)) end
    else
        -- ohne Orte-Modul: wenigstens deine eigenen Aussichtspunkte
        local spot, d = self:NearestSpot(WAIT_TIP_MAX_YARDS)
        if spot then
            local name = self:SpotName(spot)
            add(catIcon.view, L.WAIT_PLACE:format(name, Fmt(d)), Point(spot.mapID, spot.x, spot.y, name))
        end
    end
    -- 3) Klassenlehrer - neue Fähigkeiten gibt es auf jeder geraden Stufe
    local level = type(UnitLevel) == "function" and tonumber(UnitLevel("player")) or 0
    if level > 1 and level % 2 == 0 then addPoi("classtrainer", L.WAIT_CLASSTRAINER) end
    addPoi("proftrainer", L.WAIT_PROFTRAINER)
    -- 4) noch etwas in der Nähe - in zufälliger Reihenfolge, damit es nicht immer dasselbe ist
    local order = {}
    for i, k in ipairs(EXTRA) do order[i] = k end
    for i = #order, 2, -1 do
        local j = math.random(i)
        order[i], order[j] = order[j], order[i]
    end
    for _, kind in ipairs(order) do addPoi(kind, L["WAIT_" .. kind:upper()]) end
    -- 5) allgemeine Ideen
    add(poiIcon.proftrainer, L.WAIT_PROF)
    add(catIcon.fish, L.WAIT_FISH)
    return ideas
end

-- Warte-Ideen (test8b): statt eines Fensters eine Zeile im Tab Treffpunkte (UI\Window.lua),
-- solange dein Treffpunkt läuft und noch niemand kommt. Die Ideen werden einmal ausgesucht.
function Chill:StartWaitIdeas(b)
    if not self.enabled or not SM.db.music.waitTip then return false end
    if not b or b.waitIdeas or SM.Beacon.cache[b.key] ~= b then return false end
    if b.coming and next(b.coming) then return false end -- es kommt schon jemand
    local ideas = self:WaitIdeas()
    if #ideas == 0 then return false end
    b.waitIdeas, b.waitIdx = ideas, 1
    SM:Fire("WAIT_IDEAS", b)
    return true
end

-- Die Idee, die gerade dran ist (und der Treffpunkt dazu) - oder nil
function Chill:CurrentWaitIdea()
    if not (SM.Beacon and SM.Beacon.cache) then return nil end
    for _, b in pairs(SM.Beacon.cache) do
        if b.own and b.waitIdeas and not (b.coming and next(b.coming)) then
            return b.waitIdeas[b.waitIdx or 1], b
        end
    end
    return nil
end

function Chill:NextWaitIdea()
    local _, b = self:CurrentWaitIdea()
    if b then b.waitIdx = (b.waitIdx or 1) % #b.waitIdeas + 1 end
end

---------------------------------------------------------------------------
-- Stufenaufstieg: auf jeder geraden Stufe gibt es neue Fähigkeiten beim Klassenlehrer.
-- Eine Chatzeile mit Entfernung; /sm lehrer zeigt den Weg (Pfeil + Laufzeit).
---------------------------------------------------------------------------
function Chill:NearestClassTrainer()
    local P = SM.Places
    if not (P and P.enabled) then return nil end
    local best
    for _, e in ipairs(P:NearbyPOIs(nil)) do
        if e.poi == "classtrainer" and e.dist and (not best or e.dist < best.dist) then best = e end
    end
    return best
end

function Chill:OnLevelUp(level)
    level = tonumber(level) or 0
    if level < 2 or level % 2 ~= 0 or SM:IsDND() then return false end
    local t = self:NearestClassTrainer()
    if t then
        self.trainerPoint = Point(t.mapID, t.x, t.y, L.POI_classtrainer)
        SM:Print(L.LEVEL_TRAINER_NEAR:format(level, SM.Eta.FormatDistance(t.dist)))
    else
        self.trainerPoint = nil
        SM:Print(L.LEVEL_TRAINER:format(level))
    end
    return true
end

SM:RegisterEvent(Chill, "PLAYER_LEVEL_UP", function(_, level)
    if Chill.enabled then Chill:OnLevelUp(level) end
end)

SM:RegisterCommand("lehrer", function()
    local pt = Chill.trainerPoint
    if not pt then
        local t = Chill:NearestClassTrainer()
        if t then pt = Point(t.mapID, t.x, t.y, L.POI_classtrainer) end
    end
    if not pt then SM:Print(L.LEVEL_TRAINER_NONE) return end
    local _, msg = SM.Eta:GoTo(pt)
    SM:Print(msg)
end, "trainer")

-- Musik-Einstellung: "off", "click" oder "auto"
function Chill:SetMode(mode)
    if mode ~= "off" and mode ~= "click" then mode = "auto" end
    SM.db.music.mode = mode
    if mode == "off" then self:Stop() end
    if mode == "click" and self.playing and self.auto then self:Stop() end
    SM:Fire("MUSIC_MODE_CHANGED", mode)
end

---------------------------------------------------------------------------
-- Modul-Lebenszyklus, Ereignisse, Befehle
---------------------------------------------------------------------------
function Chill:OnEnable()
    self:FreeAutoNames()
    SM:RegisterEvent(self, "UNIT_SPELLCAST_CHANNEL_START", function(_, unit, _, spellID)
        if unit == "player" and self:IsFishing(spellID) then self:OnFishing() end
    end)
    self.watcher = C_Timer.NewTicker(WATCH_TICK, function() self:Watch() end)
end

function Chill:OnDisable()
    self:Stop()
    if self.watcher then self.watcher:Cancel(); self.watcher = nil end
end

SM:RegisterCallback("SILENT_CHANGED", function(on)
    if on then Chill:Stop() end
end)

SM:RegisterCallback("BEACON_ADDED", function(b)
    if not (Chill.enabled and b and b.own) then return end
    C_Timer.After(WAIT_TIP_DELAY, function() Chill:StartWaitIdeas(b) end)
end)

-- /sm musik: den Musik-Player öffnen oder schließen; /sm musik stopp / weiter
SM:RegisterCommand("musik", function(rest)
    rest = (rest or ""):lower()
    if rest == "stopp" or rest == "stop" or rest == "aus" or rest == "off" then
        SM:Print(Chill:Stop() and L.MUSIC_STOPPED or L.MUSIC_IDLE)
    elseif rest == "weiter" or rest == "next" then
        local _, msg = Chill:Next()
        SM:Print(msg)
    else
        Chill:TogglePlayer()
    end
end, "music")

SM:RegisterPosition(function() return SM.db.music end, function() return Chill.player end,
    function(f) f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -260, 180) end)
SM:RegisterPosition(function() return SM.db.musicMini end, function() return Chill.mini end,
    function() Chill:PlaceMini() end)
