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
  { name = "Hello", path = "macaroon/apps/hello.lua" },
  { name = "About", path = "macaroon/apps/about.lua" },
  { name = "Update", path = "macaroon/apps/update.lua" },
}

-- Filter out missing apps so one bad file can't break boot
local validApps = {}
for _, app in ipairs(apps) do
  if fs.exists(app.path) then
    table.insert(validApps, app)
  end
end

term.setBackgroundColor(colours.lightBlue)
term.clear()

-- Boot-time update check (skip if macaroon/noautoupdate.txt exists).
-- Never blocks boot on failure; only prompts when an update is found.
do
  local function bootCheck()
    if fs.exists("macaroon/noautoupdate.txt") then return end
    if not fs.exists("macaroon/updater.lua") then return end
    if not http then return end
    local okU, Updater = pcall(dofile, "macaroon/updater.lua")
    if not okU or type(Updater) ~= "table" then return end
    print("Checking for updates...")
    local ok, info = pcall(Updater.check)
    if not ok or type(info) ~= "table" then return end
    if not info.updateAvailable then
      print("Macaroon OS v" .. tostring(info.localVer) .. " (up to date)")
      return
    end
    print("Update available: " .. tostring(info.localVer) .. " -> " .. tostring(info.remoteVer))
    write("Update now? [Y/n] ")
    local ans = read()
    if ans and string.lower(string.sub(ans, 1, 1)) == "n" then
      print("Skipped. Open Update app later to install.")
      sleep(0.5)
      return
    end
    print("Updating...")
    local okP, err = Updater.perform(info.baseURL, function(path, i, total)
      print("[" .. i .. "/" .. total .. "] " .. path)
    end)
    if not okP then
      print("Update failed: " .. tostring(err))
      print("Continuing boot in 2s...")
      sleep(2)
      return
    end
    print("Updated. Rebooting...")
    sleep(1)
    os.reboot()
  end
  pcall(bootCheck)
  term.setBackgroundColor(colours.lightBlue)
  term.clear()
end

local ok, err = pcall(Desktop.run, Window, validApps)
if not ok then
  fail(tostring(err))
end
