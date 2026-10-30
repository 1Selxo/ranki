# Ranki - Real Anki on Kindle ![ranki downloads](https://img.shields.io/github/downloads/crazy-electron/ranki/total)

“Real Anki for e-ink. Not actually rank.”

Minimal flashcard reviewer for Kindle e-reader devices, powered by the real Anki backend. Includes a companion **KOReader offline card-mining plugin** (`koreader-plugin/anki.koplugin`) for sentence mining directly on the device without a PC or Wi-Fi.

> **This is beta software.**
> Always backup your Anki collection before trying this app.
> I am **not responsible** for any data loss.

Built for `armel` and `armhf` (tested on Kindle Touch 4th Gen 5.3.7.3, 5.14.3, 5.17.1, and 5.18.5).

---

### Kindle Touch (4th Generation / Firmware 5.3.7.3) Support
This fork adds complete out-of-the-box compatibility for **Kindle Touch 4th Gen (K5)** running legacy firmware **5.3.7.3** (Linux kernel 2.6.31, glibc 2.12.1):
- **`libk5compat.so`**: Standalone ARMv7 EABI compatibility shim supplying missing `clock_gettime`, `getauxval`, and thread-local atexit syscalls.
- **GLIBC 2.12 Compatibility**: ELF version records in `ranki-armel` are patched so the Kindle Touch 5.3.7.3 dynamic linker loads it without `GLIBC_2.15 not found` errors.
- **`liblipc.so.1` & `libcurl.so.4` shims**: Fallback libraries to prevent crashes and ensure network/LIPC compatibility.
- **Power Management**: Auto-prevents Kindle Touch screensaver sleep while reviewing via `com.lab126.powerd`.
- **Media Sync Control**: Includes a KUAL toggle (`toggle_media_sync.sh`) and binary patch to disable media downloads, saving storage and RAM on 256MB devices.

<p align="center">
  <img width="300" alt="decks" src="https://github.com/user-attachments/assets/270407e5-4290-4820-9595-b2d072ca9c1e" />
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img width="300" alt="review" src="https://github.com/user-attachments/assets/87803fb1-eb44-40f3-8586-e4db38d3a072" />
</p>

---

## Table of Contents
1. [Features](#features)
2. [How to Set Up Ranki on Kindle](#how-to-set-up-ranki-on-kindle)
3. [How to Get Your Collection onto Ranki](#how-to-get-your-collection-onto-ranki)
4. [How to Log In Using `config.ini`](#how-to-log-in-using-configini)
5. [Setting Up the KOReader Offline Mining Plugin](#setting-up-the-koreader-offline-mining-plugin)
6. [Media Sync Toggle (Memory & Storage Optimization)](#media-sync-toggle-memory--storage-optimization)
7. [Technical Details](#technical-details)
8. [Troubleshooting](#troubleshooting)

---

## Features

- **Full Anki Backend**: Uses the official Rust-based Anki backend (pinned to v25.09.02) via protobuf for authentic scheduling and sync.
- **Offline Reviewing**: Review cards and bury cards directly on e-ink.
- **AnkiWeb Sync**: Sync decks, card statuses, and reviews with AnkiWeb or a custom sync server.
- **KOReader Direct Card Mining**: Mine words and context sentences directly into your local database while reading in KOReader without a PC or active Wi-Fi.
- **MathJax Support**: Full MathJax pack available in the settings menu.

---

## How to Set Up Ranki on Kindle

### Prerequisites
- A jailbroken Kindle with **KUAL** (Kindle Unified Application Launcher) installed.

### Installation
1. Download the latest `ranki.zip` from the [Releases](https://github.com/1Selxo/ranki/releases) page.
2. Connect your Kindle to your computer via USB.
3. Extract the contents of `ranki.zip` into the `/mnt/us/extensions/` folder on your Kindle:
   ```text
   Kindle Root (e.g. E:\ or /mnt/us/)
   └── extensions/
       └── ranki/
           ├── config.ini
           ├── config.xml
           ├── menu.json
           ├── ranki-armel
           ├── ranki.sh
           ├── toggle_media_sync.sh
           └── ...
   ```
4. *(Optional)* Copy `shortcut_ranki.sh` to `/mnt/us/documents/` if you want a shortcut to launch Ranki directly from your Kindle library home screen.
5. Safely eject your Kindle and launch **KUAL** -> **Ranki** -> **Open Ranki**.

---

## How to Get Your Collection onto Ranki

There are two ways to get your Anki cards onto the Kindle:

### Method 1: Cloud Sync via AnkiWeb (Recommended)
1. Configure your AnkiWeb credentials (either via the [Ranki Settings UI](#how-to-set-up-ranki-on-kindle) or by pre-filling [`config.ini`](#how-to-log-in-using-configini)).
2. Connect your Kindle to Wi-Fi.
3. Open Ranki and tap **Sync**.
4. Ranki will download your collection and schema directly into `/mnt/us/anki_data/collection.anki2`.

### Method 2: Direct USB Copy from PC (100% Offline)
If you do not want to use Wi-Fi or have a large collection:
1. Connect your Kindle to your PC via USB.
2. Create the directory `anki_data` on the Kindle root:
   - Windows: `E:\anki_data\`
   - Linux / macOS: `/mnt/us/anki_data/`
3. Locate your `collection.anki2` file on your computer:
   - **Windows**: `%APPDATA%\Anki2\<Profile Name>\collection.anki2`  
     *(e.g., `C:\Users\<User>\AppData\Roaming\Anki2\User 1\collection.anki2`)*
   - **Linux**: `~/.local/share/Anki2/<Profile Name>/collection.anki2`
   - **macOS**: `~/Library/Application Support/Anki2/<Profile Name>/collection.anki2`
4. Copy `collection.anki2` into `/mnt/us/anki_data/collection.anki2` on the Kindle.
5. Safely eject your Kindle and launch Ranki. All your decks, cards, and review schedules are instantly ready offline!

---

## How to Log In Using `config.ini`

Typing long passwords or handling two-factor authentication (2FA) on e-ink keyboards can be slow and awkward. Ranki lets you pre-configure your login token directly from your computer via `/mnt/us/extensions/ranki/config.ini`.

### `config.ini` Format
Open `/mnt/us/extensions/ranki/config.ini` in any text editor:
```ini
[General]
sync_media=false
collection_dir=/mnt/us/anki_data
hkey=r:your_ankiweb_sync_auth_key_here
sync_server=
scale=1.5
```

### How to Retrieve Your `hkey` Token
The `hkey` is AnkiWeb's session authentication token (starts with `r:`).

#### Option A: Extract from Anki Desktop on Your PC
If you are already logged into Anki on your PC, Anki has already saved this token (`syncKey`) in `prefs21.db`. You can retrieve it instantly:

- **Windows (PowerShell)**:
  ```powershell
  python -c "import sqlite3, pickle, glob, os; p = glob.glob(os.path.expandvars('%APPDATA%/Anki2/prefs21.db'))[0]; con = sqlite3.connect(p); cur = con.cursor(); rows = cur.execute('SELECT name, data FROM profiles WHERE name != \"_global\"').fetchall(); [print(f'Profile: {r[0]}\nhkey = {pickle.loads(r[1]).get(\"syncKey\", \"None\")}') for r in rows]; con.close()"
  ```
- **Linux / macOS (Bash)**:
  ```bash
  python3 -c "import sqlite3, pickle, os; p = os.path.expanduser('~/.local/share/Anki2/prefs21.db'); con = sqlite3.connect(p); cur = con.cursor(); rows = cur.execute('SELECT name, data FROM profiles WHERE name != \"_global\"').fetchall(); [print(f'Profile: {r[0]}\nhkey = {pickle.loads(r[1]).get(\"syncKey\", \"None\")}') for r in rows]; con.close()"
  ```
Copy the printed `hkey` value (e.g. `r:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`) and paste it into `config.ini`.

#### Option B: Log In via the Ranki UI
Alternatively, on the Kindle, go to **Settings** -> enter your AnkiWeb Username & Password -> tap **Login**. Ranki will fetch the token and automatically write it to `config.ini`.

---

## Setting Up the KOReader Offline Mining Plugin

This repository includes a standalone companion plugin located in [`koreader-plugin/anki.koplugin`](koreader-plugin/anki.koplugin).

It allows you to **sentence-mine and create Anki cards directly into `/mnt/us/anki_data/collection.anki2` while reading books in KOReader**, completely offline without needing a PC running AnkiConnect or active Wi-Fi.

### Key Highlights of the KOReader Plugin
- **Direct SQLite Engine (`ranki_local.lua`)**: Interacts directly with Ranki's SQLite database via KOReader's built-in `lua-ljsqlite3`.
- **Parameterized Queries**: Uses prepared statements (`conn:prepare`) with parameter binding. Dictionary definitions with semicolons, Japanese characters, HTML tags, or quotes will never corrupt SQL statements.
- **Automatic 2-Way Sync (`usn = -1`)**: All cards created in KOReader are assigned `usn = -1`. The next time you tap **Sync** in Ranki, the newly mined notes and cards are automatically uploaded to AnkiWeb and synced to your PC!

### Installation
1. Copy the `koreader-plugin/anki.koplugin` folder to your Kindle:
   ```text
   Kindle Root (e.g. E:\ or /mnt/us/)
   └── koreader/
       └── plugins/
           └── anki.koplugin/
               ├── ankiconnect.lua
               ├── main.lua
               ├── ranki_local.lua
               ├── profiles/
               │   ├── default.lua
               │   └── Mining.lua
               └── ...
   ```
2. Open or restart KOReader.

### Configuration (`profiles/Mining.lua` or `profiles/default.lua`)
Edit `koreader/plugins/anki.koplugin/profiles/Mining.lua` to match your deck and card template:
```lua
local Config = {
    -- Target Anki Deck
    deckName = "Mining",

    -- Note type / Model in your collection (e.g. "Lapis", "Kaishi", "Basic")
    modelName = "Lapis",

    -- Field name where the looked-up word is placed
    word_field = "Expression",

    -- Field name where the dictionary definition is placed
    def_field = "Glossary",

    -- Field name where the book context sentence is placed
    context_field = "Sentence",

    -- Custom tags added to mined notes
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

### Mining Workflow
1. Open any EPUB, MOBI, or text book in KOReader.
2. Select / highlight any word or sentence to trigger the dictionary lookup popup.
3. Tap **"Add to Anki"** at the bottom of the popup.
4. A notification **`Added note to RAnki (Mining)`** will confirm the note was created.
5. When finished reading, open **Ranki** and tap **Sync** to upload your new cards to AnkiWeb.

---

## Media Sync Toggle (Memory & Storage Optimization)

On devices with limited storage and RAM (such as the Kindle Touch 4th Gen with 256MB RAM), syncing thousands of audio clips and images can cause out-of-memory errors or fill up your storage.

### How to Toggle Media Sync
1. **Via KUAL**: Open KUAL -> **Ranki** -> **Toggle Media Sync**.
2. **Via `config.ini`**: Set `sync_media=false` under `[General]` in `/mnt/us/extensions/ranki/config.ini`.

When disabled, Ranki syncs your collection text, notes, and card schedules without downloading media files.

---

## Technical Details

- **Language / Framework**: Vala & GTK+ 2.0 with WebKitGTK.
- **Anki Backend**: Official Rust backend compiled for ARM EABI (`armel` and `armhf`), communicating via protobuf (v25.09.02).
- **Kindle Compatibility**:
  - `libk5compat.so`: Provides `clock_gettime`, `getauxval`, and atexit shims for glibc 2.12.1.
  - `liblipc.so.1` & `libcurl.so.4`: Shims for device IPC and secure networking.
  - Patched ELF version headers to ensure dynamic linking compatibility on legacy kernels (Linux 2.6.31).

---

## Custom Kindle Card Styling

Ranki injects a `.kindle` CSS class into card containers. You can add Kindle-specific styles to your card templates in Anki:

```css
.kindle {
    font-size: 1.1em;
}
.kindle .highlight {
    font-weight: bold;
    text-decoration: underline;
}
```

---

## Troubleshooting

### "Unrecognized token" or error while saving note in KOReader
Ensure you are using the updated `ranki_local.lua` from this repository. Previous versions split queries on semicolons in dictionary entries; the current version uses parameterized SQLite prepared statements.

### Text or characters not displaying correctly?
Ranki uses fonts installed on the Kindle. Install custom Japanese or unicode fonts following the official Anki [font installation guide](https://docs.ankiweb.net/templates/styling.html#installing-fonts). Use non-variable (static) TTF/OTF fonts.

---

## License & Credits

- Ranki is licensed under the **GNU General Public License v3 (GPL-3.0)**.
- Original project by [crazy-electron](https://github.com/crazy-electron/ranki).
- Kindle Touch 4th Gen port and KOReader offline local integration by [1Selxo](https://github.com/1Selxo/ranki).
- `anki.koplugin` based on [Ajatt-Tools/anki.koplugin](https://github.com/Ajatt-Tools/anki.koplugin).
