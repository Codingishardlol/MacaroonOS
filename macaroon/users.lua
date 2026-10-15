-- Macaroon OS - user accounts (salted SHA256)
-- File: macaroon/users.dat (never in manifest so updates keep accounts).
-- Parsed with patterns, NEVER load(): a hostile/corrupt dat file must
-- not execute or hang the login path (infinite-loop chunks don't yield).
-- Fail counter: macaroon/fails.dat (also never in manifest).

local Users = {}

local PATH = "macaroon/users.dat"
local FAILS_PATH = "macaroon/fails.dat"
local SHA_PATH = "macaroon/sha256.lua"
-- Provisioned marker: written on first successful account creation.
-- Lets boot tell "machine that once had accounts" (deleted users.dat =
-- tamper -> shut down) from a fresh copy (no marker -> boots open).
-- Never in manifest/install lists: it is local state, like users.dat.
local PROVISIONED_PATH = "macaroon/.provisioned"
-- Key stretching: each password goes through this many SHA256 rounds.
-- ~100 rounds ~= a few seconds on real CC hardware, but makes
-- brute force 100x more expensive. Stored per account so it stays
-- tunable without breaking existing logins.
local ROUNDS = 100
local MAX_ROUNDS = 1000 -- clamp: crafted files can't login-DoS us
local MAX_PW = 64 -- login input and stored passwords share this cap
local MAX_FILE = 16384 -- dat files bigger than this are ignored

local function loadSHA()
  local ok, sha = pcall(dofile, SHA_PATH)
  if ok and type(sha) == "table" and type(sha.digest) == "function" then
    return sha
  end
  return nil
end

local function validName(name)
  if type(name) ~= "string" then return false end
  if #name < 1 or #name > 16 then return false end
  return string.match(name, "^[A-Za-z0-9_%-]+$") ~= nil
end

local function readFile(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  if not h then return nil end
  local src = h.readAll()
  h.close()
  if type(src) ~= "string" or #src > MAX_FILE then return nil end
  return src
end

-- Parses users.dat without executing it. Returns { name = {salt,hash,rounds} }.
-- Accepts exactly the shape writeAll produces; anything else is ignored.
local function readAll()
  local t = {}
  local src = readFile(PATH)
  if not src then return t end
  for name, salt, hash, rounds in string.gmatch(src,
      "%[%s*\"([A-Za-z0-9_%-]+)\"%s*%]%s*=%s*{%s*salt%s*=%s*\"([0-9a-fA-F]+)\"%s*,%s*hash%s*=%s*\"([0-9a-fA-F]+)\"%s*,?%s*rounds%s*=%s*(%d+)%s*}") do
    if validName(name) and #salt <= 64 and #hash == 64 then
      local r = tonumber(rounds) or 1
      if r < 1 then r = 1 end
      if r > MAX_ROUNDS then r = MAX_ROUNDS end
      t[name] = { salt = salt, hash = string.lower(hash), rounds = r }
    end
  end
  -- Legacy single-round entries (no rounds field).
  for name, salt, hash in string.gmatch(src,
      "%[%s*\"([A-Za-z0-9_%-]+)\"%s*%]%s*=%s*{%s*salt%s*=%s*\"([0-9a-fA-F]+)\"%s*,%s*hash%s*=%s*\"([0-9a-fA-F]+)\"%s*}") do
    if validName(name) and t[name] == nil and #salt <= 64 and #hash == 64 then
      t[name] = { salt = salt, hash = string.lower(hash), rounds = 1 }
    end
  end
  return t
end

local function writeAll(t)
  local dir = fs.getDir(PATH)
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
  local h = fs.open(PATH, "w")
  if not h then return false end
  h.write("return {\n")
  for name, rec in pairs(t) do
    if validName(name) and type(rec) == "table" then
      h.write("  [" .. string.format("%q", name) .. "] = { salt = "
        .. string.format("%q", tostring(rec.salt))
        .. ", hash = " .. string.format("%q", tostring(rec.hash))
        .. ", rounds = " .. tostring(tonumber(rec.rounds) or 1) .. " },\n")
    end
  end
  h.write("}\n")
  h.close()
  return true
end

function Users.list()
  local t = readAll()
  local names = {}
  for name in pairs(t) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

local seeded = false
local function ensureSeed()
  -- Lua's math.random repeats the same sequence every boot unless
  -- seeded. Mix wall-clock, CPU clock, computer ID, and the current
  -- file size (differs per machine once accounts exist).
  if seeded then return end
  seeded = true
  local s = 0
  if os.epoch then
    local ok, e = pcall(os.epoch, "utc")
    if ok and type(e) == "number" then s = s + e end
  end
  if os.time then s = s + (os.time() * 1000) end
  if os.clock then s = s + math.floor(os.clock() * 1000000) end
  if os.getComputerID then
    local ok, id = pcall(os.getComputerID)
    if ok and type(id) == "number" then s = s + id * 7919 end
  end
  local cur = readFile(PATH)
  if cur then s = s + #cur * 2654435761 end
  s = s + #tostring({})
  math.randomseed(s % 2147483647)
  math.random()
  math.random()
  math.random()
end

local function newSalt()
  local parts = {}
  for _ = 1, 8 do
    local b = math.random(0, 255)
    local hi = math.floor(b / 16)
    local lo = b % 16
    local function hexd(d)
      if d < 10 then return string.char(48 + d) end
      return string.char(87 + d)
    end
    parts[#parts + 1] = hexd(hi) .. hexd(lo)
  end
  return table.concat(parts)
end

local function stretch(sha, salt, password, rounds)
  local h = sha.digest(salt .. ":" .. password)
  for _ = 2, rounds do
    h = sha.digest(h .. salt)
  end
  return h
end

-- Constant-time string compare: no early exit, no length oracle.
local function sameHash(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then return false end
  if #a ~= #b then return false end
  local diff = 0
  for i = 1, #a do
    local x = string.byte(a, i) - string.byte(b, i)
    if x ~= 0 then diff = diff + 1 end
  end
  return diff == 0
end

-- Creates (or overwrites) a user. Returns true, or false + err.
function Users.create(name, password)
  if not validName(name) then
    return false, "name 1-16 chars: letters, digits, _ -"
  end
  if type(password) ~= "string" or #password < 8 then
    return false, "password min 8 chars"
  end
  if #password > MAX_PW then
    return false, "password max " .. MAX_PW .. " chars"
  end
  local sha = loadSHA()
  if not sha then return false, "sha256 missing" end
  ensureSeed()
  local salt = newSalt()
  local hash = stretch(sha, salt, password, ROUNDS)
  local t = readAll()
  t[name] = { salt = salt, hash = hash, rounds = ROUNDS }
  if not writeAll(t) then return false, "cannot write users file" end
  -- Best-effort provisioned marker (see PROVISIONED_PATH). Must never
  -- fail account creation if the marker itself can't be written.
  pcall(function()
    local m = fs.open(PROVISIONED_PATH, "w")
    if m then
      m.write("provisioned\n")
      m.close()
    end
  end)
  return true
end

function Users.verify(name, password)
  if not validName(name) or type(password) ~= "string" then
    return false
  end
  if #password > MAX_PW then return false end
  local sha = loadSHA()
  if not sha then return false end
  local t = readAll()
  local rec = t[name]
  if type(rec) ~= "table" then return false end
  return sameHash(stretch(sha, rec.salt, password, rec.rounds), rec.hash)
end

function Users.remove(name)
  local t = readAll()
  if t[name] == nil then return false end
  t[name] = nil
  return writeAll(t)
end

function Users.hasAccounts()
  return #Users.list() > 0
end

-- Persistent fail counter (survives reboot, unlike login attempts).
-- Slows keyboard brute force even across power cycles.
function Users.failCount()
  local src = readFile(FAILS_PATH)
  return tonumber(src and string.match(src, "(%d+)")) or 0
end

function Users.recordFail()
  local n = Users.failCount() + 1
  local h = fs.open(FAILS_PATH, "w")
  if h then
    h.write(tostring(n) .. "\n")
    h.close()
  end
  return n
end

function Users.resetFails()
  if fs.exists(FAILS_PATH) then
    pcall(fs.delete, FAILS_PATH)
  end
end

function Users.maxPw()
  return MAX_PW
end

return Users
