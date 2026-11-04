local ADDON, SM = ...
local L = SM.L
local M = SM.Media

-- Lore-Leser: Geschichten zu Zonen und Städten zum Lesen in Ruhe, Kapitel für Kapitel.
-- Die Geschichten stehen in Modules\LoreStories.lua (eigene Worte, nachgeprüft am Warcraft Wiki).
-- Für Zonen ohne ausführliche Geschichte zeigt der Leser die kurzen Lore-Häppchen.
-- "Mehr lesen" öffnet den Link zum passenden Artikel im Warcraft Wiki zum Kopieren.
local Reader = {}
SM.LoreReader = Reader

local ink = M.colors.ink
local SOFT = M.colors.soft
local WIKI = "https://warcraft.wiki.gg/wiki/"
local MIN_H = 240   -- kleinste Höhe des Lesers (ein Satz)

local function Lang()
    local loc = SM.locale or ""
    if loc == "deDE" then return "de" end
    return "en"
end

-- Name in der Sprache des Addons (ZoneNames.lua), sonst wie im Spiel
local function MapName(mapID)
    return SM:MapName(mapID)
end

-- Kapitel einer Zone: { { h = Überschrift, t = Text }, ... }, Wiki-Seite
function Reader:Chapters(mapID)
    local story = SM.LoreStories and SM.LoreStories[mapID]
    if story then
        local list = story[Lang()] or story.en
        if list and #list > 0 then return list, story.wiki, story.title and (story.title[Lang()] or story.title.en) end
    end
    local D = SM.LoreData
    local snippets = D and (D[Lang()] or D.en)
    snippets = snippets and snippets[mapID]
    if snippets and #snippets > 0 then
        local list = {}
        for _, t in ipairs(snippets) do list[#list + 1] = { t = t } end
        return list, story and story.wiki or nil
    end
    return nil
end

-- Alle Zonen mit Geschichten, alphabetisch (für "Andere Zone")
function Reader:Zones()
    local seen, list = {}, {}
    for id in pairs(SM.LoreStories or {}) do seen[id] = true end
    local D = SM.LoreData and (SM.LoreData[Lang()] or SM.LoreData.en) or {}
    for id in pairs(D) do if type(id) == "number" then seen[id] = true end end
    for id in pairs(seen) do list[#list + 1] = id end
    table.sort(list, function(a, b) return MapName(a) < MapName(b) end)
    return list
end

function Reader:Build()
    if self.frame then return end
    local UI = SM.UI
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "SocializeMeForeverLore", UIParent, template)
    self.frame = f
    f:SetSize(470, 440)
    f:SetPoint("CENTER", 0, 30)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(fr) SM.UI.DragStart(fr) end)
    -- Selbst verschoben: die Stelle merken, dann klebt der Leser nicht mehr am Hauptfenster
    -- gemerkt wird die untere linke Ecke: die Höhe wechselt mit dem Text, die Knöpfe unten
    -- sollen dabei an derselben Stelle bleiben (Maus bleibt auf "Weiter")
    f:SetScript("OnDragStop", function(fr)
        fr:StopMovingOrSizing()
        local x, y = fr:GetLeft(), fr:GetBottom()
        if not (x and y) then return end
        fr:ClearAllPoints()
        fr:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
        local pos = SM.db.lore
        pos.point, pos.relPoint, pos.x, pos.y = "BOTTOMLEFT", "BOTTOMLEFT", x, y
    end)
    if f.SetBackdrop then
        f:SetBackdrop({ edgeFile = M.tex.border, edgeSize = 24, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    end
    local paper = f:CreateTexture(nil, "BACKGROUND")
    paper:SetPoint("TOPLEFT", 8, -8)
    paper:SetPoint("BOTTOMRIGHT", -8, 8)
    paper:SetColorTexture(unpack(M.colors.parchment))

    local function Text(font, color, width)
        local fs = f:CreateFontString(nil, "OVERLAY", font)
        color = color or ink
        fs:SetTextColor(color[1], color[2], color[3])
        fs:SetJustifyH("LEFT")
        fs:SetShadowOffset(0, 0)
        if width then fs:SetWidth(width) end
        return fs
    end
    f.kicker = Text("GameFontNormalSmall", SOFT, 380)
    f.kicker:SetPoint("TOPLEFT", 22, -18)
    f.zone = Text("GameFontNormalLarge", ink, 380)
    f.zone:SetPoint("TOPLEFT", 22, -32)
    f.head = Text("GameFontNormal", M.colors.head, 426)
    f.head:SetPoint("TOPLEFT", 22, -62)
    f.text = Text("GameFontNormal", ink, 426)
    f.text:SetPoint("TOPLEFT", 22, -84)
    f.text:SetJustifyV("TOP")
    f.page = Text("GameFontNormalSmall", SOFT, 200)
    f.page:SetPoint("BOTTOMLEFT", 22, 52)

    f.prev = UI.Button(f, "SocializeMeForeverLorePrev", 100, 22, L.LORE_PREV)
    f.prev:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 18)
    f.prev:SetScript("OnClick", function() Reader:Turn(-1) end)
    f.next = UI.Button(f, "SocializeMeForeverLoreNext", 100, 22, L.LORE_NEXT)
    f.next:SetPoint("LEFT", f.prev, "RIGHT", 6, 0)
    f.next:SetScript("OnClick", function() Reader:Turn(1) end)
    f.more = UI.Button(f, "SocializeMeForeverLoreMore", 110, 22, L.LORE_MORE)
    f.more:SetPoint("LEFT", f.next, "RIGHT", 6, 0)
    f.more:SetScript("OnClick", function()
        if Reader.wiki then SM.CopyDialog:Show(WIKI .. Reader.wiki) end
    end)
    f.more:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:AddLine(L.LORE_MORE_TT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.more:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.other = UI.Button(f, "SocializeMeForeverLoreOther", 110, 22, L.LORE_OTHER)
    f.other:SetPoint("LEFT", f.more, "RIGHT", 6, 0)
    f.other:SetScript("OnClick", function() Reader:NextZone() end)
    local close = UI.CloseButton(f, function() f:Hide() end)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) Reader:Turn(delta < 0 and 1 or -1) end)
    tinsert(UISpecialFrames, "SocializeMeForeverLore")
    f:Hide()
end

-- "Fensterpositionen zurücksetzen" vergisst auch die Stelle des Lesers
SM:RegisterPosition(function() return SM.db.lore end, function() return Reader.frame end,
    function() if Reader.frame then Reader:Place() end end)

function Reader:Show()
    local f = self.frame
    local list, wiki, title = self:Chapters(self.mapID)
    self.list = list or {}
    self.wiki = self.wikiOverride or wiki
    local n = #self.list
    if self.index > n then self.index = n end
    if self.index < 1 then self.index = 1 end
    f.kicker:SetText(L.LORE_KICKER)
    f.zone:SetText(title or MapName(self.mapID))
    local ch = self.list[self.index]
    if ch then
        f.head:SetText(ch.h or "")
        f.text:SetText(ch.t or "")
        f.page:SetText(L.LORE_PAGE:format(self.index, n))
    else
        f.head:SetText("")
        f.text:SetText(L.LORE_EMPTY)
        f.page:SetText("")
    end
    if self.index > 1 then f.prev:Enable() else f.prev:Disable() end
    if self.index < n then f.next:Enable() else f.next:Disable() end
    if self.wiki then f.more:Enable() else f.more:Disable() end
    -- Höhe nach dem Text: kurze Kapitel = kleines Fenster. Unten verankert, also wächst
    -- und schrumpft es nach oben, die Knöpfe bleiben unter der Maus.
    -- Dem Text selbst KEINE feste Höhe geben: sonst bleibt er nach einem kurzen Kapitel so
    -- klein, und das nächste lange Kapitel wird nach einer Zeile mit "..." abgeschnitten
    -- (test8: Sturmwind, Steinkrallengebirge, Sumpfland). Ohne Höhe wächst er mit.
    local th = math.max(14, math.ceil(f.text:GetStringHeight() or 0))
    f:SetHeight(math.max(MIN_H, 84 + th + 16 + 70))
    f:Show()
end

-- Wohin mit dem Leser? Hat der Spieler ihn verschoben, an diese Stelle. Sonst neben das
-- Hauptfenster (rechts, wenn dort Platz ist, sonst links), damit sich nichts überdeckt.
-- Ist das Hauptfenster zu oder passt er auf keine Seite, kommt er in die Mitte.
local GAP = 6
function Reader:Place()
    local f = self.frame
    local pos = SM.db and SM.db.lore
    f:ClearAllPoints()
    if pos and pos.x and pos.y then
        f:SetPoint(pos.point or "BOTTOMLEFT", UIParent, pos.relPoint or "BOTTOMLEFT", pos.x, pos.y)
        return "saved"
    end
    local win = SM.Window and SM.Window.frame
    if win and win:IsShown() then
        local ws, rs = win:GetEffectiveScale() or 1, f:GetEffectiveScale() or 1
        local left, right = win:GetLeft(), win:GetRight()
        local screen = UIParent:GetRight()
        local us = UIParent:GetEffectiveScale() or 1
        if left and right and screen then
            -- alles in Bildschirm-Pixeln rechnen, die Fenster haben verschiedene Größen-Stufen
            local need = (f:GetWidth() or 470) * rs + GAP * rs
            if right * ws + need <= screen * us then
                f:SetPoint("BOTTOMLEFT", win, "BOTTOMRIGHT", GAP, 0)
                return "right"
            elseif left * ws - need >= 0 then
                f:SetPoint("BOTTOMRIGHT", win, "BOTTOMLEFT", -GAP, 0)
                return "left"
            end
        end
    end
    f:SetPoint("BOTTOM", UIParent, "CENTER", 0, -190)
    return "center"
end

-- Öffnen: mapID (sonst deine Zone), wiki = eigene Wiki-Seite (z. B. ein Bauwerk)
function Reader:Open(mapID, wiki)
    self:Build()
    if not self.frame:IsShown() then self.placed = self:Place() end
    self.frame:Raise()
    mapID = mapID or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    if not mapID or not self:Chapters(mapID) then
        -- keine Geschichte für diese Zone: die erste Zone mit Geschichte nehmen
        mapID = self:Zones()[1]
    end
    self.mapID, self.index, self.wikiOverride = mapID, 1, wiki
    self:Show()
    return true
end

function Reader:Turn(step)
    if not self.list then return end
    local n = #self.list
    local i = math.max(1, math.min(n, self.index + step))
    if i == self.index then return end
    self.index = i
    self:Show()
end

function Reader:NextZone()
    local zones = self:Zones()
    if #zones == 0 then return end
    local nextIdx = 1
    for i, id in ipairs(zones) do if id == self.mapID then nextIdx = i % #zones + 1 end end
    self.mapID, self.index, self.wikiOverride = zones[nextIdx], 1, nil
    self:Show()
end
