-- Macaroon OS installer (LevelOS-style)
-- Run on a CC: Tweaked Advanced Computer with:
--   wget run <RAW-URL-TO-THIS-FILE>
-- Example once hosted on GitHub:
--   wget run https://raw.githubusercontent.com/Codingishardlol/MacaroonOS/main/installer.lua
--
-- What it does:
--   1. Downloads every OS file from BASE_URL to / on this computer
--   2. Backs up existing /startup.lua to /startup.bak (once)
--   3. Leaves /startup.lua in place so Macaroon OS auto-boots on reboot
-- Re-run any time to update.

local BASE_URL = "https://raw.githubusercontent.com/Codingishardlol/MacaroonOS/main"

-- Paths relative to both BASE_URL and the computer root.
-- NOTE: keep in sync with macaroon/manifest.lua. Data files
-- (users.dat, settings.dat, update_url.txt) are never listed,
-- so installs/updates never wipe accounts or settings.
local FILES = {
  "startup.lua",
  "update.lua",
  "macaroon/version.lua",
  "macaroon/manifest.lua",
  "macaroon/updater.lua",
  "macaroon/sha256.lua",
  "macaroon/settings.lua",
  "macaroon/users.lua",
  "macaroon/login.lua",
  "macaroon/boot.lua",
  "macaroon/crash.lua",
  "macaroon/window.lua",
  "macaroon/desktop.lua",
  "macaroon/apps/hello.lua",
  "macaroon/apps/about.lua",
  "macaroon/apps/update.lua",
  "macaroon/apps/users.lua",
  "macaroon/apps/store.lua",
  "macaroon/apps/files.lua",
  "macaroon/apps/settings.lua",
  "macaroon/apps/terminal.lua",
}

local function printErr(msg)
  if term.isColor and term.isColor() then
    term.setTextColor(colours.red)
  end
  print(msg)
  if term.isColor and term.isColor() then
    term.setTextColor(colours.white)
  end
end

-- 1. HTTP check
if not http then
  printErr("HTTP API disabled. Enable http in CC config.")
  return
end

-- Trim trailing slash so BASE_URL .. "/" .. path is always correct
if string.sub(BASE_URL, -1) == "/" then
  BASE_URL = string.sub(BASE_URL, 1, -2)
end
if string.find(BASE_URL, "YOURNAME") then
  print("Edit installer.lua and set BASE_URL to your repo.")
  print("Current: " .. BASE_URL)
  print("")
end

print("Macaroon OS installer")
print("Source: " .. BASE_URL)
print("")

-- 2. Backup existing startup (don't overwrite backup twice)
if fs.exists("startup.lua") and not fs.exists("startup.bak") then
  -- Only backup if it's NOT already ours (check for marker)
  local h = fs.open("startup.lua", "r")
  local head = h and h.readAll() or ""
  if h then h.close() end
  if not string.find(head, "Macaroon OS %- startup") then
    print("Backing up startup.lua -> startup.bak")
    fs.copy("startup.lua", "startup.bak")
  end
end

-- 3. Download each file (cache-busted: raw hosts serve stale
-- bodies for minutes after a push, which once caused back-to-back
-- patch releases to install as the previous version).
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
for _, path in ipairs(FILES) do
  local url = cacheBusted(BASE_URL .. "/" .. path)
  print("Getting " .. path .. " ...")
  local okGet, res, err = pcall(http.get, url)
  if not okGet then
    res, err = nil, "http error: " .. tostring(res)
  end
  if not res then
    printErr("FAILED " .. path .. ": " .. tostring(err or res))
    printErr("URL: " .. url)
    print("")
    print("Check BASE_URL and that files are at repo root.")
    print("(Upload CONTENTS of 'Macaroon OS' folder, not the folder itself.)")
    return
  end
  local data = res.readAll()
  res.close()
  if not data or #data == 0 then
    printErr("FAILED " .. path .. ": empty file")
    return
  end
  local dir = fs.getDir(path)
  if dir ~= "" and dir ~= "." and not fs.exists(dir) then
    fs.makeDir(dir)
  end
  local out = fs.open(path, "w")
  if not out then
    printErr("FAILED " .. path .. ": cannot write")
    return
  end
  out.write(data)
  out.close()
end

print("")
print("Installed Macaroon OS to /")
print("startup.lua will auto-boot on reboot.")
-- Remember source so the updater can check later without retyping the URL.
do
  local dir = fs.getDir("macaroon/update_url.txt")
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
  local h = fs.open("macaroon/update_url.txt", "w")
  if h then
    h.write(BASE_URL)
    h.close()
    print("Update source saved.")
  end
end

-- Settings defaults (never overwrite existing).
if not fs.exists("macaroon/settings.dat") and fs.exists("macaroon/settings.lua") then
  local okS, Settings = pcall(dofile, "macaroon/settings.lua")
  if okS and Settings then
    pcall(Settings.save, nil)
  end
end

-- Account creation (proper install). Existing accounts are kept.
if fs.exists("macaroon/users.lua") then
  local okU, UserLib = pcall(dofile, "macaroon/users.lua")
  if okU and UserLib then
    pcall(math.randomseed, (os.epoch and os.epoch("utc") or os.time() * 1000)
      + (os.getComputerID and os.getComputerID() or 0))
    local names = UserLib.list()
    if #names > 0 then
      print("Accounts kept: " .. table.concat(names, ", "))
    else
      print("")
      print("Create admin account:")
      write("Username: ")
      local name = read()
      name = string.gsub(name or "", "^%s*(.-)%s*$", "%1")
      write("Password (min 8): ")
      local pw1 = read("*")
      write("Repeat password: ")
      local pw2 = read("*")
      if (pw1 or "") ~= (pw2 or "") then
        print("Passwords differ - no account created.")
        print("Run installer again or add one later.")
      else
        local okC, err = UserLib.create(name, pw1 or "")
        if okC then
          print("Account '" .. name .. "' created.")
        else
          print("Account failed: " .. tostring(err))
        end
      end
    end
  end
end
print("")
write("Reboot now? [Y/n] ")
local ans = read()
if not ans or string.lower(string.sub(ans, 1, 1)) ~= "n" then
  print("Rebooting...")
  sleep(0.5)
  os.reboot()
else
  print("Type 'reboot' or run 'startup' to start.")
end
