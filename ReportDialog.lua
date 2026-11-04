local ADDON, SM = ...
local L = SM.L
local M = SM.Media
local Guard = SM.Guard

-- Melde-Fenster und Beweis-Seite (Screenshot + Text zum Kopieren).
local ink = M.colors.ink

local function Frame(name, w, h, titleText)
    local UI = SM.UI
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", name, UIParent, template)
    f:SetSize(w, h)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(fr) SM.UI.DragStart(fr) end)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({ edgeFile = M.tex.border, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    end
    local paper = f:CreateTexture(nil, "BACKGROUND")
    paper:SetPoint("TOPLEFT", 11, -11)
    paper:SetPoint("BOTTOMRIGHT", -11, 11)
    paper:SetColorTexture(unpack(M.colors.parchment))
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -14)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -14)
    bar:SetHeight(28)
    local barTex = bar:CreateTexture(nil, "BACKGROUND")
    barTex:SetAllPoints(bar)
    barTex:SetColorTexture(unpack(M.colors.wood))
    UI.AddGrain(bar, w - 28, 28, "BORDER")
    local tx = M.wood.text
    f.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("CENTER", bar, "CENTER", 0, 0)
    f.title:SetTextColor(tx[1], tx[2], tx[3])
    f.title:SetText(titleText or "")
    local close = UI.CloseButton(f, function() f:Hide() end)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -18)
    close:SetFrameLevel(bar:GetFrameLevel() + 3)
    tinsert(UISpecialFrames, name)
    f:Hide()
    return f
end

local function Text(parent, font, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    color = color or ink
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetShadowOffset(0, 0)
    return fs
end

---------------------------------------------------------------------------
-- Melden
---------------------------------------------------------------------------
local REASON_KEYS = { s = "REPORT_R_SPAM", i = "REPORT_R_INSULT", h = "REPORT_R_HARASS", b = "REPORT_R_BEACON" }

function Guard:BuildDialog()
    if self.dialog then return end
    local UI = SM.UI
    local f = Frame("SocializeMeForeverReport", 420, 450, L.REPORT_TITLE)
    self.dialog = f
    f.question = Text(f)
    f.question:SetPoint("TOPLEFT", 26, -54)
    f.question:SetWidth(368)

    f.reasons = {}
    for i, key in ipairs({ "s", "i", "h", "b" }) do
        local b = UI.Button(f, nil, 368, 24, L[REASON_KEYS[key]])
        b:SetPoint("TOPLEFT", 26, -78 - (i - 1) * 28)
        b:SetScript("OnClick", function() Guard:SelectReason(key) end)
        f.reasons[key] = b
    end

    f.note = Text(f, "GameFontNormalSmall", M.colors.warn)
    f.note:SetPoint("TOPLEFT", 26, -194)
    f.note:SetWidth(368)
    f.note:SetText(L.REPORT_NOTE)

    -- Startphase (bis 18.11.): mildere Regeln, kurz erklärt
    f.start = Text(f, "GameFontNormalSmall", M.colors.soft)
    f.start:SetPoint("TOPLEFT", 26, -224)
    f.start:SetWidth(368)
    f.start:SetText(L.REPORT_STARTPHASE)

    -- Schweres gehört (auch) direkt zu Blizzard
    f.blizzText = Text(f, "GameFontNormalSmall")
    f.blizzText:SetPoint("TOPLEFT", 26, -268)
    f.blizzText:SetWidth(368)
    f.blizzText:SetText(L.REPORT_BLIZZ_HINT)
    f.blizz = UI.Button(f, "SocializeMeForeverReportBlizz", 200, 24, L.REPORT_BLIZZ_BTN)
    f.blizz:SetPoint("TOPLEFT", 26, -296)
    f.blizz:SetScript("OnClick", function()
        if not Guard:OpenBlizzardReport(f.name, Guard:Wrote(f.name)) then SM:Print(L.REPORT_BLIZZ_FAIL) end
    end)

    f.status = Text(f)
    f.status:SetPoint("TOPLEFT", 26, -330)
    f.status:SetWidth(368)
    f.status:SetHeight(60)

    f.send = UI.Button(f, "SocializeMeForeverReportSend", 120, 26, L.REPORT_SEND)
    f.send:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 26, 22)
    f.send:SetScript("OnClick", function() Guard:SubmitDialog() end)
    f.evidence = UI.Button(f, "SocializeMeForeverReportEvidence", 130, 26, L.EVIDENCE_BTN)
    f.evidence:SetPoint("LEFT", f.send, "RIGHT", 6, 0)
    f.evidence:SetScript("OnClick", function() Guard:ShowEvidence(f.name) end)
    f.evidence:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:AddLine(L.EVIDENCE_BTN, 1, 0.82, 0)
        GameTooltip:AddLine(L.EVIDENCE_TT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.evidence:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.cancel = UI.Button(f, "SocializeMeForeverReportCancel", 100, 26, L.REPORT_CANCEL)
    f.cancel:SetPoint("LEFT", f.evidence, "RIGHT", 6, 0)
    f.cancel:SetScript("OnClick", function() f:Hide() end)
end

-- Öffnet das Melde-Fenster. beacon (optional): ein Beacon dieses Spielers (für "unpassender Text").
function Guard:ShowDialog(name, beacon)
    self:BuildDialog()
    local f = self.dialog
    local short = (name and name:match("^([^-]+)")) or name
    local canWords = self:CanReport(short)
    f.name, f.beacon, f.reason = short, beacon, nil
    f.question:SetText((canWords and L.REPORT_ASK or L.REPORT_ASK_BEACON):format(short))
    for key, b in pairs(f.reasons) do
        if key == "b" then
            if beacon then b:Show() else b:Hide() end
        else
            if canWords then b:Show() else b:Hide() end
        end
        b:UnlockHighlight()
    end
    -- ohne Wörter und ohne Beacon gibt es nichts zu melden
    if not canWords and not beacon then
        local _, why = self:CanReport(short)
        SM:Print(why)
        return false
    end
    if self:Wrote(short) then f.evidence:Show(); f.blizz:Show(); f.blizzText:Show() else f.evidence:Hide(); f.blizz:Hide(); f.blizzText:Hide() end
    if self:InStartPhase() then f.start:Show() else f.start:Hide() end
    f.send:Disable()
    f.status:SetText("")
    f:Show()
    return true
end

function Guard:SelectReason(key)
    local f = self.dialog
    f.reason = key
    for k, b in pairs(f.reasons) do
        if k == key then b:LockHighlight() else b:UnlockHighlight() end
    end
    f.send:Enable()
end

function Guard:SubmitDialog()
    local f = self.dialog
    if not f.reason then return end
    local ok, msg
    if f.reason == "b" then
        ok, msg = self:ReportBeacon(f.beacon)
    else
        ok, msg = self:Report(f.name, f.reason)
    end
    local c = ok and M.colors.good or M.colors.bad
    f.status:SetTextColor(c[1], c[2], c[3])
    f.status:SetText(msg or "")
    if ok then
        f.send:Disable()
        for _, b in pairs(f.reasons) do b:Disable() end
        C_Timer.After(0.1, function() for _, b in pairs(f.reasons) do b:Enable() end end)
    end
    return ok, msg
end

---------------------------------------------------------------------------
-- Beweis-Seite: für Screenshot und Anzeige
---------------------------------------------------------------------------
local CHANNEL_KEYS = {
    WHISPER = "EVIDENCE_CH_WHISPER", PARTY = "EVIDENCE_CH_GROUP", PARTY_LEADER = "EVIDENCE_CH_GROUP",
    RAID = "EVIDENCE_CH_GROUP", RAID_LEADER = "EVIDENCE_CH_GROUP",
    INSTANCE_CHAT = "EVIDENCE_CH_GROUP", INSTANCE_CHAT_LEADER = "EVIDENCE_CH_GROUP",
}

-- Der Beweis als Text (auch zum Kopieren)
function Guard:EvidenceText(name)
    local w = self:Wrote(name)
    local realm = (type(GetRealmName) == "function" and GetRealmName()) or "?"
    local full = (w and w.full) or name
    if not full:find("-", 1, true) then full = full .. "-" .. realm end
    local lines = {
        L.EVIDENCE_HEAD,
        L.EVIDENCE_WHO:format(full),
        L.EVIDENCE_ID:format((w and w.guid and w.guid ~= "") and w.guid or "-"),
        L.EVIDENCE_BY:format((UnitName("player") or "?") .. "-" .. realm),
        L.EVIDENCE_WHEN:format(date("%d.%m.%Y %H:%M:%S")),
        "",
        L.EVIDENCE_MSGS,
    }
    for _, m in ipairs((w and w.msgs) or {}) do
        lines[#lines + 1] = ("[%s] (%s) %s: %s"):format(date("%d.%m.%Y %H:%M:%S", m.t),
            L[CHANNEL_KEYS[m.c] or "EVIDENCE_CH_GROUP"], (w.full or name), m.m)
    end
    if not (w and w.msgs and #w.msgs > 0) then lines[#lines + 1] = L.EVIDENCE_NONE end
    return table.concat(lines, "\n")
end

function Guard:BuildEvidence()
    if self.evidenceFrame then return end
    local UI = SM.UI
    local f = Frame("SocializeMeForeverEvidence", 560, 520, L.EVIDENCE_TITLE)
    self.evidenceFrame = f
    f.body = Text(f, "GameFontHighlight", M.colors.ink)
    f.body:SetPoint("TOPLEFT", 26, -54)
    f.body:SetWidth(508)
    f.body:SetHeight(300)
    f.help = Text(f, "GameFontNormalSmall", M.colors.soft)
    f.help:SetPoint("TOPLEFT", 26, -362)
    f.help:SetWidth(508)
    f.help:SetText(L.EVIDENCE_HELP)

    f.shot = UI.Button(f, "SocializeMeForeverEvidenceShot", 170, 26, L.EVIDENCE_SHOT)
    f.shot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 26, 22)
    f.shot:SetScript("OnClick", function() Guard:TakeScreenshot() end)
    f.copy = UI.Button(f, "SocializeMeForeverEvidenceCopy", 150, 26, L.EVIDENCE_COPY)
    f.copy:SetPoint("LEFT", f.shot, "RIGHT", 6, 0)
    f.copy:SetScript("OnClick", function() Guard:ShowCopy() end)
    f.done = UI.Button(f, "SocializeMeForeverEvidenceDone", 120, 26, L.RULES_CLOSE)
    f.done:SetPoint("LEFT", f.copy, "RIGHT", 6, 0)
    f.done:SetScript("OnClick", function() f:Hide() end)

    -- Text zum Kopieren (mehrzeilig, alles markiert)
    local box = CreateFrame("EditBox", "SocializeMeForeverEvidenceText", f)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetPoint("TOPLEFT", 26, -54)
    box:SetSize(508, 300)
    box:SetTextColor(ink[1], ink[2], ink[3])
    box:SetScript("OnEscapePressed", function(b) b:ClearFocus(); b:Hide(); f.body:Show() end)
    box:SetScript("OnTextChanged", function(b, user) if user then b:SetText(f.plain or ""); b:HighlightText() end end)
    box:Hide()
    f.box = box
end

function Guard:ShowEvidence(name)
    self:BuildEvidence()
    local f = self.evidenceFrame
    f.name = name
    f.plain = self:EvidenceText(name)
    f.body:SetText(f.plain)
    f.body:Show()
    f.box:Hide()
    f:Show()
    if f.Raise then f:Raise() end
    -- Das Melde-Fenster rückt daneben, statt die Beweis-Seite zu verdecken.
    local d = self.dialog
    if d and d:IsShown() then
        d:ClearAllPoints()
        d:SetPoint("TOPLEFT", f, "TOPRIGHT", 8, 0)
    end
    -- gleich einmal sichern: so wenig Klicks wie möglich
    C_Timer.After(0.5, function() if f:IsShown() then Guard:TakeScreenshot() end end)
end

function Guard:TakeScreenshot()
    local f = self.evidenceFrame
    if not f or not f:IsShown() then return false end
    f.box:Hide(); f.body:Show()
    if type(Screenshot) ~= "function" then
        SM:Print(L.EVIDENCE_NOSHOT)
        return false
    end
    -- Nichts darf den Beweis verdecken: das Melde-Fenster für das Bild kurz ausblenden.
    local d = self.dialog
    local wasShown = d and d:IsShown()
    if wasShown then d:Hide() end
    C_Timer.After(0.1, function()
        local ok = pcall(Screenshot)
        if wasShown then d:Show() end
        SM:Print(ok and L.EVIDENCE_SAVED or L.EVIDENCE_NOSHOT)
    end)
    return true
end

function Guard:ShowCopy()
    local f = self.evidenceFrame
    if not f then return end
    f.body:Hide()
    f.box:SetText(f.plain or "")
    f.box:Show()
    f.box:SetFocus()
    f.box:HighlightText()
    SM:Print(L.EVIDENCE_COPY_HINT)
end

---------------------------------------------------------------------------
-- Gesperrt: statt des Addons nur dieser Hinweis
---------------------------------------------------------------------------
function Guard:ShowBlocked()
    if not self.blockedFrame then
        local UI = SM.UI
        local f = Frame("SocializeMeForeverBlocked", 420, 220, L.BLOCK_TITLE)
        self.blockedFrame = f
        f.text = Text(f, "GameFontNormal", M.colors.warn)
        f.text:SetPoint("TOPLEFT", 26, -56)
        f.text:SetWidth(368)
        f.rules = UI.Button(f, nil, 170, 26, L.SET_RULES)
        f.rules:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 22)
        f.rules:SetScript("OnClick", function() f:Hide(); SM.Rules:Show() end)
        f.ok = UI.Button(f, nil, 170, 26, L.RULES_CLOSE)
        f.ok:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 22)
        f.ok:SetScript("OnClick", function() f:Hide() end)
    end
    self.blockedFrame.text:SetText(self:BlockText())
    self.blockedFrame:Show()
end
