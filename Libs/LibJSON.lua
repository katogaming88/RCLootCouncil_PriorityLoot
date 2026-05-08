-- Libs/LibJSON.lua
-- Lightweight JSON decoder for WoW's sandboxed Lua 5.1 environment.
-- Based on rxi/json.lua (MIT), stripped of all require/io/os/pcre dependencies.
--
-- Usage:
--   local ok, result = pcall(function() return LibRCPLJSON:decode(jsonString) end)
--
-- Exposes a single global: LibRCPLJSON
-- Methods:
--   LibRCPLJSON:decode(str)  → Lua value (table, string, number, boolean, nil)

LibRCPLJSON = {}

-- ─── Error helper ─────────────────────────────────────────────────────────────

local function json_error(str, pos, msg)
    msg = msg or "parse error"
    error(string.format("%s at position %d", msg, pos))
end

-- ─── Whitespace skip ──────────────────────────────────────────────────────────

local function skip_whitespace(str, pos)
    local _, endPos = str:find("^%s*", pos)
    return endPos + 1
end

-- ─── Forward declaration ──────────────────────────────────────────────────────

local decode_value  -- declared here, defined below; needed for recursion.

-- ─── String decoding ──────────────────────────────────────────────────────────

local ESCAPE_MAP = {
    ['"']  = '"',
    ['\\'] = '\\',
    ['/']  = '/',
    ['b']  = '\b',
    ['f']  = '\f',
    ['n']  = '\n',
    ['r']  = '\r',
    ['t']  = '\t',
}

local function decode_string(str, pos)
    -- pos points at the opening '"'
    local result = {}
    local i = pos + 1  -- skip opening quote
    local len = #str

    while i <= len do
        local ch = str:sub(i, i)

        if ch == '"' then
            -- Closing quote found.
            return table.concat(result), i + 1

        elseif ch == '\\' then
            i = i + 1
            local esc = str:sub(i, i)
            if ESCAPE_MAP[esc] then
                result[#result + 1] = ESCAPE_MAP[esc]
                i = i + 1
            elseif esc == 'u' then
                -- \uXXXX — decode 4 hex digits into a UTF-8 sequence.
                local hex = str:sub(i + 1, i + 4)
                if #hex < 4 then
                    json_error(str, i, "incomplete \\u escape")
                end
                local code = tonumber(hex, 16)
                if not code then
                    json_error(str, i, "invalid \\u escape")
                end
                -- Encode as UTF-8.
                if code <= 0x7F then
                    result[#result + 1] = string.char(code)
                elseif code <= 0x7FF then
                    result[#result + 1] = string.char(
                        0xC0 + math.floor(code / 64),
                        0x80 + (code % 64)
                    )
                else
                    result[#result + 1] = string.char(
                        0xE0 + math.floor(code / 4096),
                        0x80 + (math.floor(code / 64) % 64),
                        0x80 + (code % 64)
                    )
                end
                i = i + 5
            else
                json_error(str, i, "invalid escape character: \\" .. esc)
            end
        else
            result[#result + 1] = ch
            i = i + 1
        end
    end

    json_error(str, pos, "unterminated string")
end

-- ─── Number decoding ──────────────────────────────────────────────────────────

local function decode_number(str, pos)
    local num_str, endPos = str:match("^(-?%d+%.?%d*[eE]?[+-]?%d*)()", pos)
    if not num_str then
        json_error(str, pos, "invalid number")
    end
    return tonumber(num_str), endPos
end

-- ─── Array decoding ───────────────────────────────────────────────────────────

local function decode_array(str, pos)
    -- pos points at '['
    local arr = {}
    pos = skip_whitespace(str, pos + 1)

    if str:sub(pos, pos) == ']' then
        return arr, pos + 1  -- empty array
    end

    while true do
        local val
        val, pos = decode_value(str, pos)
        arr[#arr + 1] = val

        pos = skip_whitespace(str, pos)
        local ch = str:sub(pos, pos)

        if ch == ']' then
            return arr, pos + 1
        elseif ch == ',' then
            pos = skip_whitespace(str, pos + 1)
        else
            json_error(str, pos, "expected ',' or ']' in array")
        end
    end
end

-- ─── Object decoding ──────────────────────────────────────────────────────────

local function decode_object(str, pos)
    -- pos points at '{'
    local obj = {}
    pos = skip_whitespace(str, pos + 1)

    if str:sub(pos, pos) == '}' then
        return obj, pos + 1  -- empty object
    end

    while true do
        -- Key must be a string.
        if str:sub(pos, pos) ~= '"' then
            json_error(str, pos, "expected string key in object")
        end
        local key
        key, pos = decode_string(str, pos)

        pos = skip_whitespace(str, pos)
        if str:sub(pos, pos) ~= ':' then
            json_error(str, pos, "expected ':' after object key")
        end
        pos = skip_whitespace(str, pos + 1)

        local val
        val, pos = decode_value(str, pos)
        obj[key] = val

        pos = skip_whitespace(str, pos)
        local ch = str:sub(pos, pos)

        if ch == '}' then
            return obj, pos + 1
        elseif ch == ',' then
            pos = skip_whitespace(str, pos + 1)
        else
            json_error(str, pos, "expected ',' or '}' in object")
        end
    end
end

-- ─── Value dispatcher ─────────────────────────────────────────────────────────

decode_value = function(str, pos)
    pos = skip_whitespace(str, pos)
    local ch = str:sub(pos, pos)

    if ch == '"' then
        return decode_string(str, pos)
    elseif ch == '[' then
        return decode_array(str, pos)
    elseif ch == '{' then
        return decode_object(str, pos)
    elseif ch == 't' then
        if str:sub(pos, pos + 3) == "true" then
            return true, pos + 4
        end
        json_error(str, pos, "invalid token")
    elseif ch == 'f' then
        if str:sub(pos, pos + 4) == "false" then
            return false, pos + 5
        end
        json_error(str, pos, "invalid token")
    elseif ch == 'n' then
        if str:sub(pos, pos + 3) == "null" then
            return nil, pos + 4
        end
        json_error(str, pos, "invalid token")
    elseif ch == '-' or (ch >= '0' and ch <= '9') then
        return decode_number(str, pos)
    else
        json_error(str, pos, "unexpected character: " .. ch)
    end
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function LibRCPLJSON:decode(str)
    if type(str) ~= "string" then
        error("LibRCPLJSON:decode expects a string, got " .. type(str))
    end
    local value, _ = decode_value(str, 1)
    return value
end
