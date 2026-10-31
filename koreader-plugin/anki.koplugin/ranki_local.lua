local logger = require("logger")

local RAnkiLocal = {
    DEFAULT_DB_PATH = "/mnt/us/anki_data/collection.anki2"
}

-- Fallback SQLite loader (KOReader uses lua-ljsqlite3)
local function get_sqlite()
    local ok, SQ3 = pcall(require, "lua-ljsqlite3/init")
    if ok and SQ3 then return SQ3 end
    ok, SQ3 = pcall(require, "lsqlite3")
    if ok and SQ3 then return SQ3 end
    ok, SQ3 = pcall(require, "sqlite3")
    if ok and SQ3 then return SQ3 end
    return nil, "No SQLite library found in KOReader environment"
end

-- Bitwise helper for pure Lua SHA-1 (LuaJIT bit module)
local bit = bit or bit32
local band, bor, bxor = bit.band, bit.bor, bit.bxor
local function rol(x, n)
    return bor(bit.lshift(x, n), bit.rshift(x, 32 - n))
end

-- Calculates 32-bit unsigned integer checksum for Anki's csum column (h0 of SHA-1)
local function sha1_csum(data)
    data = tostring(data or "")
    local len = #data
    local orig_len_bits = len * 8

    -- Padding: 0x80 byte, zero bytes, 64-bit length
    local pad = { 0x80 }
    while ((len + 1 + #pad - 1) % 64) ~= 56 do
        table.insert(pad, 0x00)
    end
    -- 64-bit big endian length
    local high_bits = math.floor(orig_len_bits / 0x100000000)
    local low_bits = orig_len_bits % 0x100000000
    for i = 3, 0, -1 do
        table.insert(pad, band(bit.rshift(high_bits, i * 8), 0xFF))
    end
    for i = 3, 0, -1 do
        table.insert(pad, band(bit.rshift(low_bits, i * 8), 0xFF))
    end

    local h0 = 0x67452301
    local h1 = 0xEFCDAB89
    local h2 = 0x98BADCFE
    local h3 = 0x10325476
    local h4 = 0xC3D2E1F0

    local total_len = len + #pad
    local function get_byte(idx)
        if idx <= len then
            return string.byte(data, idx)
        else
            return pad[idx - len]
        end
    end

    for chunk_offset = 1, total_len, 64 do
        local w = {}
        for i = 0, 15 do
            local o = chunk_offset + i * 4
            local b1 = get_byte(o)
            local b2 = get_byte(o + 1)
            local b3 = get_byte(o + 2)
            local b4 = get_byte(o + 3)
            w[i] = bor(bor(bit.lshift(b1, 24), bit.lshift(b2, 16)), bor(bit.lshift(b3, 8), b4))
        end
        for i = 16, 79 do
            w[i] = rol(bxor(bxor(w[i - 3], w[i - 8]), bxor(w[i - 14], w[i - 16])), 1)
        end

        local a, b, c, d, e = h0, h1, h2, h3, h4
        for i = 0, 79 do
            local f, k
            if i <= 19 then
                f = bor(band(b, c), band(bit.bnot(b), d))
                k = 0x5A827999
            elseif i <= 39 then
                f = bxor(bxor(b, c), d)
                k = 0x6ED9EBA1
            elseif i <= 59 then
                f = bor(bor(band(b, c), band(b, d)), band(c, d))
                k = 0x8F1BBCDC
            else
                f = bxor(bxor(b, c), d)
                k = 0xCA62C1D6
            end
            local temp = band(rol(a, 5) + f + e + k + w[i], 0xFFFFFFFF)
            e = d
            d = c
            c = rol(b, 30)
            b = a
            a = temp
        end

        h0 = band(h0 + a, 0xFFFFFFFF)
        h1 = band(h1 + b, 0xFFFFFFFF)
        h2 = band(h2 + c, 0xFFFFFFFF)
        h3 = band(h3 + d, 0xFFFFFFFF)
        h4 = band(h4 + e, 0xFFFFFFFF)
    end

    -- Return 32-bit unsigned integer
    if h0 < 0 then
        return h0 + 0x100000000
    end
    return h0
end

-- 10-char Anki GUID generator
local GUID_CHARS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!#$%&()*+,-./:;<=>?@[]^_`{|}~"
local function generate_guid()
    local guid = {}
    for _ = 1, 10 do
        local rand_idx = math.random(1, #GUID_CHARS)
        table.insert(guid, string.sub(GUID_CHARS, rand_idx, rand_idx))
    end
    return table.concat(guid)
end

-- LuaJIT FFI int64 helper & sqlite collation support
local ok_ffi, ffi = pcall(require, "ffi")
local int64_ct = ok_ffi and ffi.typeof("int64_t")
local sql_lib = nil
if ok_ffi then
    pcall(function()
        sql_lib = ffi.loadlib("sqlite3", "0")
        ffi.cdef[[
            typedef int (*ljsqlite3_collation)(void*, int, const void*, int, const void*);
            int sqlite3_create_collation(void *db, const char *zName, int eTextRep, void *pArg, ljsqlite3_collation xCompare);
        ]]
    end)
end

local c_unicase_cmp = nil
if ok_ffi and sql_lib then
    pcall(function()
        local function unicase_cmp(arg, l1, s1, l2, s2)
            local str1 = ffi.string(s1, l1):lower()
            local str2 = ffi.string(s2, l2):lower()
            if str1 < str2 then return -1 end
            if str1 > str2 then return 1 end
            return 0
        end
        c_unicase_cmp = ffi.cast("ljsqlite3_collation", unicase_cmp)
    end)
end

local function to_sql_int(val)
    if val == nil then return "0" end
    if type(val) == "number" then
        return string.format("%.0f", val)
    end
    local s = tostring(val)
    s = s:gsub("[uU]?[lL][lL]$", "")
    return s
end

local function to_int64(val)
    if val == nil then
        if ok_ffi and int64_ct then return ffi.cast(int64_ct, 0) end
        return 0
    end
    if ok_ffi and int64_ct and ffi.istype(int64_ct, val) then
        return val
    end
    local num = tonumber(to_sql_int(val)) or 0
    if ok_ffi and int64_ct then
        return ffi.cast(int64_ct, num)
    end
    return num
end

-- Strip HTML tags for Anki sort field (sfld)
local function strip_html(str)
    if not str then return "" end
    -- Remove HTML comments
    str = string.gsub(str, "<!%-%-.-%-%->", "")
    -- Remove HTML tags
    str = string.gsub(str, "<[^>]+>", "")
    -- Replace common HTML entities
    str = string.gsub(str, "&nbsp;", " ")
    str = string.gsub(str, "&amp;", "&")
    str = string.gsub(str, "&lt;", "<")
    str = string.gsub(str, "&gt;", ">")
    str = string.gsub(str, "&quot;", "\"")
    return str
end

function RAnkiLocal.get_db_path()
    local candidates = {
        RAnkiLocal.custom_path,
        RAnkiLocal.DEFAULT_DB_PATH,
        "E:/anki_data/collection.anki2",
        "C:/Users/basel/AppData/Roaming/Anki2/ユーザー 1/collection.anki2"
    }
    for _, path in ipairs(candidates) do
        if path then
            local f = io.open(path, "rb")
            if f then
                f:close()
                return path
            end
        end
    end
    return RAnkiLocal.DEFAULT_DB_PATH
end

function RAnkiLocal.is_available()
    local path = RAnkiLocal.get_db_path()
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true, path
    end
    return false, string.format("RAnki database not found at %s", path)
end

function RAnkiLocal.open_db()
    local SQ3, err = get_sqlite()
    if not SQ3 then
        return nil, err
    end
    local path = RAnkiLocal.get_db_path()
    local ok, conn = pcall(SQ3.open, path)
    if not ok or not conn then
        return nil, string.format("Failed to open SQLite database '%s': %s", path, conn or err)
    end

    -- Register unicase collation so SQLite's query planner handles Anki's WITHOUT ROWID indexes and sqlite_stat4 samples
    if ok_ffi and sql_lib and conn and conn._ptr and c_unicase_cmp then
        pcall(function()
            sql_lib.sqlite3_create_collation(conn._ptr, "unicase", 1, nil, c_unicase_cmp)
            sql_lib.sqlite3_create_collation(conn._ptr, "UNICASE", 1, nil, c_unicase_cmp)
        end)
    end

    return conn
end

function RAnkiLocal.get_decknames()
    local conn, err = RAnkiLocal.open_db()
    if not conn then return nil, err end

    local decks = {}
    local ok, res = pcall(function()
        local stmt = conn:prepare("SELECT name FROM decks ORDER BY name COLLATE BINARY")
        while true do
            local r = stmt:step()
            if not r then break end
            table.insert(decks, r[1])
        end
        stmt:close()
    end)
    conn:close()
    if not ok then
        return nil, string.format("Error fetching decks: %s", res)
    end
    return decks
end

function RAnkiLocal.get_modelnames()
    local conn, err = RAnkiLocal.open_db()
    if not conn then return nil, err end

    local models = {}
    local ok, res = pcall(function()
        local stmt = conn:prepare("SELECT name FROM notetypes ORDER BY name COLLATE BINARY")
        while true do
            local r = stmt:step()
            if not r then break end
            table.insert(models, r[1])
        end
        stmt:close()
    end)
    conn:close()
    if not ok then
        return nil, string.format("Error fetching notetypes: %s", res)
    end
    return models
end

-- Fast duplicate check for dictionary popup button status
function RAnkiLocal.is_duplicate_word(word, deck_name)
    if not word or word == "" then return false end
    local conn, err = RAnkiLocal.open_db()
    if not conn then return false end

    local clean_word = strip_html(word)
    local csum_num = sha1_csum(clean_word)

    local is_dup = false
    pcall(function()
        local dup_stmt
        if deck_name then
            local d_stmt = conn:prepare("SELECT id FROM decks WHERE name = ? COLLATE BINARY")
            d_stmt:bind(deck_name)
            local d_row = d_stmt:step()
            local did = d_row and d_row[1]
            d_stmt:close()

            if did then
                dup_stmt = conn:prepare(string.format([[
                    SELECT n.id FROM notes n
                    JOIN cards c ON n.id = c.nid
                    WHERE c.did = %s AND n.csum = ? AND n.sfld = ?
                    LIMIT 1
                ]], to_sql_int(did)))
                dup_stmt:bind(to_int64(csum_num), clean_word)
            end
        end

        if not dup_stmt then
            dup_stmt = conn:prepare([[
                SELECT id FROM notes
                WHERE csum = ? AND sfld = ?
                LIMIT 1
            ]])
            dup_stmt:bind(to_int64(csum_num), clean_word)
        end

        local row = dup_stmt:step()
        if row and row[1] then
            is_dup = true
        end
        dup_stmt:close()
    end)

    conn:close()
    return is_dup
end

-- Direct local card & note insertion into RAnki collection.anki2
function RAnkiLocal.add_note(note)
    local conn, err = RAnkiLocal.open_db()
    if not conn then return nil, err end

    local deck_name = note.deckName or "Mining"
    local model_name = note.modelName or "Lapis"

    local note_id = nil
    local exec_ok, exec_err = pcall(function()
        -- 1. Find deck ID
        local deck_stmt = conn:prepare("SELECT id FROM decks WHERE name = ? COLLATE BINARY")
        deck_stmt:bind(deck_name)
        local deck_row = deck_stmt:step()
        local did = deck_row and deck_row[1]
        deck_stmt:close()
        if not did then
            error(string.format("Deck '%s' not found in RAnki database!", deck_name))
        end
        local did_sql = to_sql_int(did)

        -- 2. Find model (notetype) ID
        local model_stmt = conn:prepare("SELECT id FROM notetypes WHERE name = ? COLLATE BINARY")
        model_stmt:bind(model_name)
        local model_row = model_stmt:step()
        local mid = model_row and model_row[1]
        model_stmt:close()
        if not mid then
            error(string.format("Note type (model) '%s' not found in RAnki database!", model_name))
        end
        local mid_sql = to_sql_int(mid)

        -- 3. Fetch fields for model in ord order
        local fields = {}
        local f_ok = pcall(function()
            local fields_stmt = conn:prepare(string.format("SELECT name FROM fields WHERE ntid = %s ORDER BY ord ASC", mid_sql))
            while true do
                local r = fields_stmt:step()
                if not r then break end
                table.insert(fields, r[1])
            end
            fields_stmt:close()
        end)
        if not f_ok or #fields == 0 then
            logger.warn("RAnkiLocal: Could not query fields table, using fallback model schema for", model_name)
            if model_name == "Lapis" then
                fields = {
                    "Expression", "ExpressionFurigana", "ExpressionReading", "ExpressionAudio",
                    "SelectionText", "MainDefinition", "DefinitionPicture", "Sentence",
                    "SentenceFurigana", "SentenceAudio", "Picture", "Glossary", "Hint",
                    "IsWordAndSentenceCard", "IsClickCard", "IsSentenceCard", "IsAudioCard",
                    "PitchPosition", "PitchCategories", "Frequency", "FreqSort", "MiscInfo"
                }
            elseif model_name == "Kaishi" then
                fields = { "Word", "Reading", "Meaning", "Sentence", "SentenceReading", "SentenceMeaning", "Audio", "Image" }
            else
                fields = { "Front", "Back" }
            end
        end

        -- 4. Fetch templates for model in ord order
        local templates = {}
        pcall(function()
            local tmpls_stmt = conn:prepare(string.format("SELECT ord FROM templates WHERE ntid = %s ORDER BY ord ASC", mid_sql))
            while true do
                local r = tmpls_stmt:step()
                if not r then break end
                table.insert(templates, r[1])
            end
            tmpls_stmt:close()
        end)
        if #templates == 0 then
            table.insert(templates, 0)
        end
        tmpls_stmt:close()
        if #templates == 0 then
            table.insert(templates, 0)
        end

        -- 5. Build flds string & sfld
        local note_fields = note.fields or {}
        local fld_values = {}
        local first_field = ""
        for i, fname in ipairs(fields) do
            local val = note_fields[fname] or ""
            table.insert(fld_values, val)
            if i == 1 then first_field = val end
        end
        local flds_str = table.concat(fld_values, string.char(31))
        local sfld = strip_html(first_field)
        local csum_num = sha1_csum(sfld)

        -- 6. Duplicate check
        local options = note.options or {}
        if not options.allowDuplicate then
            local is_dup = false
            local dup_stmt
            if options.duplicateScope == "deck" then
                dup_stmt = conn:prepare(string.format([[
                    SELECT n.id FROM notes n
                    JOIN cards c ON n.id = c.nid
                    WHERE c.did = %s AND n.csum = ? AND n.sfld = ?
                    LIMIT 1
                ]], did_sql))
                dup_stmt:bind(to_int64(csum_num), sfld)
            else
                dup_stmt = conn:prepare([[
                    SELECT id FROM notes
                    WHERE csum = ? AND sfld = ?
                    LIMIT 1
                ]])
                dup_stmt:bind(to_int64(csum_num), sfld)
            end
            local row = dup_stmt:step()
            if row then
                is_dup = true
            end
            dup_stmt:close()
            if is_dup then
                error("cannot create note because it is a duplicate")
            end
        end

        -- 7. Generate timestamps, ID and GUID
        local now_sec = os.time()
        math.randomseed(now_sec + os.clock() * 1000)
        local now_ms = now_sec * 1000 + math.random(1, 999)
        local guid = generate_guid()

        -- Format tags: " tag1 tag2 "
        local tags_str = ""
        if note.tags and #note.tags > 0 then
            tags_str = " " .. table.concat(note.tags, " ") .. " "
        end

        -- 8. Find max due for new cards (type = 0)
        local max_due = 0
        local due_stmt = conn:prepare("SELECT COALESCE(MAX(due), 0) FROM cards WHERE type = 0")
        local due_row = due_stmt:step()
        if due_row and due_row[1] then
            max_due = tonumber(to_sql_int(due_row[1])) or 0
        end
        due_stmt:close()
        local new_due = max_due + 1

        -- 9. Insert Note & Cards in a Transaction
        conn:exec("BEGIN TRANSACTION")

        local note_stmt = conn:prepare([[
            INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data)
            VALUES (?, ?, ?, ?, -1, ?, ?, ?, ?, 0, '')
        ]])
        note_stmt:bind(
            to_int64(now_ms),
            guid,
            to_int64(mid),
            to_int64(now_sec),
            tags_str,
            flds_str,
            sfld,
            to_int64(csum_num)
        )
        note_stmt:step()
        note_stmt:close()

        -- 10. Insert Cards for templates
        local card_stmt = conn:prepare([[
            INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, flags, data)
            VALUES (?, ?, ?, ?, ?, -1, 0, 0, ?, 0, 0, 0, 0, 0, 0, 0, 0, '{}')
        ]])
        local card_id = now_ms + 1
        for _, tmpl_ord in ipairs(templates) do
            card_stmt:clearbind():reset()
            card_stmt:bind(
                to_int64(card_id),
                to_int64(now_ms),
                to_int64(did),
                to_int64(tmpl_ord),
                to_int64(now_sec),
                to_int64(new_due)
            )
            card_stmt:step()
            card_id = card_id + 1
        end
        card_stmt:close()

        -- 11. Update col.mod
        local col_stmt = conn:prepare("UPDATE col SET mod = ?")
        col_stmt:bind(to_int64(now_ms))
        col_stmt:step()
        col_stmt:close()

        conn:exec("COMMIT")
        note_id = to_sql_int(now_ms)
    end)

    if not exec_ok then
        pcall(function() conn:exec("ROLLBACK") end)
        conn:close()
        logger.warn("RAnkiLocal: Failed to add note:", exec_err)
        return nil, exec_err
    end

    conn:close()
    return note_id
end

function RAnkiLocal.delete_note(note_id)
    local conn, err = RAnkiLocal.open_db()
    if not conn then return nil, err end

    local nid = to_int64(note_id)
    local now_ms = to_int64(os.time() * 1000)

    local ok, res = pcall(function()
        conn:exec("BEGIN TRANSACTION")

        -- Record grave for note
        local g_note_stmt = conn:prepare("INSERT INTO graves (oid, type, usn) VALUES (?, 0, -1)")
        g_note_stmt:bind(nid)
        g_note_stmt:step()
        g_note_stmt:close()

        -- Find cards for note
        local c_find_stmt = conn:prepare("SELECT id FROM cards WHERE nid = ?")
        c_find_stmt:bind(nid)
        local card_ids = {}
        while true do
            local r = c_find_stmt:step()
            if not r then break end
            table.insert(card_ids, r[1])
        end
        c_find_stmt:close()

        -- Record graves for cards
        local g_card_stmt = conn:prepare("INSERT INTO graves (oid, type, usn) VALUES (?, 1, -1)")
        for _, cid in ipairs(card_ids) do
            g_card_stmt:clearbind():reset()
            g_card_stmt:bind(to_int64(cid))
            g_card_stmt:step()
        end
        g_card_stmt:close()

        -- Delete cards
        local d_cards_stmt = conn:prepare("DELETE FROM cards WHERE nid = ?")
        d_cards_stmt:bind(nid)
        d_cards_stmt:step()
        d_cards_stmt:close()

        -- Delete note
        local d_note_stmt = conn:prepare("DELETE FROM notes WHERE id = ?")
        d_note_stmt:bind(nid)
        d_note_stmt:step()
        d_note_stmt:close()

        -- Update col.mod
        local col_stmt = conn:prepare("UPDATE col SET mod = ?")
        col_stmt:bind(now_ms)
        col_stmt:step()
        col_stmt:close()

        conn:exec("COMMIT")
    end)

    if not ok then
        pcall(function() conn:exec("ROLLBACK") end)
    end
    conn:close()

    if not ok then
        return nil, res
    end
    return true
end

return RAnkiLocal
