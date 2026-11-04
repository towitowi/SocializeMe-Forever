local ADDON, SM = ...
local L = SM.L
local Q = SM.QuestInfo

-- Das Tooltip eines Beacons. Es wird von der Liste im Fenster UND von den Karten-Pins benutzt,
-- damit beide dasselbe zeigen (Quest, Stand, Belohnungen, Ort, Entfernung).
local Tip = {}
SM.BeaconTip = Tip

-- Quest-Name in deiner Sprache, wenn dein Spiel ihn kennt.
function Tip.QuestName(b, byID)
    return Q:LocalTitle(b.questID, byID) or b.questName
end

-- Fortschritt als Text; gibt farbigen Text (Pergament-tauglich) und den reinen Text zurück.
function Tip.ProgressColored(b)
    local txt = Q.ProgressText(b.done or 0, b.total or 0, b.qstate or 0)
    local st = b.qstate or 0
    local col = (st == Q.STATE_READY) and "2A6F2A" or (st >= Q.STATE_TURNEDIN) and "6E6E64" or "22140A"
    return "|cff" .. col .. txt .. "|r", txt
end

local function HexToRGB(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

-- owner: das Fenster-Element, an dem das Tooltip hängt. mode: "row" (Liste) oder "pin" (Karte).
function Tip:Show(owner, b, anchor, mode)
    if not b then return end
    mode = mode or "row"
    self.owner, self.beacon, self.anchor, self.mode = owner, b, anchor, mode
    local _, byID = Q:ScanLog()

    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    local name = b.questID and Tip.QuestName(b, byID)
    GameTooltip:AddLine((name and name ~= "") and name or b.title, 1, 1, 1)
    if name and name ~= "" and b.title ~= "" and b.title ~= name and b.title ~= b.questName then
        GameTooltip:AddLine(b.title, 0.85, 0.85, 0.85)
    end
    GameTooltip:AddLine(L["KIND_" .. b.kind])

    -- Wo ist die Quest zu machen? Liegt der Treffpunkt woanders, stehen beide Orte da.
    local place, mapName, differs = SM.Beacon:Where(b, byID)
    if differs then
        GameTooltip:AddLine(L.TT_QUEST_ZONE:format(place), 1, 0.82, 0)
        GameTooltip:AddLine(L.TT_MEET:format(mapName, b.x * 100, b.y * 100), 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine(("%s (%.1f, %.1f)"):format(mapName, b.x * 100, b.y * 100), 0.8, 0.8, 0.8)
    end
    local eta = SM.Eta and SM.Eta.enabled and SM.Eta:Describe(b)
    if eta then GameTooltip:AddLine(eta, 0.75, 0.9, 1) end
    -- Sprachchat-Stufe und "eher ruhig": damit niemand überrascht wird
    local level = SM.Social.VoiceLevel(b.voice)
    GameTooltip:AddLine(SM.Social.VoiceLine(level), level > 0 and 0.4 or 0.8, level > 0 and 0.9 or 0.8, level > 0 and 0.4 or 0.8, true)
    SM.Social.AddFlagLines(b)
    if not b.own then SM.Social.AddKnownLine(SM.Social:Known(b.sender)) end

    if b.questID then
        GameTooltip:AddLine(" ")
        local _, plain = Tip.ProgressColored(b)
        if b.own then
            GameTooltip:AddLine(L.TT_OWN_STAND:format(plain), 0.9, 0.9, 0.6)
        else
            GameTooltip:AddLine(L.TT_THEIR_STAND:format(b.sender, plain), 0.9, 0.9, 0.6)
            local stand = Q:OwnStand(b.questID, byID)
            if stand then
                local r, g, bl = HexToRGB(SM.Media.colors.stand[stand])
                -- dunkle Töne sind im Tooltip schlecht lesbar: etwas aufhellen
                GameTooltip:AddLine(L.TT_OWN_STAND:format(L["STAND_" .. stand]),
                    math.min(1, r + 0.3), math.min(1, g + 0.3), math.min(1, bl + 0.3))
            end
        end
    end

    -- Wer ist auf dem Weg zu deinem Beacon?
    if b.own and SM.Eta and SM.Eta.enabled then
        local lines = SM.Eta:ComingLines(b)
        if #lines > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L.TT_COMING_HDR, 1, 0.82, 0)
            for _, line in ipairs(lines) do GameTooltip:AddLine(line, 0.85, 1, 0.85) end
        end
    end

    GameTooltip:AddLine(" ")
    if b.own then
        GameTooltip:AddLine(L.TT_OWN_BEACON, 0.6, 0.6, 0.6)
    else
        -- Liste und Karte: gleiche Bedienung
        GameTooltip:AddLine(L.TT_HINT, 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

function Tip:Hide()
    self.owner, self.beacon = nil, nil
    GameTooltip:Hide()
end

-- Neu aufbauen, wenn sich etwas ändert, während das Tooltip offen ist.
function Tip:Refresh()
    if not (self.owner and self.beacon) then return end
    -- Gehört das Tooltip inzwischen jemand anderem, nichts überschreiben.
    if GameTooltip.GetOwner and GameTooltip:GetOwner() ~= self.owner then
        self.owner, self.beacon = nil, nil
        return
    end
    self:Show(self.owner, self.beacon, self.anchor, self.mode)
end

-- Item-Daten (Belohnungen) sind nachgeladen

---------------------------------------------------------------------------
-- Bedienung - überall gleich (Liste und Karte), ohne Tastenkombinationen:
--   Klick (links oder rechts) = Auswahl (Weg zeigen, Ich komme, Grüßen, Zuwinken, Einladen, Melden).
--   Tip:Click (sofort Weg zeigen) bleibt für Stellen, an denen es nur das eine gibt.
-- out(text, ok) meldet das Ergebnis (in der Liste die Statuszeile, auf der Karte der Chat).
---------------------------------------------------------------------------
local function Out(out, text, ok)
    if not text or text == "" then return end
    if out then out(text, ok) else SM:Print(text) end
end

function Tip:Click(b, out)
    if not b then return end
    if b.own then Out(out, L.TT_OWN_BEACON, true) return end
    if SM.Eta and SM.Eta.enabled then
        local ok, msg = SM.Eta:Go(b, false)
        Out(out, msg, ok)
    else
        local sent = SM.Beacon:Greet(b)
        Out(out, (sent and L.MSG_GREETED or L.MSG_GREET_WAIT):format(b.sender), sent)
    end
end

function Tip:Menu(owner, b, out)
    if not b then return end
    local Bc = SM.Beacon
    if b.own then
        SM.UI.Menu(owner, L.ROW_OWN, {
            { text = L.FORM_CANCEL, fn = function()
                local n = Bc:CancelOwn()
                Out(out, n > 0 and L.BEACON_CANCELLED or L.BEACON_NOCANCEL, true)
            end },
        })
        return
    end
    local eta = SM.Eta and SM.Eta.enabled
    local entries = {
        { text = L.PLACE_GO, disabled = not eta, fn = function()
            local ok, msg = SM.Eta:Go(b, false); Out(out, msg, ok)
        end },
        { text = L.MENU_COMING, disabled = not eta, tip = L.MENU_COMING_TT, fn = function()
            local ok, msg = SM.Eta:Go(b, true); Out(out, msg, ok)
        end },
        { text = L.MENU_GREET, tip = L.MENU_GREET_TT, fn = function()
            local sent = Bc:Greet(b)
            Out(out, (sent and L.MSG_GREETED or L.MSG_GREET_WAIT):format(b.sender), sent)
        end },
        { text = L.CT_WAVE, tip = L.MENU_WAVE_TT, fn = function()
            local ok, msg = SM.Social:Wave(b.sender, b.from or b.sender); Out(out, msg, ok)
        end },
        { text = L.CT_INVITE, fn = function()
            local ok = Bc:Invite(b)
            Out(out, (ok and L.MSG_INVITED or L.MSG_INVITE_FAIL):format(b.sender), ok)
        end },
        { text = L.CT_REPORT, tip = L.CT_REPORT_TT, fn = function() SM.Guard:ShowDialog(b.sender, b) end },
    }
    SM.UI.Menu(owner, b.sender, entries)
end
