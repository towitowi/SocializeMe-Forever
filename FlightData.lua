local ADDON, SM = ...

-- Ein Flugmeister je Zone und Fraktion: der Treffpunkt für einen Quest-Beacon, den jemand
-- außerhalb der Quest-Zone setzt (z. B. in Orgrimmar für eine Quest im Arathihochland).
-- Dort landet jeder, der in die Zone fliegt - so findet man sich am leichtesten.
-- Grundlage: öffentlich bekannte Standorte der Flugmeister (Koordinaten auf eine Nachkommastelle).
-- Gibt es in einer Zone mehrere, steht hier der im Hauptort; neutrale Flugmeister (Ratschet,
-- Marschalls Zuflucht) gelten für beide Seiten. cx/cy = Classic Era, wo Forever die Karte neu zeichnet.
--   uiMapID = { A = { x, y }, H = { x, y } }
SM.FlightData = {
    [1413] = { A = { 63.1, 37.2 }, H = { 51.5, 30.3 } },  -- Ratschet / Das Wegekreuz
    [1417] = { A = { 45.7, 46.1 }, H = { 73.0, 32.7 } },  -- Zuflucht / Hammerfall
    [1418] = { H = { 4.0, 44.8 } },                       -- Kargath
    [1419] = { A = { 65.5, 24.3 } },                      -- Burg Nethergarde
    [1421] = { H = { 45.6, 42.6 } },                      -- Das Grabmal
    [1422] = { A = { 42.9, 85.1 } },                      -- Kaltwindlager
    [1423] = { A = { 71.8, 49.6, cx = 81.6, cy = 59.3 }, H = { 70.5, 47.5, cx = 80.2, cy = 57.0 } }, -- Kapelle des Hoffnungsvollen Lichts
    [1424] = { A = { 49.3, 52.3 }, H = { 60.1, 18.6 } },  -- Süderstade / Tarrens Mühle
    [1425] = { A = { 11.1, 46.1 }, H = { 81.7, 81.8 } },  -- Nistgipfel / Revantusk (Hinterland)
    [1427] = { A = { 37.9, 30.9 }, H = { 34.8, 30.9 } },  -- Thoriumspitze
    [1428] = { A = { 84.3, 68.3 }, H = { 65.7, 24.2 } },  -- Morgans Wacht / Flammenkamm
    [1431] = { A = { 77.5, 44.3 } },                      -- Dunkelhain
    [1432] = { A = { 33.9, 51.0 } },                      -- Thelsamar
    [1433] = { A = { 25.5, 59.4, cx = 30.6, cy = 59.4 } }, -- Seenhain
    [1434] = { A = { 27.5, 77.8 }, H = { 32.5, 29.4 } },  -- Beutebucht / Grom'gol
    [1435] = { H = { 46.1, 54.8 } },                      -- Steinard
    [1436] = { A = { 56.5, 52.6 } },                      -- Späherkuppe
    [1437] = { A = { 9.5, 59.7 } },                       -- Hafen von Menethil
    [1438] = { A = { 58.4, 94.0 } },                      -- Rut'theran
    [1439] = { A = { 36.3, 45.6 } },                      -- Auberdine
    [1440] = { A = { 34.4, 48.0 }, H = { 73.2, 61.6 } },  -- Astranaar / Splitterholzposten
    [1441] = { H = { 45.1, 49.1 } },                      -- Freiwindposten
    [1442] = { A = { 36.4, 7.2 }, H = { 45.1, 59.8 } },   -- Steinkrallengipfel / Sonnenfels
    [1443] = { A = { 64.7, 10.5 }, H = { 21.6, 74.1 } },  -- Nijel's Point / Shadowprey
    [1444] = { A = { 30.2, 43.2 }, H = { 75.5, 44.4 } },  -- Mondfederfeste / Camp Mojache
    [1445] = { A = { 67.5, 51.3 }, H = { 35.6, 31.9 } },  -- Theramore / Brackenwall
    [1446] = { A = { 51.0, 29.3 }, H = { 51.6, 25.4 } },  -- Gadgetzan
    [1447] = { A = { 11.9, 77.6 }, H = { 22.0, 49.6 } },  -- Talrendisspitze / Valormok
    [1448] = { A = { 62.5, 24.2 }, H = { 34.4, 54.0 } },  -- Talonast / Blutgiftposten
    [1449] = { A = { 45.2, 5.8 }, H = { 45.2, 5.8 } },    -- Marschalls Zuflucht
    [1450] = { A = { 48.1, 67.3 }, H = { 32.1, 66.6 } },  -- Mondlichtung
    [1451] = { A = { 50.6, 34.5 }, H = { 48.7, 36.7 } },  -- Burg Cenarius
    [1452] = { A = { 62.3, 36.6 }, H = { 60.5, 36.3 } },  -- Ewige Warte
    [1453] = { A = { 71.3, 72.2, cx = 66.3, cy = 62.1 } }, -- Sturmwind
    [1454] = { H = { 45.1, 63.9 } },                      -- Orgrimmar
    [1455] = { A = { 55.5, 47.7 } },                      -- Eisenschmiede
    [1456] = { H = { 47.0, 49.8 } },                      -- Donnerfels
    [1458] = { H = { 63.2, 48.6 } },                      -- Unterstadt
}

-- Treffpunkt in einer Zone für die eigene Fraktion: der Flugmeister, sonst das Gasthaus eines
-- Ortes aus Modules\WaitData.lua (Startgebiete haben keinen Flugmeister). Gibt x, y (0-1) und
-- "flight" oder "inn" zurück, oder nichts.
function SM:MeetPointIn(mapID)
    local fac = type(UnitFactionGroup) == "function" and UnitFactionGroup("player")
    fac = (fac == "Alliance" and "A") or (fac == "Horde" and "H") or nil
    if not (fac and mapID) then return nil end
    local row = SM.FlightData[mapID]
    local p = row and row[fac]
    if p then
        if not SM.FOREVER and p.cx then return p.cx / 100, p.cy / 100, "flight" end
        return p[1] / 100, p[2] / 100, "flight"
    end
    for _, town in ipairs(SM.WaitData or {}) do
        if town.m == mapID and (not town.f or town.f == fac) then
            for _, q in ipairs(town) do
                if q[1] == "inn" then
                    if not SM.FOREVER and q.cx then return q.cx / 100, q.cy / 100, "inn" end
                    return q[2] / 100, q[3] / 100, "inn"
                end
            end
        end
    end
    return nil
end
