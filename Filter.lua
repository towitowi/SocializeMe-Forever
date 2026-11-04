local ADDON, SM = ...

-- Wörter-Filter für alles, was andere Spieler als Text von dir sehen (Beacon-Texte usw.),
-- beim Senden UND beim Empfangen. Blizzards eigener Schimpfwort-Filter gilt nur für den Chat,
-- nicht für Addon-Nachrichten - deshalb prüfen wir hier selbst.
--
-- Drei Gruppen:
--   "trade" - Handel, Boosting, Instanzen (passt nicht zu einem Addon für die offene Welt)
--   "rude"  - Beleidigungen, Hass und Drohungen (Deutsch, Englisch, Chinesisch)
--   "adult" - alles Sexuelle (ERP, Cybersex, NSFW ...). Hier spielen auch Jüngere mit.
-- Dazu für die Themen der Plauderrunde: "heavy" - schwere Themen wie Krieg oder Politik
-- (Filter:CheckTopic). Plauderrunden sind für Schönes.
--
-- Lateinische Schrift: Handelswörter nur als GANZE Wörter ("erp" soll nicht "expert" treffen).
-- Beleidigungen: manche Stämme nur am Wortanfang ("arsch" soll nicht "Marsch" treffen), sehr
-- eindeutige auch mitten im Wort ("motherfucker"). Chinesisch kennt keine Wortgrenzen, dort
-- werden Teilstrings geprüft.
local Filter = {}
SM.Filter = Filter

local TRADE = {}
for _, w in ipairs({
    "gold", "wts", "wtb", "boosting", "boost", "casino",
    "ragefire", "m+", "mythic+", "dungeon", "raid", "rubel",
}) do
    TRADE[w] = true
end
-- 代练 (Boosting), 金币 (Gold), 赌场 (Casino), 地下城/副本/团本 (Dungeon/Instanz/Raid),
-- 卖金/收金 (Gold kaufen/verkaufen)
local TRADE_CJK = { "代练", "金币", "赌场", "地下城", "副本", "团本", "卖金", "收金" }

-- Quest-Namen kommen vom Spiel selbst ("Escape from the Dungeon", "Raid on ...").
-- Für sie gilt nur die Handels-/Boost-Liste, nicht die Instanz-Wörter.
local INSTANCE_WORDS = { ragefire = true, ["m+"] = true, ["mythic+"] = true, dungeon = true, raid = true }
local INSTANCE_CJK = { ["地下城"] = true, ["副本"] = true, ["团本"] = true }

-- Überall im Text (so eindeutig, dass sie in keinem harmlosen Wort vorkommen)
local RUDE_ANYWHERE = {
    -- Deutsch
    "arschloch", "arschgeige", "hurensohn", "hurenkind", "wichser", "fotze", "missgeburt",
    "schwuchtel", "judensau", "drecksau", "drecksack", "hitler", "siegheil", "heilhitler",
    "bringdichum", "tötedich", "hängdichauf", "verreck", "krepier",
    -- Englisch
    "fuck", "cunt", "nigger", "nigga", "faggot", "motherf", "killyourself", "kilyourself",
    "iwillkillyou", "illkillyou", "iwillfindyou",
}
-- Nur am Wortanfang
local RUDE_START = {
    -- Deutsch
    "arsch", "hure", "spast", "spasti", "nutte", "schlampe", "neger", "kanake", "kanacke",
    "zigeuner", "nazi", "vergewaltig",
    -- Englisch
    "fag", "retard", "bitch", "whore", "slut", "rape", "rapist", "tranny", "dickhead",
}
-- Nur als ganzes Wort
local RUDE_WORD = { kys = true, stfu = true, idiot = true, idioten = true, wixer = true }
-- Chinesisch: 傻逼/煞笔 (Schimpfwort), 操你/草泥马/你妈/他妈的 (Flüche), 婊子/贱人 (Beleidigung),
-- 脑残/智障 (Beleidigung), 杀了你/弄死你 (Drohung). Bewusst NICHT "去死" (steckt in 去死亡矿井 =
-- "zu den Todesminen") und nicht "妈的" allein (steckt in 姑妈的 = "der Tante").
local RUDE_CJK = { "傻逼", "煞笔", "操你", "草泥马", "你妈", "他妈的", "婊子", "贱人", "脑残", "智障",
                   "杀了你", "弄死你" }

-- Sexuelles: überall im Text (eindeutig), am Wortanfang, als ganzes Wort, Chinesisch.
-- "erp" nur als ganzes Wort ("superpower" enthält "erp"), "geil" bewusst nicht (heißt oft "toll").
local ADULT_ANYWHERE = { "cybersex", "sexting", "dirtytalk", "onlyfans", "pornhub", "rule34", "hentai",
                         "nsfw", "titten", "muschi", "brüste", "brueste", "nacktbild", "nacktfoto" }
local ADULT_START = { "porn", "sex", "nackt", "horny", "boob", "titt", "penis", "vagin", "fetisch",
                      "fetish", "bdsm", "milf", "lewd", "erotik", "erotic", "erotisch", "orgasm", "orgas" }
local ADULT_WORD = { erp = true, cs = true, nude = true, nudes = true, naked = true, tits = true,
                     dick = true, cock = true, pussy = true, fap = true, ficken = true, bumsen = true }
-- 色情 (Pornografie), 做爱/性爱 (Sex), 约炮 (Sex-Treffen), 裸聊/裸照 (Nackt-Chat/-Fotos),
-- 黄片 (Pornofilm), 啪啪 (Sex, umgangssprachlich)
local ADULT_CJK = { "色情", "做爱", "性爱", "约炮", "裸聊", "裸照", "黄片", "啪啪" }

-- Schwere Themen - nur für die Themen der Plauderrunde. Vorsicht mit Spielwörtern:
-- "Krieger"/"Kriegerin" ist eine Klasse, "Warsong" eine Schlachtfeld-Gegend, "Terrordale"
-- eine Gegend, "trumpet" eine Trompete - deshalb manche nur als ganzes Wort. Bewusst NICHT
-- "war" (auf Deutsch "Wie war dein Tag?") und nicht "Wahl" (steckt in "Auswahl").
local HEAVY_START = { "weltkrieg", "kriegs", "warfare", "politik", "politic", "wahlkampf", "election",
                      "religion", "terroris", "anschlag", "covid", "impfung", "impfen", "vaccin",
                      "ukrain", "gaza", "israel", "palästin", "palestin", "russland", "russia",
                      "holocaust", "suizid", "suicid", "selbstmord" }
local HEAVY_WORD = { krieg = true, kriege = true, wars = true, terror = true, corona = true, trump = true,
                     biden = true, putin = true, afd = true, hamas = true }
local HEAVY_CJK = { "战争", "政治", "选举", "宗教", "恐怖", "疫情", "自杀" }

-- Text vereinheitlichen: klein, Zahlen-Tricks zurück zu Buchstaben (h0re, f*ck ...)
local LEET = { ["0"] = "o", ["1"] = "i", ["3"] = "e", ["4"] = "a", ["5"] = "s", ["7"] = "t",
               ["@"] = "a", ["$"] = "s", ["!"] = "i" }
local function Normalize(text)
    local s = text:lower():gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü")
    return (s:gsub("[0134578@%$!]", LEET))
end

-- Buchstaben inkl. UTF-8 (Umlaute), damit "Marsch" ein Wort bleibt
local LETTER = "[%a\128-\255]"

local function StartsWord(s, a)
    return a == 1 or not s:sub(a - 1, a - 1):find(LETTER)
end

-- Erstes Wort aus list, das irgendwo am Wortanfang steht
local function FindStart(s, list)
    for _, w in ipairs(list) do
        local from = 1
        while true do
            local a = s:find(w, from, true)
            if not a then break end
            if StartsWord(s, a) then return w end
            from = a + 1
        end
    end
end

local function CheckRude(text)
    local s = Normalize(text)
    -- ohne Leer- und Satzzeichen: "f u c k", "kill yourself", "bring dich um"
    local squeezed = s:gsub("[%s%p]", "")
    for _, w in ipairs(RUDE_ANYWHERE) do
        if squeezed:find(w, 1, true) then return w end
    end
    local hit = FindStart(s, RUDE_START)
    if hit then return hit end
    for token in s:gmatch("%a+") do
        if RUDE_WORD[token] then return token end
    end
    for _, w in ipairs(RUDE_CJK) do
        if s:find(w, 1, true) then return w end
    end
end

local function CheckAdult(text)
    local s = Normalize(text)
    local squeezed = s:gsub("[%s%p]", "")
    for _, w in ipairs(ADULT_ANYWHERE) do
        if squeezed:find(w, 1, true) then return w end
    end
    local hit = FindStart(s, ADULT_START)
    if hit then return hit end
    for token in s:gmatch("%a+") do
        if ADULT_WORD[token] then return token end
    end
    if text:find("18%s*%+") then return "18+" end
    for _, w in ipairs(ADULT_CJK) do
        if s:find(w, 1, true) then return w end
    end
end

local function CheckTrade(text, lenient)
    local lower = text:lower()
    local pos = 1
    while true do
        local a, b = lower:find("[%w%+]+", pos)
        if not a then break end
        local token = lower:sub(a, b)
        if TRADE[token] and not (lenient and INSTANCE_WORDS[token]) then return token end
        pos = b + 1
    end
    for _, s in ipairs(TRADE_CJK) do
        if not (lenient and INSTANCE_CJK[s]) and lower:find(s, 1, true) then return s end
    end
end

-- Gibt true, <gefundenes Wort>, <"trade"|"rude"|"adult"> zurück, wenn der Text nicht erlaubt ist.
-- lenient = true: Instanz-Wörter sind erlaubt (für Quest-Namen aus dem Spiel). Quest-Namen
-- werden auch nicht auf Sexuelles geprüft (das Spiel hat z. B. "Naked" in Questnamen nicht,
-- aber eine Quest soll nie am Filter scheitern).
function Filter:Check(text, lenient)
    if type(text) ~= "string" or text == "" then return false end
    local rude = CheckRude(text)
    if rude then return true, rude, "rude" end
    if not lenient then
        local adult = CheckAdult(text)
        if adult then return true, adult, "adult" end
    end
    local trade = CheckTrade(text, lenient)
    if trade then return true, trade, "trade" end
    return false
end

-- Für Themen der Plauderrunde: alles von Check plus schwere Themen ("heavy")
function Filter:CheckTopic(text)
    local bad, word, kind = self:Check(text)
    if bad then return bad, word, kind end
    if type(text) ~= "string" or text == "" then return false end
    local s = Normalize(text)
    local heavy = FindStart(s, HEAVY_START)
    if not heavy then
        for token in s:gmatch("%a+") do
            if HEAVY_WORD[token] then heavy = token; break end
        end
    end
    if not heavy then
        for _, w in ipairs(HEAVY_CJK) do
            if s:find(w, 1, true) then heavy = w; break end
        end
    end
    if heavy then return true, heavy, "heavy" end
    return false
end

-- Fertige Meldung für den Spieler (das Wort selbst wird bei Beleidigungen und Sexuellem
-- nicht wiederholt)
function Filter:Message(word, kind)
    if kind == "rude" then return SM.L.RUDE_MSG end
    if kind == "adult" then return SM.L.ADULT_MSG end
    if kind == "heavy" then return SM.L.TOPIC_HEAVY_MSG end
    return SM.L.BANNED_MSG:format(word)
end
