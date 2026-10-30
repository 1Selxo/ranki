local Config = {
    -- [REQUIRED] name of the anki deck
    deckName = "Mining",

    -- [REQUIRED] note type of the notes that should be created
    modelName = "Lapis",

    -- [REQUIRED] The field name where the word which was looked up will be sent to
    word_field = "Expression",

    -- [REQUIRED] The field name where the dictionary definition will be sent to
    def_field = "Glossary",

    -- The field name where the sentence in which the word occurred will be sent to
    context_field = "Sentence",

    -- Tags to add to the created notes
    custom_tags = { "KOReader", "Mining" },

    -- Duplicate detection
    allow_dupes = false,
    dupe_scope = "deck",

    -- Amount of sentences before/after
    prev_sentence_count = 1,
    next_sentence_count = 1,

    -- Enabled extensions
    enabled_extensions = {
        "EXT_dict_word_lookup.lua"
    }
}
return Config
