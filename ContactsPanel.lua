local ADDON, SM = ...
local L = SM.L
local M = SM.Media
local UI = SM.UI
local Window = SM.Window
local H = Window.H

-- Tab „Kontakte“: Spieler, mit denen du über Treffpunkte, Instant-Runden oder Winken zusammengekommen bist.
-- Klick = anflüstern, Rechtsklick = Menü (Flüstern, Einladen, Danke sagen, Zur Freundesliste, Zuwinken,
-- Ignorieren, Entfernen, Melden, Mit auswählen). Strg+Klick = mehrere wählen.
-- Darunter nur noch "Ich möchte reden" (braucht keinen Kontakt).
local ROWS, ROW_H = 7, 30
local LIST_TOP = 22
local ink, good, bad = M.colors.ink, M.colors.good, M.colors.bad

Window.contactOffset = 0
Window.contactSel = nil   -- Name des gewählten Kontakts
Window.contactMulti = {}  -- mehrere gewählt (Strg+Klick): Name -> true (test8b)

function Window:BuildContactsPanel(parent)
    local P = CreateFrame("Frame", nil, parent)
    P:SetAllPoints(parent)
    P:Hide()
    self.contactsPanel = P

    local hdr = H.MakeText(P, "GameFontNormal")
    hdr:SetPoint("TOPLEFT", 0, 0)
    hdr:SetText(L.CONTACTS_HDR)

    self.contactRows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, P)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", P, "TOPLEFT", 0, -LIST_TOP - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", P, "TOPRIGHT", 0, -LIST_TOP - (i - 1) * ROW_H)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(row)
        hl:SetColorTexture(unpack(M.colors.hover))
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints(row)
        row.sel:SetColorTexture(M.wood.accent[1], M.wood.accent[2], M.wood.accent[3], 0.30)
        row.sel:Hide()
        row.line1 = H.MakeText(row, "GameFontNormal")
        row.line1:SetPoint("TOPLEFT", 8, -2)
        row.line1:SetPoint("TOPRIGHT", -110, -2)
        row.line1:SetHeight(14)
        row.line1:SetWordWrap(false)
        row.when = H.MakeText(row, "GameFontNormalSmall")
        row.when:SetPoint("TOPRIGHT", -6, -3)
        row.when:SetWidth(100)
        row.when:SetJustifyH("RIGHT")
        row.line2 = H.MakeText(row, "GameFontNormalSmall")
        row.line2:SetPoint("TOPLEFT", 8, -17)
        row.line2:SetPoint("TOPRIGHT", -6, -17)
        row.line2:SetHeight(12)
        row.line2:SetWordWrap(false)
        local sep = row:CreateTexture(nil, "ARTWORK")
        sep:SetPoint("BOTTOMLEFT", 0, 0)
        sep:SetPoint("BOTTOMRIGHT", 0, 0)
        sep:SetHeight(1)
        sep:SetColorTexture(unpack(M.colors.line))
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        -- Klick = anflüstern, Rechtsklick = Menü, Strg+Klick = mehrere wählen (test8b: zum Aufräumen)
        row:SetScript("OnClick", function(r, button)
            if not r.entry then return end
            local name = r.entry.name
            if button ~= "RightButton" and IsControlKeyDown and IsControlKeyDown() then
                Window:ContactToggleMulti(name)
            elseif button == "RightButton" then
                if Window:ContactMultiCount() > 0 and Window.contactMulti[name] then
                    Window:ContactMultiMenu(r)
                else
                    Window.contactMulti = {}
                    Window.contactSel = name
                    Window:ContactMenu(r, r.entry)
                end
            else
                Window.contactMulti = {}
                Window.contactSel = name
                Window:ContactAction("whisper", r.entry)
            end
            Window:RefreshContacts()
        end)
        row:SetScript("OnEnter", function(r)
            if not r.entry then return end
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            GameTooltip:AddLine(r.entry.name, 1, 0.82, 0)
            GameTooltip:AddLine(L.CT_ROW_HINT, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        self.contactRows[i] = row
    end

    self.contactEmpty = H.MakeText(P, "GameFontNormal")
    self.contactEmpty:SetPoint("TOP", P, "TOP", 0, -LIST_TOP - 60)
    self.contactEmpty:SetWidth(420)
    self.contactEmpty:SetJustifyH("CENTER")
    self.contactEmpty:SetText(L.CONTACTS_EMPTY)

    local listBottom = LIST_TOP + ROWS * ROW_H
    self.contactPage = H.MakeText(P, "GameFontNormalSmall")
    self.contactPage:SetPoint("TOPLEFT", 6, -listBottom - 2)

    local y = -listBottom - 22
    -- "Ich möchte reden" braucht keinen ausgewählten Kontakt
    local talk = UI.Button(P, H.Name("Contact"), 220, 24, L.EAR_ASK_SHORT)
    talk:SetPoint("TOPLEFT", 0, y)
    talk:SetScript("OnClick", function() SM.EarUI:AskNow() end)
    talk:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:AddLine(L.EAR_ASK_BTN, 1, 0.82, 0)
        GameTooltip:AddLine(L.EAR_ASK_TT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    talk:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.talkBtn = talk

    self.contactStatus = H.MakeText(P, "GameFontNormal")
    self.contactStatus:SetPoint("TOPLEFT", 0, y - 34)
    self.contactStatus:SetWidth(470)
    self.contactStatus:SetHeight(30)
    self.contactStatus:SetJustifyV("TOP")

    -- (test8b: der Hinweis unten steht jetzt im Tooltip jeder Zeile - weniger Text auf dem Pergament)

    P:EnableMouseWheel(true)
    P:SetScript("OnMouseWheel", function(_, delta)
        Window.contactOffset = math.max(0, Window.contactOffset - delta)
        Window:RefreshContacts()
    end)
end

-- Was man mit einem Kontakt tun kann (Klick, Menü)
function Window:ContactAction(key, e)
    if not e then return end
    local C = SM.Contacts
    if key == "whisper" then
        C:Whisper(e)
        self:SetContactStatus(L.CT_WHISPER_OK:format(e.name), ink)
    elseif key == "invite" then
        local ok = C:Invite(e)
        self:SetContactStatus((ok and L.MSG_INVITED or L.MSG_INVITE_FAIL):format(e.name), ok and good or bad)
    elseif key == "thanks" then
        -- Danke für die Gruppe (früher auf der Danke-Karte)
        SM:SendChat(L.THANKS_TEXT, "WHISPER", e.full or e.name)
        self:SetContactStatus(L.CT_THANKS_OK:format(e.name), good)
    elseif key == "friend" then
        local ok = C:AddFriend(e)
        self:SetContactStatus((ok and L.CT_FRIEND_OK or L.CT_FRIEND_FAIL):format(e.name), ok and good or bad)
        self:RefreshContacts()
    elseif key == "wave" then
        local ok, msg = SM.Social:Wave(e.name, e.full or e.name)
        self:SetContactStatus(msg, ok and good or ink)
    elseif key == "ignore" then
        SM.Confirm:Show(L.CT_IGNORE_ASK:format(e.name), function()
            local ok = C:Ignore(e)
            if ok then Window.contactSel = nil end
            Window:SetContactStatus((ok and L.CT_IGNORE_OK or L.CT_IGNORE_FAIL):format(e.name), ok and ink or bad)
            Window:RefreshContacts()
        end)
    elseif key == "remove" then
        C:Remove(e.name)
        self.contactSel = nil
        self:SetContactStatus(L.CT_REMOVE_OK:format(e.name), ink)
        self:RefreshContacts()
    elseif key == "report" then
        local ok, why = SM.Guard:CanReport(e.name)
        if ok then SM.Guard:ShowDialog(e.name) else self:SetContactStatus(why, bad) end
    end
end

function Window:ContactMenu(row, e)
    local function A(key) return function() Window:ContactAction(key, e) end end
    local isFriend = e.friend or SM.Contacts:IsFriend(e.name)
    SM.UI.Menu(row, e.name, {
        { text = L.CT_WHISPER, fn = A("whisper") },
        { text = L.CT_INVITE, fn = A("invite") },
        { text = L.CT_THANKS, tip = L.CT_THANKS_TT, fn = A("thanks") },
        { text = L.CT_FRIEND, disabled = isFriend and true or false, fn = A("friend") },
        { text = L.CT_WAVE, tip = L.CT_WAVE_TT, fn = A("wave") },
        { text = L.CT_IGNORE, fn = A("ignore") },
        { text = L.CT_REMOVE, fn = A("remove") },
        { text = L.CT_REPORT, tip = L.CT_REPORT_TT, fn = A("report") },
        { text = L.CT_MULTI_ON, tip = L.CT_MULTI_TT, fn = function()
            Window:ContactToggleMulti(e.name)
            Window:RefreshContacts()
        end },
    })
end

---------------------------------------------------------------------------
-- Mehrere Kontakte auf einmal (test8b): Strg+Klick oder "Mit auswählen", dann Rechtsklick ->
-- Entfernen (n), Einladen (n), Zuwinken (n), Alle abwählen. So lassen sich die automatisch
-- gemerkten Kontakte schnell aufräumen.
---------------------------------------------------------------------------
function Window:ContactMultiCount()
    local n = 0
    for _ in pairs(self.contactMulti or {}) do n = n + 1 end
    return n
end

function Window:ContactToggleMulti(name)
    if not name then return end
    self.contactMulti = self.contactMulti or {}
    -- der bisher einzeln gewählte Kontakt kommt mit in die Auswahl
    if self:ContactMultiCount() == 0 and self.contactSel and self.contactSel ~= name then
        self.contactMulti[self.contactSel] = true
    end
    if self.contactMulti[name] then self.contactMulti[name] = nil else self.contactMulti[name] = true end
    self.contactSel = nil
end

-- die gewählten Kontakte (in der Reihenfolge der Liste)
function Window:ContactMultiEntries()
    local out = {}
    for _, e in ipairs(SM.Contacts:List()) do
        if self.contactMulti[e.name] then out[#out + 1] = e end
    end
    return out
end

function Window:ContactMultiMenu(owner)
    local list = self:ContactMultiEntries()
    local n = #list
    SM.UI.Menu(owner, L.CT_MULTI_TITLE:format(n), {
        { text = L.CT_MULTI_REMOVE:format(n), fn = function() Window:ContactMultiAction("remove") end },
        { text = L.CT_MULTI_INVITE:format(n), fn = function() Window:ContactMultiAction("invite") end },
        { text = L.CT_MULTI_WAVE:format(n), tip = L.CT_WAVE_TT, fn = function() Window:ContactMultiAction("wave") end },
        { text = L.CT_MULTI_NONE, fn = function() Window.contactMulti = {}; Window:RefreshContacts() end },
    })
end

function Window:ContactMultiAction(key)
    local list = self:ContactMultiEntries()
    if #list == 0 then return 0 end
    local C = SM.Contacts
    if key == "remove" then
        SM.Confirm:Show(L.CT_REMOVE_ASK_N:format(#list), function()
            for _, e in ipairs(list) do C:Remove(e.name) end
            Window.contactMulti, Window.contactSel = {}, nil
            Window:SetContactStatus(L.CT_REMOVED_N:format(#list), ink)
            Window:RefreshContacts()
        end)
        return #list
    end
    local n = 0
    for _, e in ipairs(list) do
        if key == "invite" then
            if C:Invite(e) then n = n + 1 end
        elseif key == "wave" then
            if SM.Social:Wave(e.name, e.full or e.name) then n = n + 1 end
        end
    end
    self:SetContactStatus((key == "invite" and L.CT_INVITED_N or L.CT_WAVED_N):format(n), n > 0 and good or bad)
    self:RefreshContacts()
    return n
end

function Window:SetContactStatus(text, color)
    color = color or ink
    self.contactStatus:SetTextColor(color[1], color[2], color[3])
    self.contactStatus:SetText(text or "")
end

function Window:RefreshContacts()
    if not self.contactsPanel then return end
    local C = SM.Contacts
    local list = C:List()
    local maxOffset = math.max(0, #list - ROWS)
    if self.contactOffset > maxOffset then self.contactOffset = maxOffset end
    if self.contactSel and not C:Get(self.contactSel) then self.contactSel = nil end

    for i = 1, ROWS do
        local row, e = self.contactRows[i], list[self.contactOffset + i]
        row.entry = e
        if e then
            local friend = (e.friend or C:IsFriend(e.name)) and ("  " .. SM.Hex("2A6F2A") .. L.CT_IS_FRIEND .. "|r") or ""
            row.line1:SetText(e.name .. friend)
            row.when:SetText(C.WhenText(e.last))
            local src = C.SourceText(e)
            if (e.together or 0) > 0 then src = src .. "  " .. SM.Hex("2A6F2A") .. L.CT_TOGETHER:format(e.together) .. "|r" end
            row.line2:SetText(src)
            if e.name == self.contactSel or self.contactMulti[e.name] then row.sel:Show() else row.sel:Hide() end
            row:Show()
        else
            row:Hide()
        end
    end

    if #list == 0 then self.contactEmpty:Show() else self.contactEmpty:Hide() end
    if #list > ROWS then
        self.contactPage:SetText(L.LIST_PAGE:format(self.contactOffset + 1, math.min(self.contactOffset + ROWS, #list), #list))
    else
        self.contactPage:SetText("")
    end
end

SM:RegisterCallback("CONTACTS_CHANGED", function()
    if Window.frame and Window.frame:IsShown() and Window.tab == "contacts" then Window:RefreshContacts() end
end)
