-- Macaroon OS - user accounts (salted SHA256)
-- File: macaroon/users.dat (never in manifest so updates keep accounts).
-- Format: Lua chunk returning { name = { salt=..., hash=... } }.

local Users = {}

local PATH = "macaroon/users.dat"
local SHA_PATH = "macaroon/sha256.lua"
-- Key stretching: each password goes through this many SHA256 rounds.
-- ~100 rounds ~= a few seconds on real CC hardware, but makes
-- brute force 100x more expensive. Stored per account so it stays
-- tunable without breaking existing logins.
local ROUNDS = 100

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

function Users.list()
  if not fs.exists(PATH) then return {} end
  local h = fs.open(PATH, "r")
  if not h then return {} end
  local src = h.readAll()
  h.close()
  local fn, err = load(src, "users", "t", {})
  if not fn then return {} end
  local ok, t = pcall(fn)
  if not ok or type(t) ~= "table" then return {} end
  local names = {}
  for name, rec in pairs(t) do
    if validName(name) and type(rec) == "table"
       and type(rec.salt) == "string" and type(rec.hash) == "string" then
      table.insert(names, name)
    end
  end  table.sort(names)
  return names
end

local function readAll()
  if not fs.exists(PATH) then return {} end
  local h = fs.open(PATH, "r")
  if not h then return {} end
  local src = h.readAll()
  h.close()
  local fn, err = load(src, "users", "t", {})
  if not fn then return {} end
  local ok, t = pcall(fn)
  if not ok or type(t) ~= "table" then return {} end
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

local seeded = false
local function ensureSeed()
  -- Lua's math.random repeats the same sequence every boot unless
  -- seeded. Identical account-creation orders would then produce
  -- identical salts on every machine. Mix wall-clock, CPU clock,
  -- and computer ID; salts are stored anyway, this is about uniqueness.
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
  math.randomseed(s % 2147483647)
  math.random()
  math.random()
  math.random()
end

local function newSalt()
  -- 8 random bytes as hex; seeded caller-side where possible.
  local parts = {}  for _ = 1, 8 do
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

-- Creates (or overwrites) a user. Returns true, or false + err.
function Users.create(name, password)
  if not validName(name) then
    return false, "name 1-16 chars: letters, digits, _ -"
  end
  if type(password) ~= "string" or #password < 8 then
    return false, "password min 8 chars"
  end
  local sha = loadSHA()
  if not sha then return false, "sha256 missing" end
  ensureSeed()
  local salt = newSalt()
  local hash = stretch(sha, salt, password, ROUNDS)
  local t = readAll()
  t[name] = { salt = salt, hash = hash, rounds = ROUNDS }
  if not writeAll(t) then return false, "cannot write users file" end
  return true
end

function Users.verify(name, password)
  if not validName(name) or type(password) ~= "string" then
    return false
  end
  local sha = loadSHA()
  if not sha then return false end
  local t = readAll()
  local rec = t[name]
  if type(rec) ~= "table" then return false end
  local rounds = tonumber(rec.rounds) or 1 -- legacy single-round accounts
  if rounds < 1 then rounds = 1 end
  return stretch(sha, rec.salt, password, rounds) == rec.hash
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

return Users
