-- Macaroon OS updater API
-- Used by startup.lua (boot check), update.lua (shell), and the Update desktop app.
-- No 5.4-only syntax. Remote code is never executed except the manifest
-- (loaded in a sandbox returning a list).

local Updater = {}

local FALLBACK_URL = "https://raw.githubusercontent.com/Codingishardlol/MacaroonOS/main"
local URL_FILE = "macaroon/update_url.txt"
local VERSION_PATH = "macaroon/version.lua"
local MANIFEST_PATH = "macaroon/manifest.lua"

function Updater.getBaseURL()
  if fs.exists(URL_FILE) then
    local h = fs.open(URL_FILE, "r")
    if h then
      local url = h.readAll() or ""
      h.close()
      -- trim whitespace
      url = string.gsub(url or "", "^%s*(.-)%s*$", "%1")
      if url ~= "" then
        if string.sub(url, -1) == "/" then
          url = string.sub(url, 1, -2)
        end
        return url
      end
    end
  end
  return FALLBACK_URL
end

function Updater.setBaseURL(url)
  url = string.gsub(url or "", "^%s*(.-)%s*$", "%1")
  if string.sub(url, -1) == "/" then
    url = string.sub(url, 1, -2)
  end
  local dir = fs.getDir(URL_FILE)
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
  local h = fs.open(URL_FILE, "w")
  if not h then return false end
  h.write(url)
  h.close()
  return true
end

function Updater.getLocalVersion()
  if not fs.exists(VERSION_PATH) then
    return "0.0.0"
  end
  local ok, info = pcall(dofile, VERSION_PATH)
  if ok and type(info) == "table" and type(info.version) == "string" then
    return info.version
  end
  return "0.0.0"
end

local function parseVersionFromSource(src)
  if type(src) ~= "string" then return nil end
  -- matches: version = "1.2.3"
  local v = string.match(src, 'version%s*=%s*"([^"]+)"')
  if v then return v end
  v = string.match(src, "version%s*=%s*'([^']+)'")
  return v
end

local function splitVer(v)
  local parts = {}
  for n in string.gmatch(v or "", "(%d+)") do
    table.insert(parts, tonumber(n))
  end
  return parts
end

-- Raw hosts (GitHub raw, etc.) cache aggressively, so back-to-back
-- releases can read as "up to date" for minutes. Every updater GET
-- carries a unique query string; servers ignore it, CDNs key on it.
local function cacheBusted(url)
  local t = nil
  if os.epoch then
    local ok, e = pcall(os.epoch, "utc")
    if ok and type(e) == "number" then t = math.floor(e) end
  end
  if not t then
    t = math.floor((os.time() or 0) * 1000 + (os.clock() or 0) * 1000)
  end
  return url .. "?cb=" .. tostring(t)
end

-- http.get should return nil+err on failure, but some environments
-- throw instead (blocked host, no adapter, emulator quirks).
-- Never let that propagate: check() must never crash.
local function safeGet(url)
  if not http or not http.get then
    return nil, "HTTP disabled"
  end
  local ok, a, b = pcall(http.get, url)
  if not ok then
    return nil, "http error: " .. tostring(a)
  end
  if a == nil then
    return nil, tostring(b or "http failed")
  end
  return a
end

-- Only these basenames may never be written by install/update.
-- Manifests are remote-controlled: a rogue entry naming one of these
-- (e.g. users.dat) would wipe accounts and skip the login gate.
local PROTECTED = {
  ["users.dat"] = true, ["settings.dat"] = true,
  ["update_url.txt"] = true, ["crash.log"] = true,
  ["startup.bak"] = true, ["noautoupdate.txt"] = true,
  ["fails.dat"] = true,
}

-- safePath: validates a manifest/Store path before any write.
-- Returns true, or false + reason. Rejects absolute paths, dot-dot
-- traversal, non-Lua files, and protected data files.
function Updater.safePath(path)
  if type(path) ~= "string" or path == "" then
    return false, "empty path"
  end
  if string.sub(path, 1, 1) == "/" then
    return false, "absolute path"
  end
  if string.find(path, "%.%.") then
    return false, "dot-dot"
  end
  if string.sub(path, -4) ~= ".lua" then
    return false, "not lua"
  end
  local base = string.match(path, "([^/]+)$") or path
  if PROTECTED[base] then
    return false, "protected file"
  end
  return true
end

local function requireHTTPS(url)
  return type(url) == "string" and string.sub(url, 1, 8) == "https://"
end

-- Returns -1 if a<b, 0 if equal, 1 if a>b
function Updater.compare(a, b)
  local pa = splitVer(a)
  local pb = splitVer(b)
  local n = math.max(#pa, #pb)
  for i = 1, n do
    local x = pa[i] or 0
    local y = pb[i] or 0
    if x < y then return -1 end
    if x > y then return 1 end
  end
  return 0
end

function Updater.getRemoteVersion(baseURL)
  baseURL = baseURL or Updater.getBaseURL()
  if not http then
    return nil, "HTTP disabled"
  end
  if not requireHTTPS(baseURL) then
    return nil, "update source must be https"
  end
  local url = cacheBusted(baseURL .. "/" .. VERSION_PATH)
  local res, err = safeGet(url)
  if not res then
    return nil, err
  end
  local src = res.readAll()
  res.close()
  local v = parseVersionFromSource(src)
  if not v then
    return nil, "could not parse remote version"
  end
  return v
end

-- check() returns a single info table, never throws:
-- { localVer, remoteVer, updateAvailable, err, baseURL }.
-- Single value (not ok,info) so pcall(Updater.check) unpacks cleanly.
function Updater.check(baseURL)
  baseURL = baseURL or Updater.getBaseURL()
  local localVer = Updater.getLocalVersion()
  if not http then
    return { localVer = localVer, remoteVer = nil, updateAvailable = false, err = "HTTP disabled", baseURL = baseURL }
  end
  local remoteVer, err = Updater.getRemoteVersion(baseURL)
  if not remoteVer then
    return { localVer = localVer, remoteVer = nil, updateAvailable = false, err = err, baseURL = baseURL }
  end
  local cmp = Updater.compare(localVer, remoteVer)
  return { localVer = localVer, remoteVer = remoteVer, updateAvailable = cmp < 0, err = nil, baseURL = baseURL }
end

local function loadManifestFromSource(src)
  if type(src) ~= "string" or #src > 16384 then
    return nil, "manifest too big"
  end
  -- Charset gate: a manifest is return { "paths", ... } and nothing else.
  -- Anything outside this alphabet (calls, comments, escapes) is rejected
  -- BEFORE load, so hostile code can neither run nor hang us. Keywords
  -- need a second gate below: `while true do end` is all-charset-legal.
  if string.find(src, "[^%w%./_\"',%s{}]") then
    return nil, "manifest has illegal characters"
  end
  -- Keyword ban (separate loop: frontier+alternation groups don't mix
  -- in Lua patterns). `while true do end` is charset-legal, so without
  -- this it would reach load() and hang us with an unyielding loop.
  local bad = { "do", "end", "while", "for", "function", "repeat",
    "until", "if", "then", "else", "elseif", "local", "in" }
  for _, kw in ipairs(bad) do
    if string.find(src, "%f[%w_]" .. kw .. "%f[^%w_]") then
      return nil, "manifest has code keywords"
    end
  end
  local _, opens = string.gsub(src, "{", "")
  if opens > 64 then
    return nil, "manifest too nested"
  end
  local fn, err = load(src, "manifest", "t", {})
  if not fn then return nil, err end
  local ok, list = pcall(fn)
  if not ok then return nil, tostring(list) end
  if type(list) ~= "table" then return nil, "manifest did not return a table" end
  return list
end

function Updater.getFileList(baseURL)
  -- Prefer remote manifest so new files are picked up.
  baseURL = baseURL or Updater.getBaseURL()
  if http and requireHTTPS(baseURL) then
    local res = safeGet(cacheBusted(baseURL .. "/" .. MANIFEST_PATH))
    if res then
      local src = res.readAll()
      res.close()
      local list, err = loadManifestFromSource(src)
      if list then return list end
    end
  end
  -- Fallback to local manifest.
  if fs.exists(MANIFEST_PATH) then
    local ok, list = pcall(dofile, MANIFEST_PATH)
    if ok and type(list) == "table" then return list end
  end
  return nil, "no manifest available"
end

-- Downloads every file in the manifest. onProgress(path, i, total) optional.
-- Fail-closed: non-HTTPS sources and invalid manifest entries abort the
-- whole update; downloads over 256KB are refused. Returns true on
-- success, or false + err.
local MAX_DOWNLOAD = 262144
function Updater.perform(baseURL, onProgress)
  baseURL = baseURL or Updater.getBaseURL()
  if not http then
    return false, "HTTP disabled"
  end
  if not requireHTTPS(baseURL) then
    return false, "update source must be https"
  end
  local list, merr = Updater.getFileList(baseURL)
  if not list then
    return false, merr
  end
  for _, path in ipairs(list) do
    local okP, why = Updater.safePath(path)
    if not okP then
      return false, "blocked manifest entry " .. tostring(path)
        .. " (" .. tostring(why) .. ")"
    end
  end
  for i, path in ipairs(list) do
    if onProgress then
      pcall(onProgress, path, i, #list)
    end
    local url = cacheBusted(baseURL .. "/" .. path)
    local res, err = safeGet(url)
    if not res then
      return false, "FAILED " .. path .. ": " .. tostring(err)
    end
    local okR, data = pcall(res.readAll)
    pcall(res.close)
    if not okR then
      return false, "FAILED " .. path .. ": unreadable"
    end
    if not data or #data == 0 then
      return false, "FAILED " .. path .. ": empty file"
    end
    if #data > MAX_DOWNLOAD then
      return false, "FAILED " .. path .. ": too big"
    end
    local dir = fs.getDir(path)
    if dir ~= "" and dir ~= "." and not fs.exists(dir) then
      fs.makeDir(dir)
    end
    local out = fs.open(path, "w")
    if not out then
      return false, "FAILED " .. path .. ": cannot write"
    end
    out.write(data)
    out.close()
  end
  -- Remember source for next check.
  pcall(Updater.setBaseURL, baseURL)
  return true
end

return Updater
