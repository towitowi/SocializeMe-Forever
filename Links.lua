local ADDON, SM = ...

-- Links für die Community-Tafel (Info-Tab). Hier kannst du Einträge ändern, ohne
-- den restlichen Code anzufassen. Platz ist für bis zu 4 Einträge.
--   id  = Schlüssel für die Beschriftung (LINK_<id> in Locales.lua)
--   url = die Adresse, die im Kopier-Dialog erscheint - oder eine Tabelle je Sprache
--         ({ de = ..., en = ... }; fehlt eine Sprache, gilt en)
-- Einladungslinks von Discord können ablaufen: dann hier einfach die url ersetzen.
-- Nur werbefreie Seiten ohne Gold-/Boost-Angebote aufnehmen (Blizzards Regeln für Addons).
SM.Links = {
    -- Der eigene Discord von SocializeMe Forever (Feedback, Fehler, Fragen) - Freitag-Patch
    { id = "smdiscord",    url = "https://discord.gg/qwnvFjvb82" },
    -- WoW Portal Room: Blizzards offizieller Community-Discord (Link aus Blizzards eigener
    -- Ankündigung: worldofwarcraft.blizzard.com/news/24263355)
    { id = "discord",      url = "https://discord.gg/hcFyh4AGkk" },
    -- Blizzards Forum für WoW Forever (EU). Für Deutsch die Vorstellung der deutschen
    -- Forever-Kategorie - von dort ein Klick auf "World of Warcraft: Forever".
    { id = "forever",      url = {
        en = "https://eu.forums.blizzard.com/en/wow/c/wow-forever/359",
        de = "https://eu.forums.blizzard.com/de/wow/t/334758/1",
    } },
    { id = "tavern",       url = "https://www.warcrafttavern.com/wow-classic/guides/professions/" },
}

-- Die Adresse eines Eintrags in der Sprache des Addons
function SM.LinkURL(link)
    local url = link and link.url
    if type(url) ~= "table" then return url end
    local lang = (SM.locale == "deDE") and "de" or "en"
    return url[lang] or url.en
end
