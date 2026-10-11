-- Macaroon OS - settings store
-- File: macaroon/settings.dat (Lua chunk, never in manifest so updates keep it).
-- Keys: wallpaper (color number), clock24 (bool), autoupdate (bool).

local Settings = {}

local PATH = "macaroon/settings.dat"

local DEFAULTS = {
  wallpaper = 8, -- colours.lightBlue; stored as number to avoid colours dep
  clock24 = true,
  autoupdate = true,
}

local function isColorNum(n)
  -- Valid CC color values are powers of two 1..32768
  if type(n) ~= "number" then return false end
  for i = 0, 15 do
    if n == 2 ^ i then return true end
  end
  return false
end

local function sanitize(t)
  local out = {}
  for k, v in pairs(DEFAULTS) do out[k] = v end
  if type(t) == "table" then
    if isColorNum(t.wallpaper) then out.wallpaper = t.wallpaper end
    if type(t.clock24) == "boolean" then out.clock24 = t.clock24 end
    if type(t.autoupdate) == "boolean" then out.autoupdate = t.autoupdate end
  end
  return out
end

function Settings.load()
  if not fs.exists(PATH) then
    return sanitize(nil)
  end
  local h = fs.open(PATH, "r")
  if not h then return sanitize(nil) end
  local src = h.readAll()
  h.close()
  local fn, err = load(src, "settings", "t", {})
  if not fn then return sanitize(nil) end
  local ok, t = pcall(fn)
  if not ok then return sanitize(nil) end
  return sanitize(t)
end

function Settings.save(s)
  s = sanitize(s)
  local dir = fs.getDir(PATH)
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
  local h = fs.open(PATH, "w")
  if not h then return false end
  h.write("return {\n")
  h.write("  wallpaper = " .. tostring(s.wallpaper) .. ",\n")
  h.write("  clock24 = " .. tostring(s.clock24) .. ",\n")
  h.write("  autoupdate = " .. tostring(s.autoupdate) .. ",\n")
  h.write("}\n")
  h.close()
  -- Keep legacy opt-out file in sync: updater checks it, settings owns it.
  if s.autoupdate then
    if fs.exists("macaroon/noautoupdate.txt") then
      fs.delete("macaroon/noautoupdate.txt")
    end
  else
    local h2 = fs.open("macaroon/noautoupdate.txt", "w")
    if h2 then h2.write("1") h2.close() end
  end
  return true
end

function Settings.get(key)
  local s = Settings.load()
  if s[key] ~= nil then return s[key] end
  return DEFAULTS[key]
end

function Settings.set(key, value)
  if key == "wallpaper" and not isColorNum(value) then return false end
  if (key == "clock24" or key == "autoupdate") and type(value) ~= "boolean" then
    return false
  end
  if DEFAULTS[key] == nil then return false end
  local s = Settings.load()
  s[key] = value
  return Settings.save(s)
end

return Settings
