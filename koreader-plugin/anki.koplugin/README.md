# Anki Plugin for KOReader (Offline RAnki Edition)

Enhanced KOReader plugin for Anki note and card generation directly from book dictionary lookups.

This version features **Ranki Local Offline Mode**, allowing you to sentence-mine on your Kindle completely offline without needing a PC running AnkiConnect or active Wi-Fi.

---

## Modes of Operation

1. **Local RAnki Mode (Default)**:
   - Writes directly to `/mnt/us/anki_data/collection.anki2` using KOReader's internal SQLite driver (`lua-ljsqlite3`).
   - Cards are created with `usn = -1` so they automatically synchronize to AnkiWeb next time you sync in Ranki on the Kindle or on your PC.
   - Uses parameterized prepared statements, safe against quotes, semicolons, HTML tags, and Japanese definitions.
   - Bypasses all Wi-Fi and network connectivity checks.

2. **AnkiConnect Mode (Online / PC)**:
   - Connects over HTTP to AnkiConnect running on a computer (set `url` in Anki Settings to `http://<your-pc-ip>:8765`).

---

## Installation

1. Copy the `anki.koplugin` folder to your Kindle:
   ```text
   /mnt/us/koreader/plugins/anki.koplugin/
   ```
2. Restart KOReader.

---

## Configuration

Profiles are stored in `profiles/`:
- `profiles/default.lua`
- `profiles/Mining.lua`
- `profiles/Kaishi.lua`

Example configuration:
```lua
local Config = {
    -- Target Anki Deck
    deckName = "Mining",

    -- Note type / Model in your collection
    modelName = "Lapis",

    -- Field name where the looked-up word is placed
    word_field = "Expression",

    -- Field name where the dictionary definition is placed
    def_field = "Glossary",

    -- Field name where the sentence context is placed
    context_field = "Sentence",

    -- Custom tags
    custom_tags = { "KOReader", "Mining" },

    -- Duplicate detection
    allow_dupes = false,
    dupe_scope = "deck",

    -- Sentence context window
    prev_sentence_count = 1,
    next_sentence_count = 1,

    enabled_extensions = {
        "EXT_dict_word_lookup.lua"
    }
}
return Config
```

---

## Usage

1. Open any book in KOReader.
2. Select any word or sentence to trigger the dictionary lookup.
3. Tap **"Add to Anki"** at the bottom of the popup window.
4. A notification `Added note to RAnki (Mining)` confirms the card has been saved directly to your device collection.
5. When ready, open the **Ranki** app and tap **Sync** to push your cards to AnkiWeb.

---

## Credits
Based on [Ajatt-Tools/anki.koplugin](https://github.com/Ajatt-Tools/anki.koplugin), modified by [1Selxo](https://github.com/1Selxo/ranki) to support direct local SQLite mining for Ranki.
