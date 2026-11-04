local ADDON, SM = ...
local L = SM.L
local M = SM.Media
local UI = SM.UI
local Window = SM.Window

-- Tab „Orte“: schöne Plätze, Angelstellen, Bauwerke und Lagerfeuer deiner Zone.
-- Die mitgelieferten Orte (mit Foto-Tipps) gibt es nur in WoW Forever; in Classic steht das dabei.
local H = Window.H
local MakeText, Name = H.MakeText, H.Name
local ink, good, bad = M.colors.ink, M.colors.good, M.colors.bad
local SOFT = M.colors.soft

local ROWS, ROW_H = 7, 32
local LIST_TOP = 56
local CAT_ORDER = { "all", "view", "fish", "arch", "meet", "fire" }
local CAT_W = { all = 50, view = 76, fish = 66, arch = 82, meet = 92, fire = 84 }

Window.placeCat = "all"
Window.placeOffset = 0

local function Places() return SM.Places end

local function Icon(item)
    if item.kind == "fire" then return "Interface\\AddOns\\SocializeMeForever\\Media\\pin_campfire" end
    return Places().CAT_ICON[item.cat]
end

local function SourceText(item)
    if item.source == "addon" then return L.PLACE_SRC_ADDON end
    if item.source == "own" then return L.PLACE_SRC_OWN end
    if item.source == "learned" then return L.PLACE_SRC_LEARNED end
    if item.source == "beacon" then return item.beacon and item.beacon.sender or "" end
    return ""
end

function Window:BuildPlacesPanel(parent)
    local P = CreateFrame("Frame", nil, parent)
    P:SetAllPoints(parent)
    P:Hide()
    self.placesPanel = P

    self.placeZone = MakeText(P, "GameFontNormalLarge")
    self.placeZone:SetPoint("TOPLEFT", 0, -2)
    self.placeZone:SetWidth(330)
    self.placeZone:SetWordWrap(false)

    -- Einfügen: geteilte Orte (Textzeilen "[SM] ...") zu den eigenen Orten übernehmen
    self.placePasteBtn = UI.Button(P, Name("PlacePaste"), 132, 22, L.PLACE_PASTE)
    self.placePasteBtn:SetPoint("TOPRIGHT", P, "TOPRIGHT", 0, 0)
    self.placePasteBtn:SetScript("OnClick", function()
        SM.CopyDialog:AskPaste(L.PLACE_PASTE_TITLE, L.PLACE_PASTE_HINT, function(text)
            local ok, msg = SM.Places:Import(text)
            if ok then Window:PlaceStatus(msg, good); Window:RefreshPlaces() end
            return ok, msg
        end)
    end)
    self.placePasteBtn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L.PLACE_PASTE, 1, 0.82, 0)
        GameTooltip:AddLine(L.PLACE_PASTE_TT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.placePasteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Kategorien
    self.placeCatButtons = {}
    local x = 0
    for _, cat in ipairs(CAT_ORDER) do
        local b = UI.Button(P, Name("PlaceCat"), CAT_W[cat], 22, L["PLACE_CAT_" .. cat])
        b:SetPoint("TOPLEFT", x, -28)
        b:SetScript("OnClick", function()
            Window.placeCat = cat
            Window.placeOffset = 0
            Window.placeSel = nil
            Window.placeMulti = {}
            Window:RefreshPlaces()
        end)
        self.placeCatButtons[cat] = b
        x = x + CAT_W[cat] + 4
    end

    -- Liste
    self.placeRows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, P)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", P, "TOPLEFT", 0, -LIST_TOP - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", P, "TOPRIGHT", 0, -LIST_TOP - (i - 1) * ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(row)
        hl:SetColorTexture(unpack(M.colors.hover))
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints(row)
        row.sel:SetColorTexture(1, 0.8, 0.4, 0.30)
        row.sel:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.line1 = MakeText(row, "GameFontNormal")
        row.line1:SetPoint("TOPLEFT", 32, -3)
        row.line1:SetPoint("TOPRIGHT", -90, -3)
        row.line1:SetHeight(14)
        row.line1:SetWordWrap(false)
        row.dist = MakeText(row, "GameFontNormalSmall")
        row.dist:SetPoint("TOPRIGHT", -4, -4)
        row.dist:SetWidth(84)
        row.dist:SetJustifyH("RIGHT")
        row.line2 = MakeText(row, "GameFontNormalSmall", SOFT)
        row.line2:SetPoint("TOPLEFT", 32, -18)
        row.line2:SetPoint("TOPRIGHT", -4, -18)
        row.line2:SetHeight(12)
        row.line2:SetWordWrap(false)
        local sep = row:CreateTexture(nil, "ARTWORK")
        sep:SetPoint("BOTTOMLEFT", 0, 0)
        sep:SetPoint("BOTTOMRIGHT", 0, 0)
        sep:SetHeight(1)
        sep:SetColorTexture(unpack(M.colors.line))
        -- Klick (links oder rechts) = Auswahl mit "Weg zeigen" ganz oben (test8b: vorher zeigte
        -- ein Klick sofort den Weg - das hat überrascht). Strg+Klick = mehrere wählen.
        row:SetScript("OnClick", function(r, button)
            SM.UI.DropFocus()
            if not r.item then return end
            if button ~= "RightButton" and IsControlKeyDown and IsControlKeyDown() then
                Window:PlaceToggleMulti(r.item)
            else
                Window:PlaceMenu(r, r.item)
            end
            Window:RefreshPlaces()
        end)
        row:SetScript("OnEnter", function(r)
            local it = r.item
            if not it then return end
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            GameTooltip:AddLine(it.name or "", 1, 0.82, 0)
            if it.npc and it.npc ~= "" then GameTooltip:AddLine(it.npc, 1, 1, 1) end
            if it.desc and it.desc ~= "" then GameTooltip:AddLine(it.desc, 1, 1, 1, true) end
            GameTooltip:AddLine(SourceText(it), 0.8, 0.8, 0.8)
            GameTooltip:AddLine(L.PLACE_ROW_HINT, 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        self.placeRows[i] = row
    end
    P:EnableMouseWheel(true)
    P:SetScript("OnMouseWheel", function(_, delta)
        Window.placeOffset = math.max(0, Window.placeOffset - delta)
        Window:RefreshPlaces()
    end)

    self.placeEmpty = MakeText(P, "GameFontNormal")
    self.placeEmpty:SetPoint("TOP", P, "TOP", 0, -LIST_TOP - 40)
    self.placeEmpty:SetWidth(440)
    self.placeEmpty:SetJustifyH("CENTER")

    -- Auswahl: Text + Knöpfe
    local yD = -LIST_TOP - ROWS * ROW_H - 6
    H.Separator(P, yD + 2)
    self.placeDesc = MakeText(P, "GameFontNormalSmall")
    self.placeDesc:SetPoint("TOPLEFT", 0, yD - 4)
    self.placeDesc:SetWidth(474)
    self.placeDesc:SetHeight(40)
    self.placeDesc:SetJustifyV("TOP")

    local yB = yD - 48
    local function Btn(label, x, w, fn)
        local b = UI.Button(P, Name("PlaceAct"), w, 22, label)
        b:SetPoint("TOPLEFT", x, yB)
        b:SetScript("OnClick", fn)
        -- ausgegraut: sagen, warum (erst einen Ort wählen; Foto-Tipps gibt es nur in Forever)
        if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
        b:HookScript("OnEnter", function(btn)
            if btn.isEnabled then return end
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:AddLine(L.PLACE_PICK, 1, 1, 1, true)
            if not SM:IsForever() then GameTooltip:AddLine(L.PLACE_FOREVER_NOTE, 1, 0.82, 0, true) end
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    self.placeGoBtn = Btn(L.PLACE_GO, 0, 112, function()
        if Window.placeSel then Window:PlaceGo(Window.placeSel) end
    end)
    self.placePhotoBtn = Btn(L.PLACE_PHOTO, 116, 112, function()
        if Window:PlaceMultiCount() > 0 then
            Window.placeMulti = {}
            Window:RefreshPlaces()
            return
        end
        SM.PhotoCard:Show(Window.placeSel)
    end)
    -- Geschichte zum Ort - bei eigenen Orten steht hier "Vergessen"
    self.placeLoreBtn = Btn(L.PLACE_LORE, 232, 112, function()
        if Window:PlaceMultiCount() > 0 then
            Window:PlaceForgetMulti()
            return
        end
        local it = Window.placeSel
        if it and it.source == "own" then
            Window:PlaceForget(it)
            return
        end
        SM.LoreReader:Open(it and it.mapID or nil, it and it.wiki or nil)
    end)
    self.placeShareBtn = Btn(L.PLACE_SHARE, 348, 112, function()
        if Window:PlaceMultiCount() > 0 then
            Window:PlaceShare(Window:PlaceMultiItems())
            return
        end
        local text, msg = SM.Places:ShareText(Window.placeSel)
        if text then
            SM.CopyDialog:Show(text, L.PLACE_SHARE_TITLE, L.PLACE_SHARE_HINT)
        else
            Window:PlaceStatus(msg, bad)
        end
    end)
    self.placeShareBtn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:AddLine(L.PLACE_SHARE, 1, 0.82, 0)
        GameTooltip:AddLine(L.PLACE_SHARE_TT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.placeShareBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Hier merken
    local yM = yB - 34
    local ml = MakeText(P, "GameFontNormal")
    ml:SetPoint("TOPLEFT", 0, yM - 4)
    ml:SetText(L.PLACE_REMEMBER)
    local eb = UI.EditBox(P, Name("PlaceName"), 228, 22)
    eb:SetPoint("TOPLEFT", 100, yM)
    eb:SetMaxLetters(40)
    eb:SetScript("OnEnterPressed", function(e) e:ClearFocus(); Window:PlaceRemember() end)
    eb:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
    self.placeEdit = eb
    self.placeRememberBtn = UI.Button(P, Name("PlaceRem"), 112, 22, L.PLACE_REMEMBER_BTN)
    self.placeRememberBtn:SetPoint("TOPLEFT", 336, yM)
    self.placeRememberBtn:SetScript("OnClick", function() Window:PlaceRemember() end)

    self.placeStatus = MakeText(P, "GameFontNormalSmall")
    self.placeStatus:SetPoint("TOPLEFT", 0, yM - 30)
    self.placeStatus:SetWidth(474)
end

function Window:PlaceStatus(text, color)
    if not self.placeStatus then return end
    color = color or ink
    self.placeStatus:SetTextColor(color[1], color[2], color[3])
    self.placeStatus:SetText(text or "")
end

function Window:PlaceGo(item)
    if not item then return end
    local ok, msg
    if item.beacon then
        ok, msg = SM.Eta:Go(item.beacon, false)
    else
        ok, msg = SM.Eta:GoTo({ mapID = item.mapID, x = item.x, y = item.y, title = item.name, desc = item.desc,
                                placeKey = item.source == "addon" and item.ref and item.ref.key or nil })
    end
    self:PlaceStatus(msg, ok and good or bad)
end

-- eigenen Ort löschen (die Nummer kann sich verschoben haben: den Ort selbst suchen)
local function RemoveOwn(item)
    for i, s in ipairs(SM.db.spots or {}) do
        if s == item.ref then return SM.Chill:RemoveSpot(i) end
    end
    return false
end

function Window:PlaceForget(item)
    SM.Confirm:Show(L.PLACE_FORGET_ASK:format(item.name or "?"), function()
        -- die Nummer kann sich verschoben haben: den Ort selbst suchen
        local ok = RemoveOwn(item)
        Window.placeSel, Window.placeMulti = nil, {}
        Window:PlaceStatus(ok and L.PLACE_FORGOTTEN:format(item.name or "?") or "", good)
        SM:Fire("PLACES_CHANGED")
    end)
end

---------------------------------------------------------------------------
-- Mehrere Orte auf einmal: Strg+Klick oder "Mit auswählen" im Menü. Dann gibt es
-- "Teilen (n)" für alle und "Vergessen (n)" für die eigenen darunter.
---------------------------------------------------------------------------
Window.placeMulti = {}

local function PlaceKey(it)
    return tostring(it.ref or it.key or "") .. "|" .. tostring(it.name or "") .. "|" .. tostring(it.kind or "")
end

function Window:PlaceMultiCount()
    local n = 0
    for _ in pairs(self.placeMulti or {}) do n = n + 1 end
    return n
end

-- in der Reihenfolge der Liste
function Window:PlaceMultiItems()
    local out = {}
    for _, it in ipairs(self.placeList or {}) do
        if self.placeMulti[PlaceKey(it)] then out[#out + 1] = it end
    end
    return out
end

function Window:PlaceIsMulti(it)
    return it and self.placeMulti[PlaceKey(it)] ~= nil
end

function Window:PlaceToggleMulti(it)
    if not it then return end
    -- der bisher einzeln gewählte Ort kommt mit in die Auswahl
    if self:PlaceMultiCount() == 0 and self.placeSel and PlaceKey(self.placeSel) ~= PlaceKey(it) then
        self.placeMulti[PlaceKey(self.placeSel)] = self.placeSel
    end
    local k = PlaceKey(it)
    if self.placeMulti[k] then self.placeMulti[k] = nil else self.placeMulti[k] = it end
    self.placeSel = nil
    if self:PlaceMultiCount() == 1 then
        -- nur noch einer: wieder ganz normal einzeln gewählt
        local _, only = next(self.placeMulti)
        self.placeSel, self.placeMulti = only, {}
    end
end

-- Teilen: alle Zeilen hintereinander - "Einfügen" liest beliebig viele auf einmal
function Window:PlaceShare(items)
    local lines, lastErr = {}, nil
    for _, it in ipairs(items) do
        local text, msg = SM.Places:ShareText(it)
        if text then lines[#lines + 1] = text else lastErr = msg end
    end
    if #lines == 0 then
        self:PlaceStatus(lastErr or L.PLACE_SHARE_NONE, bad)
        return
    end
    local title = (#lines > 1) and L.PLACE_SHARE_TITLE_N:format(#lines) or L.PLACE_SHARE_TITLE
    SM.CopyDialog:Show(table.concat(lines, "  "), title, L.PLACE_SHARE_HINT)
end

function Window:PlaceForgetMulti()
    local own = {}
    for _, it in ipairs(self:PlaceMultiItems()) do
        if it.source == "own" then own[#own + 1] = it end
    end
    if #own == 0 then return end
    SM.Confirm:Show(L.PLACE_FORGET_ASK_N:format(#own), function()
        local n = 0
        for _, it in ipairs(own) do if RemoveOwn(it) then n = n + 1 end end
        Window.placeMulti, Window.placeSel = {}, nil
        Window:PlaceStatus(L.PLACE_FORGOTTEN_N:format(n), good)
        SM:Fire("PLACES_CHANGED")
    end)
end

-- Klick auf einen Ort: alles, was man mit ihm tun kann ("Weg zeigen" ganz oben)
function Window:PlaceMenu(row, it)
    if self:PlaceMultiCount() == 0 then self.placeSel = it end
    local entries = {
        { text = L.PLACE_GO, fn = function() Window.placeSel = it; Window:PlaceGo(it); Window:RefreshPlaces() end },
        { text = L.PLACE_PHOTO, fn = function() SM.PhotoCard:Show(it) end },
        { text = L.PLACE_LORE, fn = function() SM.LoreReader:Open(it.mapID, it.wiki) end },
        { text = L.PLACE_SHARE, disabled = it.kind ~= "place", fn = function() Window:PlaceShare({ it }) end },
        { text = self:PlaceIsMulti(it) and L.PLACE_MULTI_OFF or L.PLACE_MULTI_ON, tip = L.PLACE_MULTI_TT,
          fn = function() Window:PlaceToggleMulti(it); Window:RefreshPlaces() end },
    }
    if it.source == "own" then
        entries[#entries + 1] = { text = L.PLACE_FORGET, fn = function() Window:PlaceForget(it) end }
    end
    SM.UI.Menu(row, it.name, entries)
end

function Window:PlaceRemember()
    -- gemerkt wird in der gerade gewählten Kategorie (Alle / Lagerfeuer -> Aussicht)
    local c = self.placeCat
    local cat = (c == "fish" or c == "arch" or c == "meet") and c or "view"
    self.placeEdit:ClearFocus()
    local at = self.placeAt -- Stelle von der Weltkarte (Alt+Klick), sonst da, wo du stehst
    local ok, msg
    if at then
        ok, msg = SM.Places:RememberAt(self.placeEdit:GetText(), cat, at.mapID, at.x, at.y)
    else
        ok, msg = SM.Places:Remember(self.placeEdit:GetText(), cat)
    end
    self:PlaceStatus(msg, ok and good or bad)
    if ok then self.placeEdit:SetText(""); self.placeAt = nil end
    self:RefreshPlaces()
end

function Window:RefreshPlaces()
    if not self.placesPanel or not self.placesPanel:IsShown() then return end
    local Pl = SM.Places
    for cat, b in pairs(self.placeCatButtons) do
        if cat == self.placeCat then b:LockHighlight() else b:UnlockHighlight() end
    end
    if not (Pl and Pl.enabled) then
        self.placeZone:SetText(L.PLACE_TITLE:format("?"))
        for _, r in ipairs(self.placeRows) do r:Hide() end
        self.placeEmpty:SetText(L.PLACE_OFF)
        self.placeEmpty:Show()
        return
    end
    local mapID = Pl:PlayerPos() or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    self.placeZone:SetText(L.PLACE_TITLE:format(mapID and H.MapName(mapID) or "?"))
    local list = mapID and Pl:ForZone(mapID, self.placeCat) or {}
    self.placeList = list
    local maxOff = math.max(0, #list - ROWS)
    if self.placeOffset > maxOff then self.placeOffset = maxOff end
    for i = 1, ROWS do
        local row, it = self.placeRows[i], list[self.placeOffset + i]
        row.item = it
        if it then
            row.icon:SetTexture(Icon(it))
            local catName = L["PLACE_CAT_" .. it.cat]
            row.line1:SetText(it.name or "")
            row.line2:SetText(catName .. "  ·  " .. SourceText(it))
            row.dist:SetText(it.dist and SM.Eta.FormatDistance(it.dist) or "")
            local key = PlaceKey(it)
            if self.placeMulti[key] then self.placeMulti[key] = it end -- frische Daten
            local selected = self.placeMulti[key] or (self.placeSel and self.placeSel.ref == it.ref and self.placeSel.name == it.name)
            if selected then row.sel:Show() else row.sel:Hide() end
            row:Show()
        else
            row:Hide()
        end
    end
    if #list == 0 then
        self.placeEmpty:SetText(SM:IsForever() and L.PLACE_EMPTY or L.PLACE_EMPTY_CLASSIC)
        self.placeEmpty:Show()
    else
        self.placeEmpty:Hide()
    end
    -- Auswahl
    local sel = self.placeSel
    local nMulti = self:PlaceMultiCount()
    if nMulti > 0 then
        local items, own, share = self:PlaceMultiItems(), 0, 0
        for _, it in ipairs(items) do
            if it.source == "own" then own = own + 1 end
            if it.kind == "place" then share = share + 1 end
        end
        self.placeDesc:SetText(SM.Hex("7A4A00") .. L.PLACE_MULTI:format(nMulti) .. "|r  " .. L.PLACE_MULTI_HINT)
        self.placeGoBtn:Disable()
        self.placePhotoBtn:SetText(L.PLACE_MULTI_CLEAR); self.placePhotoBtn:Enable()
        self.placeLoreBtn:SetText(L.PLACE_FORGET_N:format(own))
        if own > 0 then self.placeLoreBtn:Enable() else self.placeLoreBtn:Disable() end
        self.placeShareBtn:SetText(L.PLACE_SHARE_N:format(share))
        if share > 0 then self.placeShareBtn:Enable() else self.placeShareBtn:Disable() end
        return
    end
    self.placePhotoBtn:SetText(L.PLACE_PHOTO)
    self.placeShareBtn:SetText(L.PLACE_SHARE)
    if sel then
        local d = sel.desc and sel.desc ~= "" and sel.desc or ""
        self.placeDesc:SetText(SM.Hex("7A4A00") .. (sel.name or "") .. "|r  " .. d)
        self.placeGoBtn:Enable(); self.placePhotoBtn:Enable(); self.placeLoreBtn:Enable()
        self.placeLoreBtn:SetText(sel.source == "own" and L.PLACE_FORGET or L.PLACE_LORE)
        if sel.kind == "place" then self.placeShareBtn:Enable() else self.placeShareBtn:Disable() end
    else
        -- In Classic: kurz sagen, dass die mitgelieferten Orte nur in WoW Forever da sind
        self.placeDesc:SetText(SM:IsForever() and L.PLACE_PICK or (L.PLACE_PICK .. "\n" .. L.PLACE_FOREVER_NOTE))
        self.placeGoBtn:Disable(); self.placePhotoBtn:Disable(); self.placeShareBtn:Disable()
    end
end

function Window:OpenPlaces()
    if SM.Rules and not SM.Rules:Accepted() then SM.Rules:Show() return end
    if SM.Guard:SelfBlocked() then SM.Guard:ShowBlocked() return end
    self:Create()
    self:ShowTab("places") -- Einfach-Ansicht: gezielt geöffnet = dazuschalten
    self.frame:Show()
    self:SelectTab("places")
end

SM:RegisterCallback("PLACES_CHANGED", function()
    if Window.frame and Window.frame:IsShown() and Window.tab == "places" then Window:RefreshPlaces() end
end)

-- Dev-Zusatz: Forever/Classic umgeschaltet
SM:RegisterCallback("FOREVER_CHANGED", function()
    if not (Window.frame and Window.frame:IsShown()) then return end
    Window:RefreshTitle()
    if Window.tab == "places" then Window:RefreshPlaces() end
    if Window.tab == "settings" then Window:RefreshSettings() end
end)
