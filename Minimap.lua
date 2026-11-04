local ADDON, SM = ...
local L = SM.L
local M = SM.Media

local Button = {}
SM.MinimapButton = Button

local EDGE_OFFSET = 5 -- Standard-Abstand: der Knopf sitzt mit seiner Mitte knapp außerhalb der Minimap-Linie (einstellbar)
local atan2 = math.atan2 or math.atan -- Lua 5.1 (WoW) hat atan2, neuere Lua-Versionen atan mit 2 Argumenten

-- Größe der echten Minimap (andere Addons können sie vergrößern oder verkleinern).
local function MinimapSize()
    local w = Minimap.GetWidth and Minimap:GetWidth()
    local h = Minimap.GetHeight and Minimap:GetHeight()
    if type(w) ~= "number" or w <= 0 then w = 140 end
    if type(h) ~= "number" or h <= 0 then h = w end
    return w, h
end

-- Minimap-Addons mit eckiger Karte melden das über GetMinimapShape().
local function IsSquare()
    if type(GetMinimapShape) ~= "function" then return false end
    local ok, shape = pcall(GetMinimapShape)
    return ok and shape ~= nil and shape ~= "ROUND"
end

-- Position auf dem Rand für einen Winkel in Grad. Gibt x, y relativ zur Minimap-Mitte zurück.
function Button:EdgePosition(deg)
    local w, h = MinimapSize()
    local offset = (SM.db and SM.db.minimap and SM.db.minimap.offset) or EDGE_OFFSET
    local halfW, halfH = w / 2 + offset, h / 2 + offset
    local angle = math.rad(deg or 45)
    local c, s = math.cos(angle), math.sin(angle)
    if IsSquare() then
        -- auf den Rand des Quadrats "ausrollen"
        local k = math.sqrt(2)
        return math.max(-halfW, math.min(c * halfW * k, halfW)), math.max(-halfH, math.min(s * halfH * k, halfH))
    end
    return c * halfW, s * halfW
end

function Button:UpdatePosition()
    if not self.frame then return end
    local x, y = self:EdgePosition(SM.db.minimap.pos)
    self.frame:ClearAllPoints() -- sonst sammeln sich Anker an
    self.frame:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Zeigt oder versteckt den Button gemäß Einstellung.
function Button:Apply()
    if not self.frame then return end
    if SM.db.minimap.hide then self.frame:Hide() else self.frame:Show() end
end

function Button:Create()
    if self.frame then return end

    local f = CreateFrame("Button", "SocializeMeForeverMinimapButton", Minimap)
    self.frame = f
    f:SetSize(31, 31)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(8)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:RegisterForDrag("LeftButton")

    local icon = f:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(M.tex.minimap)
    icon:SetSize(21, 21)
    icon:SetPoint("TOPLEFT", 6, -5)

    local border = f:CreateTexture(nil, "OVERLAY")
    border:SetTexture(M.tex.minimapBorder)
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", 0, 0)

    f:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    f:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if SM.Chill then
                local _, msg = SM.Chill:Toggle()
                SM:Print(msg)
            end
            return
        end
        if SM.Window then SM.Window:Toggle() end
    end)

    f:SetScript("OnDragStart", function(self)
        if SM.db.ui.locked then return end
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            SM.db.minimap.pos = math.deg(atan2(cy / scale - my, cx / scale - mx))
            Button:UpdatePosition()
        end)
    end)
    f:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L.WIN_TITLE, 1, 0.82, 0)
        GameTooltip:AddLine(L.MM_TIP_OPEN, 1, 1, 1)
        GameTooltip:AddLine(L.MM_TIP_MUSIC, 1, 1, 1)
        GameTooltip:AddLine(L.MM_TIP_DRAG, 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self:UpdatePosition()
    self:Apply()
end

SM:RegisterCallback("READY", function() Button:Create() end)
