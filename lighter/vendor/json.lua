-- Minimal pure-Lua JSON encoder/decoder
-- Handles the subset needed by Lighter (config, harpoon, AI responses)

local json = {}

local escape_chars = {
  ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n",
  ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f",
}

local function escape_string(s)
  return '"' .. s:gsub('[\\"\n\r\t\b\f]', escape_chars) .. '"'
end

function json.encode(val, indent, level)
  level = level or 0
  local t = type(val)
  if val == nil or val == json.null then
    return "null"
  elseif t == "boolean" then
    return tostring(val)
  elseif t == "number" then
    if val ~= val then return "null" end -- NaN
    if val >= math.huge then return "1e999" end
    if val <= -math.huge then return "-1e999" end
    return string.format("%.14g", val)
  elseif t == "string" then
    return escape_string(val)
  elseif t == "table" then
    local is_array = #val > 0 or next(val) == nil
    if is_array then
      -- check it's really an array
      local n = #val
      for k in pairs(val) do
        if type(k) ~= "number" or k < 1 or k > n or math.floor(k) ~= k then
          is_array = false
          break
        end
      end
    end
    local parts = {}
    local sep = indent and ",\n" or ","
    local pre = indent and string.rep(indent, level + 1) or ""
    local post = indent and string.rep(indent, level) or ""
    if is_array then
      for i, v in ipairs(val) do
        parts[i] = pre .. json.encode(v, indent, level + 1)
      end
      if #parts == 0 then return "[]" end
      return "[\n" .. table.concat(parts, sep) .. "\n" .. post .. "]"
    else
      local i = 0
      for k, v in pairs(val) do
        i = i + 1
        parts[i] = pre .. escape_string(tostring(k)) .. ": " .. json.encode(v, indent, level + 1)
      end
      if #parts == 0 then return "{}" end
      return "{\n" .. table.concat(parts, sep) .. "\n" .. post .. "}"
    end
  end
  return "null"
end

-- Decoder
local function skip_whitespace(str, pos)
  return str:match("^%s*()", pos)
end

local function decode_string(str, pos)
  local start = pos + 1 -- skip opening quote
  local buf = {}
  local i = start
  while i <= #str do
    local c = str:sub(i, i)
    if c == '"' then
      return table.concat(buf), i + 1
    elseif c == '\\' then
      i = i + 1
      c = str:sub(i, i)
      if c == 'n' then buf[#buf+1] = '\n'
      elseif c == 'r' then buf[#buf+1] = '\r'
      elseif c == 't' then buf[#buf+1] = '\t'
      elseif c == 'b' then buf[#buf+1] = '\b'
      elseif c == 'f' then buf[#buf+1] = '\f'
      elseif c == 'u' then
        local hex = str:sub(i+1, i+4)
        local code = tonumber(hex, 16)
        if code then
          if code < 0x80 then
            buf[#buf+1] = string.char(code)
          elseif code < 0x800 then
            buf[#buf+1] = string.char(0xC0 + math.floor(code / 64), 0x80 + (code % 64))
          else
            buf[#buf+1] = string.char(
              0xE0 + math.floor(code / 4096),
              0x80 + math.floor((code % 4096) / 64),
              0x80 + (code % 64)
            )
          end
          i = i + 4
        end
      else
        buf[#buf+1] = c
      end
    else
      buf[#buf+1] = c
    end
    i = i + 1
  end
  error("unterminated string at position " .. pos)
end

local decode_value -- forward declaration

local function decode_array(str, pos)
  pos = pos + 1 -- skip [
  pos = skip_whitespace(str, pos)
  local arr = {}
  if str:sub(pos, pos) == "]" then return arr, pos + 1 end
  while true do
    local val
    val, pos = decode_value(str, pos)
    arr[#arr+1] = val
    pos = skip_whitespace(str, pos)
    local c = str:sub(pos, pos)
    if c == "]" then return arr, pos + 1 end
    if c ~= "," then error("expected ',' or ']' at position " .. pos) end
    pos = skip_whitespace(str, pos + 1)
  end
end

local function decode_object(str, pos)
  pos = pos + 1 -- skip {
  pos = skip_whitespace(str, pos)
  local obj = {}
  if str:sub(pos, pos) == "}" then return obj, pos + 1 end
  while true do
    if str:sub(pos, pos) ~= '"' then error("expected string key at position " .. pos) end
    local key
    key, pos = decode_string(str, pos)
    pos = skip_whitespace(str, pos)
    if str:sub(pos, pos) ~= ":" then error("expected ':' at position " .. pos) end
    pos = skip_whitespace(str, pos + 1)
    local val
    val, pos = decode_value(str, pos)
    obj[key] = val
    pos = skip_whitespace(str, pos)
    local c = str:sub(pos, pos)
    if c == "}" then return obj, pos + 1 end
    if c ~= "," then error("expected ',' or '}' at position " .. pos) end
    pos = skip_whitespace(str, pos + 1)
  end
end

decode_value = function(str, pos)
  pos = skip_whitespace(str, pos)
  local c = str:sub(pos, pos)
  if c == '"' then
    return decode_string(str, pos)
  elseif c == '{' then
    return decode_object(str, pos)
  elseif c == '[' then
    return decode_array(str, pos)
  elseif c == 't' then
    if str:sub(pos, pos+3) == "true" then return true, pos + 4 end
  elseif c == 'f' then
    if str:sub(pos, pos+4) == "false" then return false, pos + 5 end
  elseif c == 'n' then
    if str:sub(pos, pos+3) == "null" then return nil, pos + 4 end
  else
    local num_str = str:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
    if num_str then
      return tonumber(num_str), pos + #num_str
    end
  end
  error("unexpected character '" .. c .. "' at position " .. pos)
end

function json.decode(str)
  if type(str) ~= "string" or str == "" then
    return nil, "invalid input"
  end
  local ok, result, _ = pcall(decode_value, str, 1)
  if ok then
    return result
  else
    return nil, result
  end
end

-- Sentinel for explicit null values
json.null = setmetatable({}, { __tostring = function() return "null" end })

return json
