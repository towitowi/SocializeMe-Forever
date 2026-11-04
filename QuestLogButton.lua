local ADDON, SM = ...
local L = SM.L

-- Knopf "Treffpunkt setzen" am Questlog des Spiels: die gewählte Quest mit einem Klick als
-- Quest-Treffpunkt teilen - ohne erst das Addon-Fenster zu öffnen. Sprachchat-Stufe und Kürzel
-- kommen aus dem Formular (gemerkt). Der Knopf sitzt unten in der Knopfleiste links neben
-- "Schließen" (test8b); gibt es den nicht, hängt er rechts außen am Questlog. Gibt es kein
-- klassisches Questlog, gibt es auch keinen Knopf.
local QB = {}
SM.QuestLogButton = QB

local W, H = 136, 24

-- Gewählte Quest im Questlog: questID, Titel (oder nil)
function QB:SelectedQuest()
    local idx = type(GetQuestLogSelection) == "function" and GetQuestLogSelection()
    if not idx or idx == 0 or type(GetQuestLogTitle) ~= "function" then return nil end
    local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(idx)
    if not title or isHeader then return nil end
    questID = tonumber(questID)
    if not questID or questID == 0 then
        -- ältere Clients: über den Titel im eigenen Questlog suchen
        for _, e in ipairs((SM.QuestInfo:ScanLog())) do
            if e.title == title then questID = e.questID end
        end
    end
    return questID, title
end

-- Warum geht es gerade nicht? (nil = es geht)
function QB:Problem()
    if SM.Rules and not SM.Rules:Accepted() then return L.QL_RULES end
    if not (SM.Beacon and SM.Beacon.enabled) then return L.ERR_DISABLED end
    if SM:IsDND() then return L.ERR_DND end
    if not SM.Beacon:LevelOK() then return L.ERR_LEVEL:format(SM.Guard.MIN_BEACON_LEVEL) end
    if not self:SelectedQuest() then return L.QL_PICK end
    return nil
end

function QB:Refresh()
    local b = self.btn
    if not b then return end
    -- Beschriftung jedes Mal neu: der Knopf entsteht, bevor die Addon-Sprache gesetzt ist (test8d)
    b:SetText(L.QL_BTN)
    if self:Problem() then b:Disable() else b:Enable() end
end

function QB:Click()
    local problem = self:Problem()
    if problem then SM:Print(problem) return false end
    local questID = self:SelectedQuest()
    local voice = SM.Social.VoiceLevel(SM.db.beacon.voice)
    local ok, msg = SM.Beacon:Create("quest", "", voice, questID)
    SM:Print(msg)
    if ok and SM.Window and SM.Window.frame and SM.Window.frame:IsShown() then SM.Window:RefreshList() end
    return ok
end

-- Der Knopf "Schließen" unten im Questlog: je nach Client heißt er anders - darum auch nach der
-- Beschriftung suchen (CLOSE = "Schließen"/"Close" in der Sprache des Spiels). Das X oben hat keine.
function QB:FindClose()
    local label = _G.CLOSE or "Close"
    local function IsClose(f)
        return f and f.GetObjectType and f:GetObjectType() == "Button" and f.GetText and f:GetText() == label
    end
    for _, name in ipairs({ "QuestLogFrameCancelButton", "QuestLogFrameCloseButton", "QuestLogCloseButton" }) do
        if IsClose(_G[name]) then return _G[name] end
    end
    local function Scan(f, depth)
        if not (f and f.GetChildren) or depth > 3 then return nil end
        for _, c in ipairs({ f:GetChildren() }) do
            if c ~= self.btn and IsClose(c) then return c end
            local r = Scan(c, depth + 1)
            if r then return r end
        end
        return nil
    end
    return Scan(QuestLogFrame, 0)
end

-- test8b: unten in der Knopfleiste, direkt links neben "Schließen" (dort ist Platz). Findet sich
-- kein solcher Knopf, wie bisher rechts außen am Questlog.
function QB:Place()
    local b = self.btn
    if not b then return end
    local close = self:FindClose()
    b:ClearAllPoints()
    if close then
        b:SetPoint("RIGHT", close, "LEFT", -4, 0)
        -- so hoch wie "Schließen", sonst steht er oben und unten über (test8d)
        local h = close.GetHeight and tonumber(close:GetHeight())
        if h and h > 10 then b:SetHeight(h) end
        if b.SetFrameLevel and close.GetFrameLevel then b:SetFrameLevel((close:GetFrameLevel() or 1) + 1) end
        self.atClose = true
    else
        b:SetPoint("TOPLEFT", QuestLogFrame, "TOPRIGHT", -30, -72)
        self.atClose = false
    end
end

function QB:Build()
    if self.btn or not QuestLogFrame then return end
    local b = SM.UI.Button(QuestLogFrame, "SocializeMeForeverQuestLogButton", W, H, L.QL_BTN)
    self.btn = b
    self:Place()
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
    b:SetScript("OnClick", function() QB:Click(); QB:Refresh() end)
    b:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L.QL_BTN, 1, 0.82, 0)
        GameTooltip:AddLine(L.QL_BTN_TT, 1, 1, 1, true)
        local problem = QB:Problem()
        if problem then GameTooltip:AddLine(problem, 1, 0.5, 0.4, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- beim Öffnen noch einmal suchen: manche Clients/Addons bauen die Knopfleiste erst später
    QuestLogFrame:HookScript("OnShow", function() if not QB.atClose then QB:Place() end; QB:Refresh() end)
    if type(hooksecurefunc) == "function" and type(SelectQuestLogEntry) == "function" then
        hooksecurefunc("SelectQuestLogEntry", function() QB:Refresh() end)
    end
    self:Refresh()
end

local ev = {}
SM:RegisterEvent(ev, "PLAYER_LOGIN", function() QB:Build() end)
SM:RegisterEvent(ev, "ADDON_LOADED", function() if not QB.btn then QB:Build() end end)
for _, e in ipairs({ "PLAYER_LEVEL_UP", "QUEST_LOG_UPDATE" }) do
    SM:RegisterEvent(QB, e, function() QB:Refresh() end)
end
SM:RegisterCallback("DND_CHANGED", function() QB:Refresh() end)
SM:RegisterCallback("RULES_ACCEPTED", function() QB:Refresh() end)
