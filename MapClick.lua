local ADDON, SM = ...
local L = SM.L
local M = SM.Media

-- Weltkarte (M): Alt+Klick auf eine Stelle öffnet eine kleine Auswahl (test8b):
--   * Weg hierher zeigen   - unsere Fahne auf Karte und Minikarte plus Richtungspfeil
--   * Hier einen Ort merken - Tab "Orte" öffnet sich, Namen eintippen (oder leer lassen), "Merken"
--   * Hier einen Treffpunkt setzen - nur in der Zone, in der du gerade bist: das Formular öffnet
--     sich mit der Stelle, Art / Text / Sprachchat wählst du wie gewohnt
--   * Weg wieder entfernen - nur, wenn gerade ein Weg aktiv ist
-- Linksklick zoomt bei Blizzard hinein, Rechtsklick heraus, TomTom nutzt Strg+Rechtsklick -
-- Alt+Klick ist frei. Ein kleiner Zettel unten in der Mitte der Karte sagt, dass es das gibt;
-- nach dreimal Benutzen verschwindet er.
local MC = {}
SM.MapClick = MC

local HINT_USES = 3
local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
local ink = M.colors.ink

local function Pct(v) return math.floor((tonumber(v) or 0) * 100 + 0.5) end

local function PlayerMap()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

local function CloseMap()
    local w = WorldMapFrame
    if not (w and w.IsShown and w:IsShown()) then return end
    if HideUIPanel then HideUIPanel(w) else w:Hide() end
end

-- Zone und Stelle: mapID, x, y (0-1) - auf einer Kontinent- oder Weltkarte wird die Zone unter
-- der Maus gesucht und umgerechnet. nil, wenn dort keine Zone ist.
function MC:Resolve(mapID, x, y)
    x, y = tonumber(x), tonumber(y)
    if not (mapID and x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
    if info and info.mapType and info.mapType < zoneType then
        local sub = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(mapID, x, y)
        if not (sub and sub.mapID and sub.mapID ~= mapID and HBD and HBD.TranslateZoneCoordinates) then return nil end
        local zx, zy = HBD:TranslateZoneCoordinates(x, y, mapID, sub.mapID)
        if not (zx and zy) or zx < 0 or zx > 1 or zy < 0 or zy > 1 then return nil end
        return sub.mapID, zx, zy
    end
    return mapID, x, y
end

-- Name der Stelle: "Durotar 45, 62"
function MC:Label(mapID, x, y)
    return ("%s %d, %d"):format(SM:MapName(mapID) or "?", Pct(x), Pct(y))
end

function MC:Go(mapID, x, y)
    if not SM.Eta then return false end
    local ok, msg = SM.Eta:GoTo({ mapID = mapID, x = x, y = y, title = self:Label(mapID, x, y) })
    SM:Print(msg)
    return ok
end

function MC:Remember(mapID, x, y)
    local W = SM.Window
    if not W then return false end
    CloseMap()
    W:OpenTab("places")
    if not (W.frame and W.frame:IsShown()) then return false end -- Regeln noch offen o. ä.
    W.placeAt = { mapID = mapID, x = x, y = y }
    W:PlaceStatus(L.MAP_PLACE_AT:format(SM:MapName(mapID) or "?", Pct(x), Pct(y)), ink)
    if W.placeEdit then W.placeEdit:SetFocus() end
    return true
end

function MC:Meet(mapID, x, y)
    local W = SM.Window
    if not W then return false end
    if mapID ~= PlayerMap() then SM:Print(L.MAP_MEET_ZONE) return false end
    CloseMap()
    W:OpenBeaconForm()
    if not (W.frame and W.frame:IsShown()) then return false end
    W.beaconAt = { mapID = mapID, x = x, y = y }
    W:SetStatus(L.MAP_MEET_AT:format(SM:MapName(mapID) or "?", Pct(x), Pct(y), L.FORM_LIGHT), ink)
    return true
end

-- Die Auswahl an der Maus
function MC:Open(mapID, x, y)
    local inZone = (mapID == PlayerMap())
    local eta = SM.Eta and SM.Eta.enabled
    local entries = {
        { text = L.MAP_GO, disabled = not eta, fn = function() MC:Go(mapID, x, y) end },
        { text = L.MAP_REMEMBER, disabled = not SM.Chill, fn = function() MC:Remember(mapID, x, y) end },
        { text = L.MAP_MEET, disabled = not inZone, tip = (not inZone) and L.MAP_MEET_ZONE or nil,
          fn = function() MC:Meet(mapID, x, y) end },
    }
    if eta and SM.Eta.target then
        entries[#entries + 1] = { text = L.MAP_STOP, fn = function() SM.Eta:Stop() end }
    end
    self.menu = SM.UI.Menu(WorldMapFrame or UIParent, self:Label(mapID, x, y), entries)
    self:Used()
    return entries
end

-- Alt+Klick auf die Karte (mapID der gezeigten Karte, x/y 0-1)
function MC:Click(mapID, x, y)
    local m, zx, zy = self:Resolve(mapID, x, y)
    if not m then SM:Print(L.MAP_ZOOM_IN) return false end
    self:Open(m, zx, zy)
    return true
end

---------------------------------------------------------------------------
-- Hinweis-Zettel unten rechts auf der Karte (bis du es dreimal benutzt hast)
---------------------------------------------------------------------------
function MC:Used()
    local ui = SM.db and SM.db.ui
    if not ui then return end
    ui.mapHintUses = (tonumber(ui.mapHintUses) or 0) + 1
    self:RefreshHint()
end

function MC:RefreshHint()
    local h = self.hint
    if not h then return end
    local uses = SM.db and tonumber(SM.db.ui.mapHintUses) or 0
    if uses >= HINT_USES then h:Hide() else h:Show() end
end

function MC:BuildHint()
    if self.hint or not WorldMapFrame then return end
    local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "SocializeMeForeverMapHint", parent, template)
    self.hint = f
    if f.SetFrameLevel and parent.GetFrameLevel then f:SetFrameLevel((parent:GetFrameLevel() or 0) + 30) end
    f:EnableMouse(false) -- Klicks gehen durch auf die Karte
    if f.SetBackdrop then
        f:SetBackdrop({ edgeFile = M.tex.border, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    end
    local paper = f:CreateTexture(nil, "BACKGROUND")
    paper:SetPoint("TOPLEFT", 3, -3)
    paper:SetPoint("BOTTOMRIGHT", -3, 3)
    paper:SetColorTexture(unpack(M.colors.parchment))
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("CENTER", 0, 0)
    f.text:SetTextColor(ink[1], ink[2], ink[3])
    f.text:SetShadowOffset(0, 0)
    f.text:SetText(L.MAP_HINT)
    local w = tonumber(f.text.GetStringWidth and f.text:GetStringWidth()) or 0
    if w <= 0 then w = 260 end
    f:SetSize(math.ceil(w) + 18, 22)
    -- unten in der Mitte: bei großer Karte ragen die Ecken über den Bildschirmrand (test8b)
    f:SetPoint("BOTTOM", parent, "BOTTOM", 0, 8)
    if WorldMapFrame.HookScript then WorldMapFrame:HookScript("OnShow", function() MC:RefreshHint() end) end
    self:RefreshHint()
end

---------------------------------------------------------------------------
-- An die Karte hängen: über Blizzards Klick-Verteiler der Karte (dann zoomt die Karte bei
-- Alt+Klick nicht), sonst über das Loslassen der Maustaste
---------------------------------------------------------------------------
local function Handler(map, button, cx, cy)
    if button ~= "LeftButton" or not (IsAltKeyDown and IsAltKeyDown()) then return false end
    map = map or WorldMapFrame
    local mapID = map and map.GetMapID and map:GetMapID()
    local x, y = cx, cy
    if map and map.GetNormalizedCursorPosition then x, y = map:GetNormalizedCursorPosition() end
    SM.SafeCall(function() MC:Click(mapID, x, y) end)
    return true
end
MC.Handler = Handler

function MC:Hook()
    if self.hooked or not WorldMapFrame then return false end
    self.hooked = true
    if WorldMapFrame.AddCanvasClickHandler then
        WorldMapFrame:AddCanvasClickHandler(Handler, 100)
    elseif WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.HookScript then
        WorldMapFrame.ScrollContainer:HookScript("OnMouseUp", function(_, button) Handler(WorldMapFrame, button) end)
    end
    self:BuildHint()
    return true
end

local ev = {}
SM:RegisterEvent(ev, "PLAYER_LOGIN", function() MC:Hook() end)
SM:RegisterEvent(ev, "ADDON_LOADED", function() if not MC.hooked then MC:Hook() end end)
