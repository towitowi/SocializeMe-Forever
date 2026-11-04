local ADDON, SM = ...
local L = SM.L
local M = SM.Media

-- Kleiner eigener Dialog zum Kopieren von Links und Texten. WoW kann nichts direkt in die
-- Zwischenablage legen: Der Text erscheint markiert, du drückst Strg+C.
-- Zweite Art (AskPaste): ein leeres Feld zum Einfügen mit Strg+V, z. B. für geteilte Orte.
-- (Eigener Rahmen statt StaticPopup, weil sich dessen Aufbau zwischen den Clients ändert.)
local Copy = {}
SM.CopyDialog = Copy

local ink = M.colors.ink

function Copy:Create()
    if self.frame then return end

    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "SocializeMeForeverCopyDialog", UIParent, template)
    self.frame = f
    f:SetSize(470, 130)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(fr) SM.UI.DragStart(fr) end)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    if f.SetBackdrop then
        f:SetBackdrop({
            edgeFile = M.tex.border,
            edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    local paper = f:CreateTexture(nil, "BACKGROUND")
    paper:SetPoint("TOPLEFT", 11, -11)
    paper:SetPoint("BOTTOMRIGHT", -11, 11)
    paper:SetColorTexture(unpack(M.colors.parchment))

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -24)
    title:SetTextColor(ink[1], ink[2], ink[3])
    title:SetShadowOffset(0, 0)
    title:SetText(L.COPY_TITLE)
    self.title = title

    local eb = SM.UI.EditBox(f, "SocializeMeForeverCopyEditBox", 410, 24)
    eb:SetPoint("TOP", 0, -50)
    eb:SetMaxLetters(300)
    self.editBox = eb

    -- Der Link soll nicht versehentlich verändert werden (nur beim Kopieren).
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput and Copy.url and not Copy.onPaste then
            self:SetText(Copy.url)
            self:HighlightText()
        end
    end)
    eb:SetScript("OnEditFocusGained", function(self) if not Copy.onPaste then self:HighlightText() end end)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnEnterPressed", function() if Copy.onPaste then Copy:Accept() else f:Hide() end end)
    -- Nach Strg+C (bzw. Cmd+C) schließt sich der Dialog von selbst.
    eb:SetScript("OnKeyUp", function(_, key)
        local ctrl = IsControlKeyDown() or (IsMetaKeyDown and IsMetaKeyDown())
        if ctrl and key == "C" and not Copy.onPaste then f:Hide() end
    end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOP", 0, -78)
    hint:SetWidth(410)
    hint:SetTextColor(M.colors.soft[1], M.colors.soft[2], M.colors.soft[3])
    hint:SetShadowOffset(0, 0)
    self.hint = hint

    local ok = SM.UI.Button(f, "SocializeMeForeverCopyDone", 120, 24, L.COPY_DONE)
    ok:SetPoint("BOTTOM", 0, 22)
    ok:SetScript("OnClick", function() f:Hide() end)
    self.doneButton = ok

    -- Zum Einfügen: Übernehmen / Abbrechen
    local accept = SM.UI.Button(f, "SocializeMeForeverPasteAccept", 120, 24, L.PASTE_ACCEPT)
    accept:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 22)
    accept:SetScript("OnClick", function() Copy:Accept() end)
    self.acceptButton = accept
    local cancel = SM.UI.Button(f, "SocializeMeForeverPasteCancel", 120, 24, L.CONFIRM_NO)
    cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 22)
    cancel:SetScript("OnClick", function() f:Hide() end)
    self.cancelButton = cancel
    f:SetScript("OnHide", function() Copy.onPaste = nil end)

    tinsert(UISpecialFrames, "SocializeMeForeverCopyDialog")
    f:Hide()
end

-- Höhe nach dem Hinweis richten, damit die Knöpfe ihn nicht verdecken (test7, Einfügen-Beispiel)
function Copy:Fit()
    local h = self.hint:GetText() ~= "" and math.ceil(self.hint:GetStringHeight() or 12) or 0
    self.frame:SetHeight(math.max(130, 78 + h + 8 + 24 + 22))
end

-- Text zum Kopieren zeigen (title und hint sind freiwillig)
function Copy:Show(url, title, hint)
    self:Create()
    self.onPaste = nil
    self.url = url
    self.title:SetText(title or L.COPY_TITLE)
    self.hint:SetText(hint or "")
    self.doneButton:Show(); self.acceptButton:Hide(); self.cancelButton:Hide()
    self.editBox:SetMaxLetters(math.max(300, #tostring(url or "")))
    self.editBox:SetText(url)
    self:Fit()
    self.frame:Show()
    self.editBox:SetFocus()
    self.editBox:HighlightText()
end

-- Leeres Feld zum Einfügen. onAccept(text) gibt ok, msg zurück; bei ok schließt der Dialog.
function Copy:AskPaste(title, hint, onAccept)
    self:Create()
    self.url = nil
    self.title:SetText(title)
    self.hint:SetText(hint or "")
    self.doneButton:Hide(); self.acceptButton:Show(); self.cancelButton:Show()
    self.editBox:SetMaxLetters(2000)
    self.editBox:SetText("")
    self:Fit()
    self.frame:Show()
    self.onPaste = onAccept
    self.editBox:SetFocus()
end

function Copy:Accept()
    local fn = self.onPaste
    if not fn then self.frame:Hide(); return end
    local ok, msg = fn(self.editBox:GetText() or "")
    if msg then self.hint:SetText(msg); self:Fit() end
    if ok then self.frame:Hide() end
end

---------------------------------------------------------------------------
-- Eigene Chat-Links (test8b): |Hsmforever:discord:<code>|h[discord.gg/<code>]|h
-- Ein Klick darauf im Chat öffnet dieses Kopierfeld. WoW kennt den Link-Typ nicht; deshalb
-- fangen wir ihn an zwei Stellen ab (je nach Client-Version kommt er an der einen oder anderen
-- vorbei) - und öffnen das Feld nur einmal pro Klick.
---------------------------------------------------------------------------
function Copy:HandleLink(link)
    local code = type(link) == "string" and link:match("^smforever:discord:([%w%-]+)$")
    if not code then return false end
    local now = GetTime()
    if self.lastLink == link and self.lastLinkAt and (now - self.lastLinkAt) < 0.3 then return true end
    self.lastLink, self.lastLinkAt = link, now
    self:Show(SM.Circle and SM.Circle.DiscordURL(code) or ("https://discord.gg/" .. code),
        L.CIRCLE_DISCORD_COPY_TITLE, L.CIRCLE_DISCORD_COPY_HINT)
    return true
end

function Copy:HookLinks()
    if self.linksHooked then return end
    self.linksHooked = true
    -- 1) Der Tooltip, den das Spiel für unbekannte Links öffnen würde: leer lassen, Feld zeigen
    local tt = ItemRefTooltip
    if tt and type(tt.SetHyperlink) == "function" then
        local orig = tt.SetHyperlink
        tt.SetHyperlink = function(t, link, ...)
            if Copy:HandleLink(link) then
                if t.Hide then t:Hide() end
                return
            end
            return orig(t, link, ...)
        end
    end
    -- 2) Nach dem Klick (falls der Client unbekannte Links vorher schon abweist)
    if type(hooksecurefunc) == "function" and type(SetItemRef) == "function" then
        hooksecurefunc("SetItemRef", function(link)
            if Copy:HandleLink(link) and ItemRefTooltip and ItemRefTooltip.Hide then ItemRefTooltip:Hide() end
        end)
    end
end

local ev = {}
SM:RegisterEvent(ev, "PLAYER_LOGIN", function() Copy:HookLinks() end)
