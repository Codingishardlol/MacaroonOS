-- Macaroon OS - startup (auto-run on boot)
-- Expects files at /startup.lua and /macaroon/...

local function fail(msg)
  term.setBackgroundColor(colours.black)
  term.setTextColor(colours.red)
  term.clear()
  term.setCursorPos(1, 1)
  print("Macaroon OS boot failed:")
  print(msg)
end

-- Advanced (colour + mouse) required for v1 desktop
if not term.isColor or not term.isColor() then
  fail("Advanced Computer required (colour).")
  return
end

-- Boot splash module (optional; boot continues plainly if missing).
local okBoot, BootMod = pcall(dofile, "macaroon/boot.lua")
local Boot = nil
if okBoot and type(BootMod) == "table" then
  Boot = BootMod
end

-- Animated wait: advances the splash spinner instead of a dead sleep.
-- Falls back to plain sleep when the splash is unavailable.
local function bootSpinSleep(n)
  if not Boot or type(Boot.spinTick) ~= "function" then
    sleep(n)
    return
  end
  local steps = math.floor(n / 0.1 + 0.5)
  if steps < 1 and n > 0 then
    steps = 1
  end
  for i = 1, steps do
    sleep(0.1)
    pcall(Boot.spinTick)
  end
end

-- Progress line: splash status row when available, else console print.
local function bootSay(msg)
  if Boot and type(Boot.status) == "function" then
    if pcall(Boot.status, msg) then
      return
    end
  end
  print(msg)
end

if not fs.exists("macaroon/window.lua") or not fs.exists("macaroon/desktop.lua") then
  fail("Missing /macaroon/window.lua or /macaroon/desktop.lua")
  return
end

local okW, Window = pcall(dofile, "macaroon/window.lua")
if not okW or type(Window) ~= "table" then
  fail("window.lua load error: " .. tostring(Window))
  return
end

local okD, Desktop = pcall(dofile, "macaroon/desktop.lua")
if not okD or type(Desktop) ~= "table" or type(Desktop.run) ~= "function" then
  fail("desktop.lua load error: " .. tostring(Desktop))
  return
end

local apps = {
  { name = "Files", path = "macaroon/apps/files.lua" },
  { name = "Terminal", path = "macaroon/apps/terminal.lua" },
  { name = "Settings", path = "macaroon/apps/settings.lua" },
  { name = "Hello", path = "macaroon/apps/hello.lua" },
  { name = "About", path = "macaroon/apps/about.lua" },
  { name = "Update", path = "macaroon/apps/update.lua" },
  { name = "Users", path = "macaroon/apps/users.lua" },
  { name = "Store", path = "macaroon/apps/store.lua" },
}

-- Filter out missing apps so one bad file can't break boot
local validApps = {}
for _, app in ipairs(apps) do
  if fs.exists(app.path) then
    table.insert(validApps, app)
  end
end

-- Boot splash (Windows-style) with ~2s of spinner animation.
-- Wrapped in pcall: Ctrl+T during the splash must fall through to the
-- update check and login gate below, never abort startup into a shell.
pcall(function()
  if Boot and type(Boot.show) == "function" then
    pcall(Boot.show)
    bootSay("Starting macaroon OS...")
    bootSpinSleep(2)
  else
    term.setBackgroundColor(colours.lightBlue)
    term.clear()
  end
end)

-- Boot-time update check (skip if macaroon/noautoupdate.txt exists).
-- Never blocks boot on failure; only prompts when an update is found.
do
  local function bootCheck()
    if fs.exists("macaroon/noautoupdate.txt") then return end
    if not fs.exists("macaroon/updater.lua") then return end
    if not http then return end
    local okU, Updater = pcall(dofile, "macaroon/updater.lua")
    if not okU or type(Updater) ~= "table" then return end
    bootSay("Checking for updates...")
    local ok, info = pcall(Updater.check)
    if not ok then
      bootSay("Update check crashed: " .. tostring(info))
      bootSay("Continuing boot in 3s...")
      bootSpinSleep(3)
      return
    end
    if type(info) ~= "table" then
      bootSay("Update check broken. Continuing in 3s...")
      bootSpinSleep(3)
      return
    end
    if info.err and not info.remoteVer then
      bootSay("Update check failed: " .. tostring(info.err))
      bootSay("Continuing boot in 3s...")
      bootSpinSleep(3)
      return
    end
    if not info.updateAvailable then
      bootSay("Macaroon OS v" .. tostring(info.localVer) .. " (up to date)")
      bootSpinSleep(1)
      return
    end
    bootSay("Update available: " .. tostring(info.localVer) .. " -> " .. tostring(info.remoteVer))
    write("Update now? [Y/n] ")
    local ans = read()
    if ans and string.lower(string.sub(ans, 1, 1)) == "n" then
      bootSay("Skipped. Open Update app later to install.")
      bootSpinSleep(0.5)
      return
    end
    bootSay("Updating...")
    local okCall, okP, perr = pcall(Updater.perform, info.baseURL, function(path, i, total)
      bootSay("[" .. i .. "/" .. total .. "] " .. path)
    end)
    if not okCall then
      bootSay("Update crashed: " .. tostring(okP))
      bootSay("Continuing boot in 3s...")
      bootSpinSleep(3)
      return
    end
    if not okP then
      bootSay("Update failed: " .. tostring(perr))
      bootSay("Continuing boot in 3s...")
      bootSpinSleep(3)
      return
    end
    bootSay("Updated. Rebooting...")
    bootSpinSleep(1)
    os.reboot()
  end
  pcall(bootCheck)
  if not Boot then
    term.setBackgroundColor(colours.lightBlue)
    term.clear()
  end
  -- Splash stays up through login when present; login draws its own screen.
end

-- Secure boot: login gate. Skipped when no accounts exist
-- (fresh manual copy), so the OS still boots out of the box.
local sessionUser = nil
do
  local function bootLogin()
    if not fs.exists("macaroon/login.lua") then return end
    local hasAccts = false
    if fs.exists("macaroon/users.lua") then
      local okU, UL = pcall(dofile, "macaroon/users.lua")
      if okU and UL and UL.hasAccounts then
        local okH, has = pcall(UL.hasAccounts)
        hasAccts = okH and has
      end
    end
    if not hasAccts then return end
    local okL, Login = pcall(dofile, "macaroon/login.lua")
    if not okL or type(Login) ~= "table" then return end
    local who, reason = Login.run()
    if who then
      sessionUser = who
      return
    end
    if reason == "shutdown" then
      os.shutdown()
      return
    end
    print("Too many attempts. Shutting down.")
    sleep(1)
    os.shutdown()
  end
  pcall(bootLogin)
  -- Terminate-trap: Ctrl+T during login throws through read(), and the
  -- pcall above swallows it. Never continue to desktop unauthenticated
  -- when accounts exist.
  if sessionUser == nil then
    local locked = false
    if fs.exists("macaroon/users.lua") then
      local okU, UL = pcall(dofile, "macaroon/users.lua")
      if okU and UL and UL.hasAccounts then
        local okH, has = pcall(UL.hasAccounts)
        locked = okH and has
      end
    end
    if locked then
      term.setBackgroundColor(colours.black)
      term.setTextColor(colours.red)
      term.clear()
      term.setCursorPos(1, 1)
      print("Login required. Shutting down.")
      pcall(sleep, 1) -- mash-proof: terminate here must not escape to shell
      os.shutdown()
      return
    end
  end
end

-- Hide splash (restore lightBlue clear) right before the desktop.
if Boot and type(Boot.hide) == "function" then
  pcall(Boot.hide)
else
  term.setBackgroundColor(colours.lightBlue)
  term.clear()
end

local ok, err = pcall(Desktop.run, Window, validApps, { user = sessionUser })
if not ok then
  fail(tostring(err))
end
