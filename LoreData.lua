local ADDON, SM = ...

-- Lore-Häppchen je Zone (uiMapID der Classic-Karten) auf Deutsch und Englisch.
-- Chinesische Clients bekommen die englischen Texte.
-- Bewusst nur gut belegte Fakten; Ergänzungen einfach in beide Sprachen eintragen.
SM.LoreData = {
    de = {
        [1429] = { -- Wald von Elwynn
            "In der Abtei von Nordhain machen viele junge Menschen ihre ersten Schritte als Helden.",
            "Die Kobolde in den Minen von Elwynn sind berühmt für ihren Ruf: „Ihr nicht nehmen Kerze!“",
            "Im Gasthaus „Zur Höhle des Löwen“ in Goldhain kehren seit jeher Abenteurer ein.",
        },
        [1436] = { -- Westfall
            "Die Steinmetze, die Sturmwind wiederaufbauten, wurden nie bezahlt - unter Edwin van Cleef wurden sie zur Defias-Bruderschaft.",
            "Auf der Späherkuppe sammelt Gryan Starkmantel die Volksmiliz von Westfall.",
            "Die Erntegolems auf den Feldern wurden von den Defias übernommen und gegen die Bauern gerichtet.",
        },
        [1433] = { -- Rotkammgebirge
            "Seenhain liegt am Ufer des Immerstillen Sees.",
            "Orcs des Schwarzfelsclans und Gnolle bedrohen Seenhain immer wieder.",
            "Im Norden grenzt das Rotkammgebirge an die Brennende Steppe, die Heimat des Schwarzfelsclans.",
        },
        [1431] = { -- Dämmerwald
            "Der Dämmerwald soll einst ein heller Wald gewesen sein - seine Verdunkelung wird dem nahen Karazhan zugeschrieben.",
            "Dunkelhain wird von der Nachtwache beschützt.",
            "Auf dem Friedhof am Rabenhügel finden die Toten keine Ruhe.",
        },
        [1434] = { -- Schlingendorntal
            "Die Beutebucht gehört dem Dampfdruckkartell der Goblins.",
            "Im Schlingendorntal lag einst das Reich der Gurubashi-Trolle.",
            "Hemet Nesingwary lädt im Norden des Tals zur großen Jagd.",
            "In der Gurubashi-Arena wird alle drei Stunden um eine Schatztruhe gekämpft.",
        },
        [1426] = { -- Dun Morogh
            "Eisenschmiede wurde von den Zwergen tief in den Berg gehauen.",
            "Gnomeregan, die Stadt der Gnome, wurde von Troggs überrannt.",
            "In Kharanos braut die Familie Donnerbräu ihr berühmtes Bier.",
        },
        [1432] = { -- Loch Modan
            "Der große Damm staut das Wasser des Loch Modan.",
            "Thelsamar ist die wichtigste Siedlung am Loch Modan.",
            "Die Forscherliga gräbt in Loch Modan nach Spuren der Vergangenheit.",
        },
        [1437] = { -- Sumpfland
            "Der Hafen von Menethil trägt den Namen des Königshauses von Lordaeron.",
            "In der alten Zwergenfestung Grim Batol hielt der Drachenmalclan einst die Drachenkönigin Alexstrasza gefangen.",
            "Die Thandolbrücke verbindet Khaz Modan mit dem Arathihochland.",
        },
        [1417] = { -- Arathihochland
            "Arathor war das erste Reich der Menschen.",
            "Stromgarde gilt als Erbe des alten Arathor.",
            "Im Arathibecken ringen Allianz und Horde um Rohstoffe.",
        },
        [1424] = { -- Vorgebirge des Hügellands
            "Süderstade gehört der Allianz, Tarrens Mühle der Horde - ihre Gefechte sind legendär.",
            "In Burg Durnholde wuchs Thrall als Gefangener von Aedelas Schwarzmoor auf.",
            "Das Hügelland war einst eine ruhige Bauerngegend Lordaerons.",
        },
        [1416] = { -- Alteracgebirge
            "König Perenolde von Alterac verriet im Zweiten Krieg die Allianz und verbündete sich mit der Horde.",
            "Hinter den Bergen liegt Rabenholdt, der verborgene Sitz einer Schurkengilde.",
            "Dalaran liegt am Rand der Alteracberge unter einer violetten Schutzkuppel.",
        },
        [1421] = { -- Silberwald
            "In der Burg Schattenfang rief der Erzmagier Arugal die Worgen herbei.",
            "Das Grabmal ist der Stützpunkt der Verlassenen im Silberwald.",
            "Hinter dem Graumähnenwall hat sich das Königreich Gilneas abgeschottet.",
        },
        [1420] = { -- Tirisfal
            "Unterstadt liegt unter den Ruinen von Lordaeron, der einstigen Hauptstadt.",
            "Das Scharlachrote Kloster ist eine Hochburg des Scharlachroten Kreuzzugs.",
            "In Todesend erwachen viele Verlassene zu ihrem neuen Dasein.",
        },
        [1422] = { -- Westliche Pestländer
            "Von Andorhal aus verbreitete Kel'Thuzad die Seuche.",
            "Die Scholomance liegt unter Caer Darrow, einst der Sitz der Familie Barov.",
            "Herdweiler ist eine Bastion des Scharlachroten Kreuzzugs.",
        },
        [1423] = { -- Östliche Pestländer
            "Die Kapelle des Hoffnungsvollen Lichts gilt als heiliger Boden - hier harrt die Argentumdämmerung aus.",
            "Prinz Arthas ließ Stratholme säubern, bevor die Seuche die Bewohner verwandeln konnte.",
            "Über den Pestländern schwebt die Nekropole Naxxramas.",
        },
        [1425] = { -- Hinterland
            "Die Wildhammerzwerge vom Nistgipfel reiten auf Greifen.",
            "Jintha'Alor ist eine Festung der Trolle.",
            "In Seradane steht eines der Tore zum Smaragdgrünen Traum.",
        },
        [1427] = { -- Sengende Schlucht
            "Die Schlucht entstand, als Thaurissan im Krieg der Drei Hämmer Ragnaros beschwor.",
            "Die Dunkeleisenzwerge lassen hier Sklaven für sich schuften.",
            "Die Thoriumbruderschaft hat in der Schlucht ihren Stützpunkt.",
        },
        [1428] = { -- Brennende Steppe
            "Der Schwarzfels erhebt sich zwischen Brennender Steppe und Sengender Schlucht.",
            "Der Schwarzfelsclan beherrscht den oberen Teil des Berges.",
            "In Morgans Wacht halten die Truppen der Allianz die Stellung.",
        },
        [1419] = { -- Verwüstete Lande
            "Durch das Dunkle Portal kamen die Orcs nach Azeroth.",
            "Die Verwüsteten Lande waren einst ein Sumpf, das Schwarzmoor.",
            "Burg Nethergarde wacht über das Dunkle Portal.",
        },
        [1435] = { -- Sümpfe des Elends
            "Der Tempel von Atal'Hakkar versank, weil die Trolle dort den Blutgott Hakkar beschwören wollten.",
            "Grüne Drachen bewachen den versunkenen Tempel.",
            "Steinard ist ein Außenposten der Horde mitten im Sumpf.",
        },
        [1418] = { -- Ödland
            "Uldaman ist ein uraltes Gewölbe der Titanen.",
            "Der Horde-Stützpunkt Kargath ist nach Kargath Messerfaust benannt.",
        },
        [1430] = { -- Gebirgspass der Totenwinde
            "Karazhan war der Turm des Magiers Medivh.",
            "Medivh half den Orcs, das Dunkle Portal zu öffnen.",
        },
        [1411] = { -- Durotar
            "Thrall benannte Durotar nach seinem Vater Durotan.",
            "Orgrimmar trägt den Namen von Orgrim Schicksalshammer.",
            "Sen'jin-Dorf ist nach dem einstigen Anführer der Dunkelspeertrolle benannt.",
        },
        [1412] = { -- Mulgore
            "Cairne Bluthuf ließ Donnerfels auf hohen Tafelbergen errichten.",
            "Die Tauren verehren die Erdenmutter.",
            "Die Venture Kompanie gräbt in Mulgore nach Rohstoffen - sehr zum Ärger der Tauren.",
        },
        [1413] = { -- Brachland
            "Das Wegekreuz ist ein wichtiger Posten der Horde.",
            "Ratschet ist ein neutraler Hafen der Goblins.",
            "In den Höhlen des Wehklagens gefangen, träumt der Druide Naralex einen Albtraum.",
        },
        [1438] = { -- Teldrassil
            "Teldrassil ist ein gewaltiger Weltenbaum - gepflanzt ohne den Segen der Drachen.",
            "Darnassus liegt in den Ästen von Teldrassil.",
            "Im Schattenhain beginnen junge Nachtelfen ihren Weg.",
        },
        [1439] = { -- Dunkelküste
            "Auberdine ist der Hafen der Nachtelfen an der Dunkelküste.",
            "Die Furbolgs der Dunkelküste sind von einer Verderbnis befallen.",
        },
        [1440] = { -- Eschental
            "Im Eschental tötete Grom Höllschrei den Halbgott Cenarius.",
            "In der Dämonenfall-Schlucht liegen die Überreste von Mannoroth.",
            "Astranaar ist der wichtigste Posten der Nachtelfen im Eschental.",
        },
        [1442] = { -- Steinkrallengebirge
            "Die Venture Kompanie holzt das Steinkrallengebirge rücksichtslos ab.",
            "Auf dem Steinkrallengipfel wachen die Druiden der Nachtelfen.",
        },
        [1443] = { -- Desolace
            "In Maraudon soll das Grab von Zaetar liegen, einem Sohn des Cenarius.",
            "Die Zentaurenstämme von Desolace führen erbitterte Kriege gegeneinander.",
        },
        [1444] = { -- Feralas
            "Düsterbruch, einst die Stadt Eldre'Thalas, war ein Sitz der Hochgeborenen.",
            "An der Küste ragen die gewaltigen Zwillingskolosse empor.",
            "Die Nachtelfen halten eine Festung auf einer Insel vor der Küste.",
        },
        [1441] = { -- Tausend Nadeln
            "Die Tausend Nadeln sind gewaltige Felsnadeln in einer ausgetrockneten Senke.",
            "Auf den Schimmernden Ebenen veranstalten Goblins und Gnome Rennen.",
            "Der Freiwindposten der Tauren thront auf einem hohen Plateau.",
        },
        [1446] = { -- Tanaris
            "Gadgetzan ist das Herz des Dampfdruckkartells.",
            "In den Höhlen der Zeit wacht der Bronzene Drachenschwarm über den Lauf der Geschichte.",
            "Zul'Farrak ist die Stadt der Sandwüter-Trolle.",
        },
        [1445] = { -- Düstermarschen
            "Theramore wurde von Jaina Prachtmeer gegründet.",
            "In den Düstermarschen liegt Onyxias Hort.",
            "Der berühmte Angler Nat Pagle hat hier sein Lager.",
        },
        [1447] = { -- Azshara
            "Azshara ist nach der Königin der Hochgeborenen benannt, die einst die Brennende Legion rief.",
            "Die Ruinen von Eldarath erinnern an das alte Reich der Nachtelfen.",
        },
        [1448] = { -- Teufelswald
            "Der Teufelswald war einst Teil des Eschentals, bis die Brennende Legion ihn verderbte.",
            "Die Smaragdgrüne Zuflucht ist ein Rückzugsort der Druiden.",
            "Die Furbolgs der Holzschlundfeste blieben von der Verderbnis verschont.",
        },
        [1449] = { -- Krater von Un'Goro
            "Der Krater von Un'Goro gilt als Werkstatt der Titanen - voller Dinosaurier und Riesenpflanzen.",
            "Überall im Krater leuchten farbige Kraftkristalle.",
            "Marshals Zuflucht ist ein Lager von Forschern am Kraterrand.",
        },
        [1450] = { -- Mondlichtung
            "Die Mondlichtung ist ein heiliger Ort der Druiden.",
            "Nachthafen ist das Dorf der Druiden.",
            "Zum Mondfest kommen Reisende aus ganz Azeroth in die Mondlichtung.",
        },
        [1451] = { -- Silithus
            "Im Krieg der Treibsande versiegelten Nachtelfen und Bronzedrachen Ahn'Qiraj hinter dem Skarabäuswall.",
            "Die Festung Ahn'Qiraj liegt am Südende von Silithus.",
            "Die Burg Cenarius ist der Stützpunkt des Zirkels des Cenarius.",
        },
        [1452] = { -- Winterquell
            "Die Ewige Warte ist ein Handelsposten der Goblins im ewigen Schnee.",
            "In Winterquell zähmen die Nachtelfen ihre Frostsäbler.",
            "Südwestlich erhebt sich der Berg Hyjal.",
        },
        [1453] = { -- Sturmwind
            "Hochlord Bolvar Fordragon regiert Sturmwind für den jungen König Anduin.",
            "Das Verlies ist das Gefängnis von Sturmwind.",
            "Sturmwind wurde nach dem Ersten Krieg wiederaufgebaut.",
        },
        [1454] = { -- Orgrimmar
            "Thrall regiert die Horde aus Grommashs Feste.",
            "Unter der Stadt liegt der Flammenschlund.",
            "Orgrimmar ist nach Orgrim Schicksalshammer benannt.",
        },
        [1455] = { -- Eisenschmiede
            "Die Große Schmiede ist das glühende Herz von Eisenschmiede.",
            "König Magni Bronzebart herrscht über die Zwerge.",
            "Die Tiefenbahn verbindet Eisenschmiede mit Sturmwind.",
        },
        [1456] = { -- Donnerfels
            "Donnerfels liegt auf mehreren Tafelbergen, verbunden durch Hängebrücken.",
            "Cairne Bluthuf ist der Hochhäuptling der Tauren.",
        },
        [1457] = { -- Darnassus
            "Tyrande Wisperwind ist Hohepriesterin der Elune und Anführerin der Nachtelfen.",
            "Der Tempel des Mondes ist das Zentrum der Elune-Verehrung.",
        },
        [1458] = { -- Unterstadt
            "Sylvanas Windläufer führt die Verlassenen.",
            "Die Königliche Apothekervereinigung forscht in der Unterstadt an einer neuen Seuche.",
        },
    },

    en = {
        [1429] = {
            "Many young humans take their first steps as heroes at Northshire Abbey.",
            "The kobolds in Elwynn's mines are famous for one cry: \"You no take candle!\"",
            "Adventurers have always gathered at the Lion's Pride Inn in Goldshire.",
        },
        [1436] = {
            "The stonemasons who rebuilt Stormwind were never paid - under Edwin VanCleef they became the Defias Brotherhood.",
            "On Sentinel Hill, Gryan Stoutmantle gathers the People's Militia of Westfall.",
            "The harvest golems in the fields were taken over by the Defias and turned against the farmers.",
        },
        [1433] = {
            "Lakeshire lies on the shore of Lake Everstill.",
            "Blackrock orcs and gnolls keep threatening Lakeshire.",
            "To the north, Redridge borders the Burning Steppes, home of the Blackrock clan.",
        },
        [1431] = {
            "Duskwood is said to have once been a bright forest - its darkness is blamed on nearby Karazhan.",
            "Darkshire is protected by the Night Watch.",
            "At Raven Hill Cemetery the dead find no rest.",
        },
        [1434] = {
            "Booty Bay belongs to the goblins of the Steamwheedle Cartel.",
            "Stranglethorn was once the heart of the Gurubashi troll empire.",
            "In the north of the vale, Hemet Nesingwary invites hunters to the great hunt.",
            "Every three hours, fighters battle for a treasure chest in the Gurubashi Arena.",
        },
        [1426] = {
            "The dwarves carved Ironforge deep into the mountain.",
            "Gnomeregan, the city of the gnomes, was overrun by troggs.",
            "In Kharanos the Thunderbrew family brews its famous ale.",
        },
        [1432] = {
            "The great dam holds back the waters of Loch Modan.",
            "Thelsamar is the most important settlement on Loch Modan.",
            "The Explorers' League digs for traces of the past in Loch Modan.",
        },
        [1437] = {
            "Menethil Harbor bears the name of Lordaeron's royal house.",
            "In the old dwarven fortress of Grim Batol, the Dragonmaw clan once held the dragon queen Alexstrasza captive.",
            "Thandol Span links Khaz Modan with the Arathi Highlands.",
        },
        [1417] = {
            "Arathor was the first kingdom of humans.",
            "Stromgarde sees itself as the heir of ancient Arathor.",
            "In Arathi Basin, Alliance and Horde fight over resources.",
        },
        [1424] = {
            "Southshore belongs to the Alliance, Tarren Mill to the Horde - their skirmishes are legendary.",
            "Thrall grew up at Durnholde Keep as the prisoner of Aedelas Blackmoore.",
            "Hillsbrad was once a quiet farming region of Lordaeron.",
        },
        [1416] = {
            "In the Second War, King Perenolde of Alterac betrayed the Alliance and sided with the Horde.",
            "Hidden beyond the mountains lies Ravenholdt, the secret seat of a rogues' guild.",
            "Dalaran lies at the edge of the Alterac Mountains beneath a violet dome.",
        },
        [1421] = {
            "At Shadowfang Keep, Archmage Arugal summoned the worgen.",
            "The Sepulcher is the Forsaken stronghold in Silverpine Forest.",
            "Behind the Greymane Wall, the kingdom of Gilneas has sealed itself off.",
        },
        [1420] = {
            "The Undercity lies beneath the ruins of Lordaeron, the former capital.",
            "The Scarlet Monastery is a stronghold of the Scarlet Crusade.",
            "Many Forsaken awaken to their new existence in Deathknell.",
        },
        [1422] = {
            "From Andorhal, Kel'Thuzad spread the plague.",
            "Scholomance lies beneath Caer Darrow, once the seat of the Barov family.",
            "Hearthglen is a bastion of the Scarlet Crusade.",
        },
        [1423] = {
            "Light's Hope Chapel is held to be sacred ground - the Argent Dawn holds out there.",
            "Prince Arthas purged Stratholme before the plague could turn its people.",
            "The necropolis Naxxramas floats above the Plaguelands.",
        },
        [1425] = {
            "The Wildhammer dwarves of Aerie Peak ride gryphons.",
            "Jintha'Alor is a troll fortress.",
            "At Seradane stands one of the gates to the Emerald Dream.",
        },
        [1427] = {
            "The gorge was born when Thaurissan summoned Ragnaros in the War of the Three Hammers.",
            "The Dark Iron dwarves keep slaves toiling here.",
            "The Thorium Brotherhood has its base in the gorge.",
        },
        [1428] = {
            "Blackrock Mountain rises between the Burning Steppes and Searing Gorge.",
            "The Blackrock clan rules the upper part of the mountain.",
            "At Morgan's Vigil, the Alliance troops hold the line.",
        },
        [1419] = {
            "The orcs came to Azeroth through the Dark Portal.",
            "The Blasted Lands were once a swamp, the Black Morass.",
            "Nethergarde Keep watches over the Dark Portal.",
        },
        [1435] = {
            "The Temple of Atal'Hakkar sank because the trolls wanted to summon the blood god Hakkar there.",
            "Green dragons guard the sunken temple.",
            "Stonard is a Horde outpost in the middle of the swamp.",
        },
        [1418] = {
            "Uldaman is an ancient vault of the titans.",
            "The Horde outpost of Kargath is named after Kargath Bladefist.",
        },
        [1430] = {
            "Karazhan was the tower of the mage Medivh.",
            "Medivh helped the orcs open the Dark Portal.",
        },
        [1411] = {
            "Thrall named Durotar after his father Durotan.",
            "Orgrimmar bears the name of Orgrim Doomhammer.",
            "Sen'jin Village is named after the former leader of the Darkspear trolls.",
        },
        [1412] = {
            "Cairne Bloodhoof had Thunder Bluff built on high mesas.",
            "The tauren worship the Earth Mother.",
            "The Venture Co. digs for resources in Mulgore - much to the tauren's anger.",
        },
        [1413] = {
            "The Crossroads is an important Horde outpost.",
            "Ratchet is a neutral goblin port.",
            "Trapped in the Wailing Caverns, the druid Naralex dreams a nightmare.",
        },
        [1438] = {
            "Teldrassil is a mighty World Tree - planted without the blessing of the dragons.",
            "Darnassus lies in the branches of Teldrassil.",
            "Young night elves begin their journey in Shadowglen.",
        },
        [1439] = {
            "Auberdine is the night elf harbor on Darkshore.",
            "The furbolgs of Darkshore have fallen to corruption.",
        },
        [1440] = {
            "In Ashenvale, Grom Hellscream slew the demigod Cenarius.",
            "The remains of Mannoroth lie in Demon Fall Canyon.",
            "Astranaar is the most important night elf outpost in Ashenvale.",
        },
        [1442] = {
            "The Venture Co. ruthlessly cuts down the forests of Stonetalon.",
            "Night elf druids keep watch on Stonetalon Peak.",
        },
        [1443] = {
            "Maraudon is said to hold the tomb of Zaetar, a son of Cenarius.",
            "The centaur tribes of Desolace wage bitter wars against each other.",
        },
        [1444] = {
            "Dire Maul, once the city of Eldre'Thalas, was a seat of the Highborne.",
            "On the coast, the mighty Twin Colossals tower over the land.",
            "The night elves hold a stronghold on an island off the coast.",
        },
        [1441] = {
            "The Thousand Needles are huge rock spires in a dried-out basin.",
            "On the Shimmering Flats, goblins and gnomes hold races.",
            "The tauren of Freewind Post live atop a high plateau.",
        },
        [1446] = {
            "Gadgetzan is the heart of the Steamwheedle Cartel.",
            "In the Caverns of Time, the bronze dragonflight watches over the course of history.",
            "Zul'Farrak is the city of the Sandfury trolls.",
        },
        [1445] = {
            "Theramore was founded by Jaina Proudmoore.",
            "Onyxia's Lair lies in Dustwallow Marsh.",
            "The famous angler Nat Pagle has his camp here.",
        },
        [1447] = {
            "Azshara is named after the queen of the Highborne who once called the Burning Legion.",
            "The Ruins of Eldarath recall the ancient night elf empire.",
        },
        [1448] = {
            "Felwood was once part of Ashenvale until the Burning Legion corrupted it.",
            "The Emerald Sanctuary is a refuge of the druids.",
            "The furbolgs of Timbermaw Hold were spared from the corruption.",
        },
        [1449] = {
            "Un'Goro Crater is said to be a workshop of the titans - full of dinosaurs and giant plants.",
            "Colorful power crystals glow all over the crater.",
            "Marshal's Refuge is a camp of explorers at the crater's edge.",
        },
        [1450] = {
            "Moonglade is a sacred place of the druids.",
            "Nighthaven is the village of the druids.",
            "For the Lunar Festival, travelers from all over Azeroth come to Moonglade.",
        },
        [1451] = {
            "In the War of the Shifting Sands, night elves and bronze dragons sealed Ahn'Qiraj behind the Scarab Wall.",
            "The fortress of Ahn'Qiraj lies at the southern end of Silithus.",
            "Cenarion Hold is the base of the Cenarion Circle.",
        },
        [1452] = {
            "Everlook is a goblin trading post in the eternal snow.",
            "In Winterspring, the night elves tame their frostsabers.",
            "Mount Hyjal rises to the southwest.",
        },
        [1453] = {
            "Highlord Bolvar Fordragon rules Stormwind for the young King Anduin.",
            "The Stockade is Stormwind's prison.",
            "Stormwind was rebuilt after the First War.",
        },
        [1454] = {
            "Thrall leads the Horde from Grommash Hold.",
            "Ragefire Chasm lies beneath the city.",
            "Orgrimmar is named after Orgrim Doomhammer.",
        },
        [1455] = {
            "The Great Forge is the glowing heart of Ironforge.",
            "King Magni Bronzebeard rules the dwarves.",
            "The Deeprun Tram connects Ironforge with Stormwind.",
        },
        [1456] = {
            "Thunder Bluff sits on several mesas linked by rope bridges.",
            "Cairne Bloodhoof is the high chieftain of the tauren.",
        },
        [1457] = {
            "Tyrande Whisperwind is high priestess of Elune and leader of the night elves.",
            "The Temple of the Moon is the center of Elune's worship.",
        },
        [1458] = {
            "Sylvanas Windrunner leads the Forsaken.",
            "The Royal Apothecary Society is working on a new plague in the Undercity.",
        },
    },

    -- Häppchen rund ums Angeln (überall gültig)
    fish = {
        de = {
            "Nat Pagle, der berühmteste Angler Azeroths, hat sein Lager in den Düstermarschen.",
            "Beim großen Angelwettbewerb im Schlingendorntal wird jeden Sonntag um seltene Fische gewetteifert.",
            "Manche Fische beißen nur nachts - ein Grund mehr, am Lagerfeuer sitzen zu bleiben.",
            "Wo ein Fischschwarm an der Oberfläche brodelt, beißt es besonders gut.",
        },
        en = {
            "Nat Pagle, Azeroth's most famous angler, has his camp in Dustwallow Marsh.",
            "At the great fishing contest in Stranglethorn, anglers compete for rare fish every Sunday.",
            "Some fish only bite at night - one more reason to stay by the campfire.",
            "Where a school of fish bubbles at the surface, the fish bite especially well.",
        },
    },
}
