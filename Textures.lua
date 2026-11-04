local ADDON, SM = ...

-- Zentrale Stelle für Look & Feel. Hier kannst du später echte Pergament-
-- oder Holztexturen eintragen (eigene Dateien in Media/ ablegen und den
-- Pfad hier setzen, z. B. "Interface\\AddOns\\SocializeMeForever\\Media\\parchment").
SM.Media = {
    tex = {
        border  = "Interface\\DialogFrame\\UI-DialogBox-Border",
        -- Kompass des Autors (eigenes Bild, Media\\compass.tga). Zeigt der Button nur ein
        -- grünes Quadrat, wurde das Spiel nach dem Einspielen nicht neu gestartet.
        minimap = "Interface\\AddOns\\SocializeMeForever\\Media\\compass",
        pin     = "Interface\\Icons\\Spell_Fire_Fireball02", -- Beacon-Pins auf Karte und Minimap (Flamme)
        minimapBorder = "Interface\\Minimap\\MiniMap-TrackingBorder",
        -- Wegweiser-Pfeil (zeigt bei Drehung 0 nach oben). Erscheint ein Quadrat,
        -- fehlt der Pfad auf deinem Client: z. B. "Interface\\Minimap\\ROTATING-MINIMAPARROW" probieren.
        arrow   = "Interface\\Minimap\\MinimapArrow",
    },
    colors = {
        parchment = { 0.93, 0.84, 0.65, 1 },   -- Pergament-Hintergrund
        wood      = { 0.30, 0.17, 0.07, 1 },   -- Titelleiste
        ink       = { 0.22, 0.12, 0.04 },      -- Textfarbe auf Pergament
        line      = { 0.35, 0.20, 0.08, 0.40 },-- Trennlinien
        hover     = { 1.00, 0.80, 0.40, 0.25 },-- Zeilen-Hover
        field     = { 0.97, 0.93, 0.80 },      -- Eingabefelder (heller als das Pergament)
        good      = { 0.10, 0.40, 0.10 },
        bad       = { 0.60, 0.10, 0.10 },
        soft      = { 0.40, 0.28, 0.15 },      -- Nebentext (Hinweise, Untertitel)
        head      = { 0.48, 0.29, 0.00 },      -- Kapitel-Überschriften (Geschichten)
        card      = { 0.89, 0.79, 0.58, 1 },   -- Karten auf dem Pergament (Instant)
        panel     = { 0.97, 0.92, 0.78, 1 },   -- helle Klapp-Listen (Quest-Auswahl)
        tip       = { 0.93, 0.86, 0.70, 1 },   -- Erst-Tipp-Leiste
        off       = { 0.55, 0.50, 0.42 },      -- ausgegraute Menüeinträge
        grey      = { 0.45, 0.40, 0.33 },      -- graue Schalter (nur in Forever)
        warn      = { 0.55, 0.12, 0.10 },      -- Warnungen im Melde-Fenster
        shade     = { 0.35, 0.20, 0.08, 0.18 },-- Schatten oben in Eingabefeldern
        kind = {                                -- Farben der Beacon-Arten (Hex)
            quest = "8B1A1A",
            campfire = "B5541B",               -- Lagerfeuer: einfach zusammen sein und reden
        },
        -- Eigener Stand zu einer Quest (Farbbalken links in der Liste, Hex für Text)
        stand = {
            none  = "C98A1B",   -- noch nicht angenommen (Bernstein)
            log   = "2F7D2F",   -- im eigenen Questlog (Grün)
            ready = "2F7D2F",   -- abgabebereit (Grün)
            done  = "8A8A80",   -- schon erledigt (Grau)
        },
        -- dieselben Zustände als Text auf Pergament (dunkler, damit gut lesbar)
        standText = {
            none  = "96600A",
            log   = "2A6F2A",
            ready = "2A6F2A",
            done  = "6E6E64",
        },
    },
    -- Holz-Knöpfe: flach, dunkler Rand, helleres Holz bei Hover/Auswahl
    wood = {
        normal   = { 0.36, 0.21, 0.09 },
        hover    = { 0.47, 0.29, 0.13 },
        down     = { 0.26, 0.15, 0.06 },
        selected = { 0.58, 0.37, 0.17 },
        disabled = { 0.30, 0.25, 0.20 },
        border   = { 0.12, 0.07, 0.03 },
        light    = { 0.62, 0.42, 0.22 },   -- feine Oberkante
        dark     = { 0.20, 0.11, 0.04 },   -- feine Unterkante
        accent   = { 0.93, 0.70, 0.27 },   -- Streifen unter gewähltem Knopf
        text     = { 0.99, 0.93, 0.76 },
        textOff  = { 0.62, 0.57, 0.50 },
        closeHover = { 0.62, 0.17, 0.12 },
    },
}

---------------------------------------------------------------------------
-- Skins (test8b): fertige Farbsätze für alle Fenster des Addons. "parchment" ist der Standard
-- (die Werte oben). Ein Skin nennt nur, was er ändert; der Rest kommt vom Pergament.
-- Übernommen wird beim Laden (vor dem Aufbau der Fenster) - darum gilt ein neuer Skin nach
-- "Neu laden". Dazu die Durchsichtigkeit der Hintergründe (50-100 %).
---------------------------------------------------------------------------
local M = SM.Media
SM.SKIN_ORDER = { "parchment", "night", "midnight", "clear", "horde", "alliance", "druid" }

local function Copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and Copy(v) or v end
    return c
end
-- der Standard, bevor irgendein Skin etwas ändert
M.base = { colors = Copy(M.colors), wood = Copy(M.wood) }

M.SKINS = {
    parchment = {},
    -- Nacht: dunkles Papier, dunkles Holz, helle Schrift
    night = {
        colors = {
            parchment = { 0.16, 0.14, 0.13, 1 }, wood = { 0.09, 0.08, 0.07, 1 },
            ink = { 0.91, 0.86, 0.77 }, soft = { 0.72, 0.64, 0.52 }, head = { 0.96, 0.76, 0.40 },
            line = { 0.85, 0.75, 0.60, 0.22 }, hover = { 1.00, 0.85, 0.50, 0.14 },
            field = { 0.25, 0.22, 0.20 }, good = { 0.50, 0.82, 0.48 }, bad = { 0.96, 0.48, 0.42 },
            card = { 0.22, 0.20, 0.18, 1 }, panel = { 0.21, 0.19, 0.17, 1 }, tip = { 0.24, 0.21, 0.18, 1 },
            off = { 0.50, 0.47, 0.42 }, grey = { 0.58, 0.54, 0.48 }, warn = { 0.96, 0.48, 0.42 },
            shade = { 0, 0, 0, 0.30 },
            kind = { quest = "D85A50", campfire = "E08848" },
            stand = { none = "D9A03A", log = "5FB85F", ready = "5FB85F", done = "8A8A80" },
            standText = { none = "E0A848", log = "78C878", ready = "78C878", done = "A8A89E" },
        },
        -- farbige Wörter in Texten (für helles Papier gedacht) auf dunklem Papier heller
        hexMap = { ["7A4A00"] = "E0B060", ["2F5D1F"] = "80C870", ["8B1A1A"] = "E87868", ["2A6F2A"] = "78C878",
                   ["5A3A10"] = "D8C0A0", ["1F5D7A"] = "78B8E8", ["96600A"] = "E0A848" },
        wood = {
            normal = { 0.23, 0.20, 0.18 }, hover = { 0.31, 0.27, 0.23 }, down = { 0.15, 0.13, 0.12 },
            selected = { 0.40, 0.32, 0.22 }, disabled = { 0.19, 0.18, 0.17 }, border = { 0.04, 0.04, 0.03 },
            light = { 0.40, 0.35, 0.30 }, dark = { 0.10, 0.09, 0.08 }, text = { 0.95, 0.90, 0.80 },
            textOff = { 0.50, 0.47, 0.42 },
        },
    },
    -- Mitternachtsblau: dunkles Blau, helle Schrift, silbrig-goldene Akzente (test8b)
    midnight = {
        colors = {
            parchment = { 0.09, 0.12, 0.21, 1 }, wood = { 0.05, 0.07, 0.14, 1 },
            ink = { 0.88, 0.91, 0.97 }, soft = { 0.66, 0.72, 0.86 }, head = { 0.95, 0.82, 0.48 },
            line = { 0.70, 0.78, 0.95, 0.22 }, hover = { 0.55, 0.70, 1.00, 0.16 },
            field = { 0.15, 0.19, 0.30 }, good = { 0.52, 0.85, 0.58 }, bad = { 0.98, 0.52, 0.48 },
            card = { 0.13, 0.17, 0.28, 1 }, panel = { 0.12, 0.16, 0.26, 1 }, tip = { 0.15, 0.19, 0.31, 1 },
            off = { 0.48, 0.52, 0.62 }, grey = { 0.58, 0.62, 0.72 }, warn = { 0.98, 0.52, 0.48 },
            shade = { 0, 0, 0, 0.30 },
            kind = { quest = "E06A60", campfire = "E8944E" },
            stand = { none = "D9A03A", log = "5FB86F", ready = "5FB86F", done = "8A90A0" },
            standText = { none = "E6B050", log = "7CCB88", ready = "7CCB88", done = "AAB0C0" },
        },
        hexMap = { ["7A4A00"] = "E6C070", ["2F5D1F"] = "84CC80", ["8B1A1A"] = "EC8070", ["2A6F2A"] = "7CCB88",
                   ["5A3A10"] = "C8D0E8", ["1F5D7A"] = "80BCF0", ["96600A"] = "E6B050" },
        wood = {
            normal = { 0.15, 0.20, 0.36 }, hover = { 0.21, 0.28, 0.48 }, down = { 0.10, 0.14, 0.26 },
            selected = { 0.28, 0.37, 0.60 }, disabled = { 0.14, 0.16, 0.22 }, border = { 0.02, 0.03, 0.07 },
            light = { 0.38, 0.47, 0.70 }, dark = { 0.07, 0.10, 0.18 }, accent = { 0.90, 0.80, 0.45 },
            text = { 0.92, 0.94, 1.00 }, textOff = { 0.48, 0.52, 0.62 },
        },
    },
    -- Hell & klar: fast weißes Papier, schiefergraue Knöpfe, kräftige dunkle Schrift (am besten
    -- lesbar - test8b: deutlich anders als Pergament)
    clear = {
        colors = {
            parchment = { 0.97, 0.97, 0.96, 1 }, wood = { 0.20, 0.23, 0.27, 1 }, ink = { 0.06, 0.06, 0.08 },
            soft = { 0.30, 0.32, 0.36 }, head = { 0.12, 0.28, 0.50 }, line = { 0.20, 0.22, 0.26, 0.35 },
            hover = { 0.40, 0.60, 0.95, 0.20 }, field = { 1.00, 1.00, 1.00 }, good = { 0.04, 0.42, 0.10 },
            bad = { 0.70, 0.05, 0.05 }, card = { 0.90, 0.91, 0.92, 1 }, panel = { 1.00, 1.00, 1.00, 1 },
            tip = { 0.92, 0.94, 0.97, 1 }, off = { 0.55, 0.56, 0.60 }, grey = { 0.38, 0.40, 0.44 },
            shade = { 0.10, 0.12, 0.16, 0.12 },
        },
        wood = {
            normal = { 0.27, 0.30, 0.35 }, hover = { 0.35, 0.39, 0.45 }, down = { 0.19, 0.21, 0.25 },
            selected = { 0.40, 0.46, 0.55 }, disabled = { 0.30, 0.31, 0.33 }, border = { 0.08, 0.09, 0.11 },
            light = { 0.52, 0.56, 0.62 }, dark = { 0.14, 0.15, 0.18 }, accent = { 0.35, 0.62, 0.95 },
            text = { 0.98, 0.98, 1.00 }, textOff = { 0.60, 0.61, 0.64 },
        },
    },
    -- Horde: Rot und Schwarz
    horde = {
        colors = {
            parchment = { 0.91, 0.82, 0.71, 1 }, wood = { 0.28, 0.05, 0.04, 1 }, ink = { 0.20, 0.06, 0.04 },
            soft = { 0.45, 0.20, 0.15 }, head = { 0.55, 0.10, 0.05 }, line = { 0.40, 0.10, 0.06, 0.40 },
            hover = { 1.00, 0.55, 0.40, 0.25 }, card = { 0.86, 0.74, 0.62, 1 }, tip = { 0.89, 0.78, 0.66, 1 },
        },
        wood = {
            normal = { 0.45, 0.09, 0.07 }, hover = { 0.58, 0.14, 0.10 }, down = { 0.32, 0.06, 0.05 },
            selected = { 0.70, 0.20, 0.14 }, disabled = { 0.30, 0.22, 0.20 }, border = { 0.08, 0.02, 0.02 },
            light = { 0.75, 0.30, 0.22 }, dark = { 0.22, 0.04, 0.03 }, accent = { 0.95, 0.75, 0.30 },
            text = { 1.00, 0.92, 0.82 },
        },
    },
    -- Allianz: Blau und Gold
    alliance = {
        colors = {
            parchment = { 0.92, 0.89, 0.80, 1 }, wood = { 0.07, 0.13, 0.30, 1 }, ink = { 0.06, 0.10, 0.22 },
            soft = { 0.25, 0.30, 0.45 }, head = { 0.55, 0.40, 0.05 }, line = { 0.10, 0.15, 0.35, 0.35 },
            hover = { 0.98, 0.85, 0.40, 0.25 }, field = { 0.97, 0.96, 0.92 }, card = { 0.85, 0.84, 0.78, 1 },
            tip = { 0.88, 0.86, 0.78, 1 },
        },
        wood = {
            normal = { 0.12, 0.22, 0.45 }, hover = { 0.17, 0.30, 0.58 }, down = { 0.08, 0.15, 0.32 },
            selected = { 0.24, 0.38, 0.68 }, disabled = { 0.22, 0.25, 0.30 }, border = { 0.03, 0.05, 0.12 },
            light = { 0.40, 0.52, 0.80 }, dark = { 0.05, 0.10, 0.22 }, accent = { 0.98, 0.80, 0.30 },
            text = { 1.00, 0.95, 0.80 },
        },
    },
    -- Druidengrün: grünes Holz, helles Moos-Papier
    druid = {
        colors = {
            parchment = { 0.88, 0.90, 0.78, 1 }, wood = { 0.10, 0.20, 0.08, 1 }, ink = { 0.10, 0.16, 0.06 },
            soft = { 0.28, 0.36, 0.20 }, head = { 0.30, 0.40, 0.05 }, line = { 0.15, 0.28, 0.10, 0.40 },
            hover = { 0.85, 0.95, 0.50, 0.30 }, field = { 0.96, 0.97, 0.90 }, card = { 0.82, 0.85, 0.70, 1 },
            tip = { 0.85, 0.88, 0.74, 1 },
        },
        wood = {
            normal = { 0.18, 0.32, 0.13 }, hover = { 0.24, 0.42, 0.18 }, down = { 0.12, 0.22, 0.09 },
            selected = { 0.32, 0.52, 0.24 }, disabled = { 0.24, 0.28, 0.22 }, border = { 0.04, 0.08, 0.03 },
            light = { 0.45, 0.62, 0.35 }, dark = { 0.08, 0.15, 0.06 }, accent = { 0.85, 0.80, 0.35 },
            text = { 0.95, 0.97, 0.85 },
        },
    },
}

-- Werte in die bestehenden Tabellen schreiben (die Fenster halten Verweise darauf)
local function Fill(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            for i in pairs(dst[k]) do dst[k][i] = nil end
            Fill(dst[k], v)
        else
            dst[k] = v
        end
    end
end

-- Skin + Durchsichtigkeit (Prozent, 50-100) übernehmen. Gibt den Namen des Skins zurück.
function SM:ApplySkin(name, opacity)
    if not M.SKINS[name] then name = "parchment" end
    Fill(M.colors, M.base.colors)
    Fill(M.wood, M.base.wood)
    local skin = M.SKINS[name]
    if skin.colors then Fill(M.colors, skin.colors) end
    if skin.wood then Fill(M.wood, skin.wood) end
    local a = math.max(50, math.min(100, tonumber(opacity) or 100)) / 100
    for _, key in ipairs({ "parchment", "card", "panel", "tip" }) do
        local c = M.colors[key]
        if c then c[4] = a end
    end
    M.skin, M.opacity = name, a
    -- farbige Wörter: in allen Texten des Addons umfärben (nur Skins mit hexMap, z. B. Nacht)
    M.hexMap = skin.hexMap
    if M.hexMap and SM.L then
        for k, v in pairs(SM.L) do
            if type(v) == "string" and v:find("|c", 1, true) then SM.L[k] = SM.SkinText(v) end
        end
    end
    return name
end

-- "|cff" + Farbe für farbige Wörter auf dem Papier (folgt dem Skin)
function SM.Hex(code)
    local map = M.hexMap
    return "|cff" .. ((map and map[code:upper()]) or code)
end

-- Farbcodes in einem Text an den Skin anpassen
function SM.SkinText(text)
    local map = M.hexMap
    if not map or type(text) ~= "string" then return text end
    return (text:gsub("|c[fF][fF](%x%x%x%x%x%x)", function(hex)
        local to = map[hex:upper()]
        return "|cff" .. (to or hex)
    end))
end
