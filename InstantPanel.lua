local ADDON, SM = ...
local L = SM.L
local M = SM.Media
local UI = SM.UI
local Window = SM.Window

-- Tab „Instant“: SocializeMe Voice und SocializeMe Text - spontan mit 2 bis 4 anderen plaudern.
--   * Ganz oben "Jetzt plaudern": ein Klick, ohne Thema - in die passendste offene Runde (Text oder
--     Sprachchat wie zuletzt, am Anfang Text, nie automatisch Discord), sonst eine eigene Runde.
--   * Darunter zwei Karten. Ein Klick auf "Jetzt reden" / "Jetzt schreiben" geht in eine passende
--     offene Runde oder eröffnet deine eigene.
--   * Sprachchat über das Spiel ("WoW-Sprachchat", kein Download) oder über Discord - das wählt,
--     wer die Runde eröffnet. Vor dem Beitritt zu einer Discord-Runde kommt ein Hinweis. Den
--     Discord-Link trägt der Gastgeber in "Deine Runde" ein; wer beitritt, bekommt ihn (test8b).
--   * Darunter das Thema (freiwillig, voreingestellt "Einfach plaudern") und alle offenen Runden.
--   * Bist du in einer Runde, wird aus den Karten "Deine Runde": wer dabei ist, die Knöpfe für
--     den Anfang und zum Gehen.
--   * Unten zwei Haken (beide aus): Chatzeile bei neuer Runde, Chatzeile beim Abflug.
-- Die Logik (Nachrichten, Einladen, Filter) steckt in Modules\Circle.lua.
local H = Window.H
local MakeText, Name = H.MakeText, H.Name
local ink, good, bad = M.colors.ink, M.colors.good, M.colors.bad
local SOFT = M.colors.soft
local CARD_FILL = M.colors.card
local ICON = { v = "Interface\\Icons\\INV_Misc_Horn_01", d = "Interface\\Icons\\INV_Misc_Horn_01",
               t = "Interface\\Icons\\INV_Misc_Note_01" }
local ROWS = 3
local CARD_TOP = -62             -- test8b: ohne Einleitungszeile (steht jetzt im Tooltip)
local CARD_H = 110
local LIST_TOP = -246
local ROUND_H, ROUND_H_D = 142, 170 -- Karte "Deine Runde" (mit Discord-Zeile etwas höher)

local function C() return SM.Circle end

local function Tip(widget, title, body)
    widget:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:AddLine(title, 1, 0.82, 0)
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Small(parent, x, y, width, color)
    local fs = MakeText(parent, "GameFontNormalSmall", color or SOFT)
    fs:SetPoint("TOPLEFT", x, y)
    if width then fs:SetWidth(width) end
    fs:SetJustifyV("TOP")
    return fs
end

-- Eine der beiden Karten (mode "v" oder "t")
local function BuildCard(P, x, mode)
    local card = UI.Panel(P, nil, CARD_FILL)
    card:SetSize(234, CARD_H)
    card:SetPoint("TOPLEFT", x, CARD_TOP)
    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30)
    icon:SetPoint("TOPLEFT", 10, -10)
    icon:SetTexture(ICON[mode])
    local title = MakeText(card, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 48, -9)
    title:SetText(mode == "v" and L.INSTANT_VOICE or L.INSTANT_TEXT)
    local sub = MakeText(card, "GameFontNormal")
    sub:SetPoint("TOPLEFT", 48, -28)
    sub:SetText(mode == "v" and L.INSTANT_VOICE_SUB or L.INSTANT_TEXT_SUB)
    -- Die Beschreibung steht im Tooltip der Karte (test8: kürzer, nichts überdeckt sich mehr).
    -- Darunter die grüne Zeile (wie viele Runden offen sind), der Knopf fest am unteren Rand.
    card.stats = Small(card, 10, -50, 214, good)
    card.go = UI.Button(card, Name("InstantGo"), 214, 24, mode == "v" and L.INSTANT_GO_VOICE or L.INSTANT_GO_TEXT)
    card.go:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 6)
    card.go:SetScript("OnClick", function() Window:InstantGo(mode) end)
    Tip(card.go, mode == "v" and L.INSTANT_GO_VOICE or L.INSTANT_GO_TEXT,
        (mode == "v" and L.INSTANT_VOICE_DESC or L.INSTANT_TEXT_DESC) .. "\n\n" .. L.INSTANT_GO_TT)
    card:EnableMouse(true)
    Tip(card, mode == "v" and L.INSTANT_VOICE or L.INSTANT_TEXT, mode == "v" and L.INSTANT_VOICE_DESC or L.INSTANT_TEXT_DESC)
    return card
end

function Window:BuildInstantPanel(parent)
    local P = CreateFrame("Frame", nil, parent)
    P:SetAllPoints(parent)
    P:Hide()
    self.instantPanel = P

    local head = H.Header(P, L.INSTANT_TITLE, 0, 0)
    -- Die Einleitung steht im Tooltip (weniger Text auf dem Pergament, test8b)
    local headHit = CreateFrame("Frame", nil, P)
    headHit:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
    headHit:SetSize(300, 20)
    headHit:EnableMouse(true)
    Tip(headHit, L.INSTANT_TITLE, L.INSTANT_INTRO)

    -- Ein Klick, ohne nachzudenken
    local quick = UI.Button(P, Name("InstantQuick"), 476, 28, L.INSTANT_QUICK)
    quick:SetPoint("TOPLEFT", 0, -26)
    quick:SetScript("OnClick", function() Window:InstantQuick() end)
    Tip(quick, L.INSTANT_QUICK, L.INSTANT_INTRO .. "\n\n" .. L.INSTANT_QUICK_TT)
    self.instantQuick = quick

    -- Noch in keiner Runde: zwei Karten + Thema
    self.instantCards = { v = BuildCard(P, 0, "v"), t = BuildCard(P, 242, "t") }
    local yT = CARD_TOP - CARD_H - 8
    local tl = MakeText(P, "GameFontNormal")
    tl:SetPoint("TOPLEFT", 0, yT - 4)
    tl:SetText(L.CIRCLE_TOPIC)
    self.instantTopicLabel = tl
    local tb = UI.Button(P, Name("InstantTopic"), 204, 22, "")
    tb:SetPoint("TOPLEFT", 54, yT)
    tb:SetScript("OnClick", function()
        local db = SM.db.circle
        db.topic = (db.topic or 1) % C().NUM_TOPICS + 1
        Window.instantOwn:SetText("")
        Window:RefreshInstant()
    end)
    Tip(tb, L.CIRCLE_TOPIC, L.CIRCLE_TOPIC_TT)
    self.instantTopicBtn = tb
    local ol = Small(P, 266, yT - 5)
    ol:SetText(L.CIRCLE_OWN)
    self.instantOwnLabel = ol
    local eb = UI.EditBox(P, Name("InstantOwn"), 130, 22)
    eb:SetPoint("TOPLEFT", 346, yT)
    eb:SetMaxLetters(40)
    eb:SetScript("OnEnterPressed", function(e) e:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
    self.instantOwn = eb

    -- Sprachchat über das Spiel oder über Discord (gilt für Runden, die du eröffnest)
    local yV = yT - 26
    local vl = MakeText(P, "GameFontNormal")
    vl:SetPoint("TOPLEFT", 0, yV - 4)
    vl:SetText(L.INSTANT_VIA)
    self.instantViaLabel = vl
    self.instantVia = {}
    for i, via in ipairs({ "wow", "discord" }) do
        local b = UI.Button(P, Name("InstantVia"), 150, 22, L["INSTANT_VIA_" .. via:upper()])
        b:SetPoint("TOPLEFT", 150 + (i - 1) * 156, yV)
        b:SetScript("OnClick", function()
            SM.db.circle.via = via
            Window:RefreshInstant()
        end)
        Tip(b, L["INSTANT_VIA_" .. via:upper()], L["INSTANT_VIA_" .. via:upper() .. "_TT"])
        self.instantVia[via] = b
    end

    -- In einer Runde: "Deine Runde"
    local rc = UI.Panel(P, nil, CARD_FILL)
    rc:SetSize(476, ROUND_H)
    rc:SetPoint("TOPLEFT", 0, -26) -- "Jetzt plaudern" ist in einer Runde ausgeblendet
    rc.icon = rc:CreateTexture(nil, "ARTWORK")
    rc.icon:SetSize(30, 30)
    rc.icon:SetPoint("TOPLEFT", 10, -10)
    rc.title = MakeText(rc, "GameFontNormalLarge")
    rc.title:SetPoint("TOPLEFT", 48, -9)
    rc.title:SetWidth(416)
    rc.title:SetWordWrap(false)
    rc.sub = MakeText(rc, "GameFontNormal")
    rc.sub:SetPoint("TOPLEFT", 48, -28)
    rc.sub:SetWidth(416)
    rc.sub:SetWordWrap(false)
    rc.members = Small(rc, 10, -52, 456)
    rc.hint = Small(rc, 10, -70, 456)
    local function RBtn(label, x, w, fn, tt)
        local b = UI.Button(rc, Name("InstantRound"), w, 22, label)
        b:SetPoint("TOPLEFT", x, -112)
        b:SetScript("OnClick", fn)
        if tt then Tip(b, label, tt) end
        return b
    end
    -- "schreibt erst, wenn du klickst / du kannst jederzeit gehen" steht jetzt in den Tooltips
    rc.hello = RBtn(L.CIRCLE_HELLO, 10, 104, function()
        local ok, msg = C():SayHello()
        if not ok then Window:SetInstantStatus(msg, bad) end
    end, L.CIRCLE_HELLO_TT .. "\n\n" .. L.INSTANT_ROUND_NOTE)
    rc.topic = RBtn(L.CIRCLE_SAY_TOPIC, 120, 110, function()
        local ok, msg = C():SayTopic()
        if not ok then Window:SetInstantStatus(msg, bad) end
    end, L.CIRCLE_SAY_TOPIC_TT .. "\n\n" .. L.INSTANT_ROUND_NOTE)
    rc.cheat = RBtn(L.CIRCLE_CHEAT, 236, 100, function() SM.VoiceCard:Toggle() end, L.INSTANT_CHEAT_TT)
    rc.leave = RBtn(L.CIRCLE_LEAVE, 342, 124, function()
        local ok, msg
        if C().own and not C().InGroup() then
            ok, msg = C():Close(), L.CIRCLE_CLOSED   -- noch allein: nur schließen
        else
            ok, msg = C():Leave()
        end
        Window:SetInstantStatus(msg, ok and good or bad)
    end, L.INSTANT_LEAVE_TT)
    -- Discord-Runde (test8b): der Gastgeber trägt seinen Einladungslink ein (wird gemerkt), wer
    -- beitritt, bekommt ihn vom Addon und kopiert ihn hier (oder per Klick auf die Zeile im Chat)
    rc.dLabel = MakeText(rc, "GameFontNormal")
    rc.dLabel:SetPoint("TOPLEFT", 10, -145)
    rc.dLabel:SetText(L.CIRCLE_DISCORD_LABEL)
    rc.dEdit = UI.EditBox(rc, Name("InstantDiscord"), 250, 22)
    rc.dEdit:SetPoint("TOPLEFT", 80, -140)
    rc.dEdit:SetMaxLetters(80)
    rc.dEdit:SetScript("OnEnterPressed", function(e) e:ClearFocus(); Window:InstantSaveDiscord() end)
    rc.dEdit:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
    rc.dText = MakeText(rc, "GameFontNormal")
    rc.dText:SetPoint("TOPLEFT", 80, -145)
    rc.dText:SetWidth(250)
    rc.dText:SetWordWrap(false)
    rc.dBtn = UI.Button(rc, Name("InstantDiscordBtn"), 126, 22, L.CIRCLE_DISCORD_SAVE)
    rc.dBtn:SetPoint("TOPLEFT", 340, -140)
    rc.dBtn:SetScript("OnClick", function() Window:InstantDiscordClick() end)
    rc.dBtn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:AddLine(b:GetText() or "", 1, 0.82, 0)
        GameTooltip:AddLine(C():Hosting() and L.CIRCLE_DISCORD_SAVE_TT or L.CIRCLE_DISCORD_COPY_TT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    rc.dBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rc:Hide()
    self.instantRound = rc

    -- Offene Runden
    H.Separator(P, LIST_TOP + 14)
    local lh = MakeText(P, "GameFontNormal")
    lh:SetPoint("TOPLEFT", 0, LIST_TOP + 8)
    lh:SetText(L.CIRCLE_LIST_HDR)
    self.instantRows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, P)
        row:SetSize(476, 26)
        row:SetPoint("TOPLEFT", 0, LIST_TOP - 12 - (i - 1) * 28)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.text = MakeText(row, "GameFontNormal")
        row.text:SetPoint("LEFT", row, "LEFT", 24, 0)
        row.text:SetWidth(360)
        row.text:SetWordWrap(false)
        row.btn = UI.Button(row, nil, 80, 22, L.CIRCLE_JOIN)
        row.btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.btn:SetScript("OnClick", function() Window:InstantJoin(row.round) end)
        local sep = row:CreateTexture(nil, "ARTWORK")
        sep:SetPoint("BOTTOMLEFT", 0, -1)
        sep:SetPoint("BOTTOMRIGHT", 0, -1)
        sep:SetHeight(1)
        sep:SetColorTexture(unpack(M.colors.line))
        row:Hide()
        self.instantRows[i] = row
    end
    self.instantEmpty = Small(P, 0, LIST_TOP - 16, 476)
    self.instantEmpty:SetText(L.CIRCLE_LIST_EMPTY)
    -- Mehr als 3 offene Runden: mit dem Mausrad blättern (rechts steht "1-3 von 5")
    self.instantOffset = 0
    local wheel = CreateFrame("Frame", nil, P)
    wheel:SetPoint("TOPLEFT", 0, LIST_TOP - 12)
    wheel:SetSize(476, ROWS * 28)
    wheel:EnableMouseWheel(true)
    wheel:SetScript("OnMouseWheel", function(_, delta)
        Window.instantOffset = math.max(0, (Window.instantOffset or 0) - delta)
        Window:RefreshInstant()
    end)
    self.instantWheel = wheel
    self.instantMore = Small(P, 0, LIST_TOP + 8, 476)
    self.instantMore:SetJustifyH("RIGHT")

    -- Bescheid sagen (aus), Status, Regeln
    local yB = LIST_TOP - 12 - ROWS * 28 - 6
    self.instantNotify = H.MakeCheck(P, L.INSTANT_NOTIFY, 0, yB,
        function() return SM.db.circle.notify end, function(v) SM.db.circle.notify = v end)
    self.instantTravel = H.MakeCheck(P, L.INSTANT_TRAVEL, 0, yB - 22,
        function() return SM.db.circle.travel end, function(v) SM.db.circle.travel = v end)
    Tip(self.instantTravel, L.INSTANT_TRAVEL, L.INSTANT_TRAVEL_TT)
    self.instantStatus = MakeText(P, "GameFontNormal")
    self.instantStatus:SetPoint("TOPLEFT", 0, yB - 46)
    self.instantStatus:SetWidth(476)
    self.instantStatus:SetHeight(28)
    self.instantStatus:SetJustifyV("TOP")
    self.instantRules = Small(P, 0, yB - 76, 476)
    self.instantRules:SetText(L.CIRCLE_RULES)
end

function Window:SetInstantStatus(text, color)
    if not self.instantStatus then return end
    color = color or ink
    self.instantStatus:SetTextColor(color[1], color[2], color[3])
    self.instantStatus:SetText(text or "")
end

-- Gewähltes Thema: eigenes (wenn etwas im Feld steht), sonst der Vorschlag
function Window:InstantChoice()
    local db = SM.db.circle
    local own = self.instantOwn and C().CleanTopic(self.instantOwn:GetText() or "") or ""
    if own ~= "" then return 0, own end
    return db.topic or 1, nil
end

-- Sprachchat-Runde eröffnen: über das Spiel ("v") oder Discord ("d")
local function VoiceMode()
    return SM.db.circle.via == "discord" and "d" or "v"
end

-- "Jetzt reden" / "Jetzt schreiben"
function Window:InstantGo(mode)
    SM.db.circle.mode = mode
    if mode == "v" then mode = VoiceMode() end
    local topic, text = self:InstantChoice()
    local ok, msg = C():Search(mode, topic, text)
    self:SetInstantStatus(msg, ok and good or bad)
    if not ok and msg then SM:Print(msg) end
    self:RefreshInstant()
end

-- "Jetzt plaudern": wie zuletzt (Text oder Sprachchat), am Anfang Text
function Window:InstantQuick()
    local mode = SM.db.circle.mode == "v" and "v" or "t"
    local ok, msg = C():QuickChat(mode, mode == "v" and VoiceMode() or "t")
    self:SetInstantStatus(msg, ok and good or bad)
    if not ok and msg then SM:Print(msg) end
    self:RefreshInstant()
end

-- Beitreten (Knopf in der Liste). Eine Discord-Runde sagt vorher, worauf man sich einlässt.
function Window:InstantJoin(r)
    local function join()
        local ok, msg = C():Join(r)
        Window:SetInstantStatus(msg, ok and good or bad)
        Window:RefreshInstant()
    end
    if r and r.mode == "d" and SM.db.circle.via ~= "discord" then
        SM.Confirm:Show(L.INSTANT_DISCORD_ASK, join, L.INSTANT_DISCORD_YES, L.INSTANT_DISCORD_NO)
        return
    end
    join()
end

local function ModeIcon(mode) return ICON[mode] or ICON.t end

-- Discord-Link speichern (Gastgeber) - leer = entfernen
function Window:InstantSaveDiscord()
    local rc = self.instantRound
    local ok, msg = C():SetDiscord(rc.dEdit:GetText())
    self:SetInstantStatus(msg, ok and good or bad)
    if not ok then SM:Print(msg) end
    self:RefreshInstant()
    return ok
end

-- Knopf neben dem Link: Gastgeber speichert, Mitspieler kopiert
function Window:InstantDiscordClick()
    local Ci = C()
    if Ci:Hosting() then return self:InstantSaveDiscord() end
    local m = Ci.member
    if m and m.link then
        SM.CopyDialog:Show(Ci.DiscordURL(m.link), L.CIRCLE_DISCORD_COPY_TITLE, L.CIRCLE_DISCORD_COPY_HINT)
        return true
    end
    return false
end

function Window:RefreshInstant()
    if not self.instantPanel or not self.instantPanel:IsShown() then return end
    local Ci = C()
    if not (Ci and Ci.enabled) then
        for _, c in pairs(self.instantCards) do c:Hide() end
        self.instantRound:Hide()
        for _, r in ipairs(self.instantRows) do r:Hide() end
        self.instantEmpty:SetText(L.CIRCLE_OFF)
        self.instantEmpty:Show()
        return
    end
    self.instantEmpty:SetText(L.CIRCLE_LIST_EMPTY)
    local db = SM.db.circle
    local own, member, joining = Ci.own, Ci.member, Ci.joining
    local inGroup = Ci.InGroup()
    local cur = Ci:Current()
    local busy = own or member or joining or inGroup

    -- Karten oder "Deine Runde"
    local showRound = (own or member) and true or false
    for mode, card in pairs(self.instantCards) do
        if showRound then card:Hide() else
            card:Show()
            local rounds, people = Ci:Stats(mode)
            card.stats:SetText(rounds > 0 and L.INSTANT_STATS:format(rounds, people) or L.INSTANT_STATS_NONE)
            if busy then card.go:Disable() else card.go:Enable() end
        end
    end
    for _, w in ipairs({ self.instantTopicLabel, self.instantTopicBtn, self.instantOwnLabel, self.instantOwn,
                         self.instantViaLabel, self.instantVia.wow, self.instantVia.discord, self.instantQuick }) do
        if showRound then w:Hide() else w:Show() end
    end
    if busy then self.instantQuick:Disable() else self.instantQuick:Enable() end
    for via, b in pairs(self.instantVia) do
        if (db.via or "wow") == via then b:LockHighlight() else b:UnlockHighlight() end
    end
    self.instantTopicBtn:SetText(Ci.TopicName(db.topic or 1))

    local rc = self.instantRound
    if showRound then
        rc:Show()
        rc.icon:SetTexture(ModeIcon(cur.mode))
        rc.title:SetText(L.INSTANT_ROUND_TITLE:format(Ci.TopicName(cur.topic, cur.text)))
        local n = Ci.GroupSize()
        if own then
            local left = math.max(1, math.ceil((Ci.OPEN_TIME - (GetTime() - own.opened)) / 60))
            rc.sub:SetText(L.INSTANT_ROUND_OWN:format(Ci.ModeName(cur.mode), n, left))
        else
            rc.sub:SetText(L.INSTANT_ROUND_IN:format(Ci.ModeName(cur.mode), n, cur.host or "?"))
        end
        local names = Ci:Members()
        rc.members:SetText(#names > 0 and L.INSTANT_MEMBERS:format(table.concat(names, ", ")) or L.INSTANT_WAITING_PEOPLE)
        local hosting = Ci:Hosting()
        rc.hint:SetText((cur.mode == "d" and (hosting and L.INSTANT_HINT_DISCORD_HOST or L.INSTANT_HINT_DISCORD))
            or (cur.mode == "v" and L.INSTANT_HINT_VOICE) or L.INSTANT_HINT_TEXT)
        -- Discord-Zeile nur bei Discord-Runden; die Karte wird dafür etwas höher
        for _, w in ipairs({ rc.dLabel, rc.dEdit, rc.dText, rc.dBtn }) do w:Hide() end
        if cur.mode == "d" then
            rc.dLabel:Show()
            rc.dBtn:Show()
            if hosting then
                rc.dEdit:Show()
                if not (rc.dEdit.HasFocus and rc.dEdit:HasFocus()) then
                    local code = hosting.link or db.discord
                    rc.dEdit:SetText(Ci.ValidCode(code) and Ci.DiscordShort(code) or "")
                end
                rc.dBtn:SetText(L.CIRCLE_DISCORD_SAVE)
                rc.dBtn:Enable()
            else
                rc.dText:Show()
                rc.dText:SetText(cur.link and Ci.DiscordShort(cur.link) or L.CIRCLE_DISCORD_NONE)
                rc.dBtn:SetText(L.CIRCLE_DISCORD_COPY)
                if cur.link then rc.dBtn:Enable() else rc.dBtn:Disable() end
            end
            rc:SetHeight(ROUND_H_D)
        else
            rc:SetHeight(ROUND_H)
        end
        rc.leave:SetText((own and not inGroup) and L.CIRCLE_CLOSE or L.CIRCLE_LEAVE)
        for _, b in ipairs({ rc.hello, rc.topic }) do
            if inGroup then b:Enable() else b:Disable() end
        end
    else
        rc:Hide()
    end
    if joining and not showRound then
        self:SetInstantStatus(L.CIRCLE_WAITING:format(joining.host), ink)
    end

    -- offene Runden
    local topic, text = self:InstantChoice()
    local list = Ci:List(db.mode or "t", topic, text)
    local maxOff = math.max(0, #list - ROWS)
    self.instantOffset = math.min(self.instantOffset or 0, maxOff)
    local off = self.instantOffset
    if #list > ROWS then
        self.instantMore:SetText(L.INSTANT_MORE:format(off + 1, math.min(off + ROWS, #list), #list))
        self.instantMore:Show()
    else
        self.instantMore:Hide()
    end
    for i, row in ipairs(self.instantRows) do
        local r = list[i + off]
        row.round = r
        if r then
            row.icon:SetTexture(ModeIcon(r.mode))
            local line = L.INSTANT_ROW:format(Ci.TopicName(r.topic, r.text), r.n, r.host)
            -- welche Art (Text, WoW-Sprachchat, Discord) - damit niemand überrascht wird
            row.text:SetText(line .. " · " .. Ci.ModeName(r.mode))
            if busy then row.btn:Disable() else row.btn:Enable() end
            row:Show()
        else
            row:Hide()
        end
    end
    if #list == 0 then self.instantEmpty:Show() else self.instantEmpty:Hide() end
    if self.instantNotify.Refresh then self.instantNotify:Refresh() end
    if self.instantTravel.Refresh then self.instantTravel:Refresh() end
end

SM:RegisterCallback("CIRCLE_CHANGED", function()
    if Window.frame and Window.frame:IsShown() and Window.tab == "instant" then Window:RefreshInstant() end
end)
