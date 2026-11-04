local ADDON, SM = ...

-- Zonennamen in den drei Addon-Sprachen. Gebraucht nur, wenn das Addon in einer anderen Sprache
-- läuft als das Spiel (z. B. englischer Client, Addon auf Deutsch) - sonst kommen die Namen
-- direkt aus dem Spiel. So steht nicht "Orte in The Barrens" neben deutschem Text.
--   uiMapID = { en, de, zh }
local NAMES = {
    [1411] = { "Durotar", "Durotar", "杜隆塔尔" },
    [1412] = { "Mulgore", "Mulgore", "莫高雷" },
    [1413] = { "The Barrens", "Das Brachland", "贫瘠之地" },
    [1416] = { "Alterac Mountains", "Alteracgebirge", "奥特兰克山脉" },
    [1417] = { "Arathi Highlands", "Arathihochland", "阿拉希高地" },
    [1418] = { "Badlands", "Ödland", "荒芜之地" },
    [1419] = { "Blasted Lands", "Verwüstete Lande", "诅咒之地" },
    [1420] = { "Tirisfal Glades", "Tirisfal", "提瑞斯法林地" },
    [1421] = { "Silverpine Forest", "Silberwald", "银松森林" },
    [1422] = { "Western Plaguelands", "Westliche Pestländer", "西瘟疫之地" },
    [1423] = { "Eastern Plaguelands", "Östliche Pestländer", "东瘟疫之地" },
    [1424] = { "Hillsbrad Foothills", "Vorgebirge des Hügellands", "希尔斯布莱德丘陵" },
    [1425] = { "The Hinterlands", "Hinterland", "辛特兰" },
    [1426] = { "Dun Morogh", "Dun Morogh", "丹莫罗" },
    [1427] = { "Searing Gorge", "Sengende Schlucht", "灼热峡谷" },
    [1428] = { "Burning Steppes", "Brennende Steppe", "燃烧平原" },
    [1429] = { "Elwynn Forest", "Wald von Elwynn", "艾尔文森林" },
    [1430] = { "Deadwind Pass", "Gebirgspass der Totenwinde", "逆风小径" },
    [1431] = { "Duskwood", "Dämmerwald", "暮色森林" },
    [1432] = { "Loch Modan", "Loch Modan", "洛克莫丹" },
    [1433] = { "Redridge Mountains", "Rotkammgebirge", "赤脊山" },
    [1434] = { "Stranglethorn Vale", "Schlingendorntal", "荆棘谷" },
    [1435] = { "Swamp of Sorrows", "Sümpfe des Elends", "悲伤沼泽" },
    [1436] = { "Westfall", "Westfall", "西部荒野" },
    [1437] = { "Wetlands", "Sumpfland", "湿地" },
    [1438] = { "Teldrassil", "Teldrassil", "泰达希尔" },
    [1439] = { "Darkshore", "Dunkelküste", "黑海岸" },
    [1440] = { "Ashenvale", "Eschental", "灰谷" },
    [1441] = { "Thousand Needles", "Tausend Nadeln", "千针石林" },
    [1442] = { "Stonetalon Mountains", "Steinkrallengebirge", "石爪山脉" },
    [1443] = { "Desolace", "Desolace", "凄凉之地" },
    [1444] = { "Feralas", "Feralas", "菲拉斯" },
    [1445] = { "Dustwallow Marsh", "Düstermarschen", "尘泥沼泽" },
    [1446] = { "Tanaris", "Tanaris", "塔纳利斯" },
    [1447] = { "Azshara", "Azshara", "艾萨拉" },
    [1448] = { "Felwood", "Teufelswald", "费伍德森林" },
    [1449] = { "Un'Goro Crater", "Krater von Un'Goro", "安戈洛环形山" },
    [1450] = { "Moonglade", "Mondlichtung", "月光林地" },
    [1451] = { "Silithus", "Silithus", "希利苏斯" },
    [1452] = { "Winterspring", "Winterquell", "冬泉谷" },
    [1453] = { "Stormwind City", "Sturmwind", "暴风城" },
    [1454] = { "Orgrimmar", "Orgrimmar", "奥格瑞玛" },
    [1455] = { "Ironforge", "Eisenschmiede", "铁炉堡" },
    [1456] = { "Thunder Bluff", "Donnerfels", "雷霆崖" },
    [1457] = { "Darnassus", "Darnassus", "达纳苏斯" },
    [1458] = { "Undercity", "Unterstadt", "幽暗城" },
}
SM.ZoneNames = NAMES

local IDX = { enUS = 1, enGB = 1, deDE = 2, zhCN = 3 }

-- Name einer Karte in der Sprache des Addons
function SM:MapName(mapID)
    local addonLang = IDX[self.locale or ""] or 1
    local gameLang = IDX[GetLocale and GetLocale() or ""]
    local row = NAMES[tonumber(mapID) or 0]
    if row and addonLang ~= gameLang then return row[addonLang] end
    if C_Map and C_Map.GetMapInfo and mapID then
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name then return info.name end
    end
    return row and row[addonLang] or "?"
end

-- Umgekehrt: Karten-ID zu einem Zonennamen (z. B. die Überschrift im Questlog). Verglichen wird
-- mit dem Namen aus dem Spiel und mit den drei Namen der Tabelle, ohne Groß/klein.
function SM:MapByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local want = name:lower()
    for id, row in pairs(NAMES) do
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
        if info and info.name and info.name:lower() == want then return id end
        for _, n in ipairs(row) do
            if n:lower() == want then return id end
        end
    end
    return nil
end
