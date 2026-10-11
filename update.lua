-- Macaroon OS update program (shell)
-- Manual use: type `update` (runs /update.lua via shell path).
-- Tip: while the desktop is running, press Ctrl+T to drop to shell, then run `update`.

local function printErr(msg)
  if term.isColor and term.isColor() then
    term.setTextColor(colours.red)
  end
  print(msg)
  if term.isColor and term.isColor() then
    term.setTextColor(colours.white)
  end
end

if not fs.exists("macaroon/updater.lua") then
  printErr("Updater missing: macaroon/updater.lua not found.")
  print("Re-install with: wget run <URL-TO-installer.lua>")
  return
end

local okU, Updater = pcall(dofile, "macaroon/updater.lua")
if not okU or type(Updater) ~= "table" then
  printErr("Updater load failed: " .. tostring(Updater))
  return
end

print("Macaroon OS update check...")
local okCall, info = pcall(Updater.check)
if not okCall or type(info) ~= "table" then
  printErr("Check crashed: " .. tostring(info))
  return
end

print("Local:  " .. tostring(info.localVer))
if info.err and not info.remoteVer then
  printErr("Remote: unknown (" .. tostring(info.err) .. ")")
  print("Source: " .. tostring(info.baseURL))
  return
end
print("Remote: " .. tostring(info.remoteVer))

if not info.updateAvailable then
  print("Already up to date.")
  return
end

print("")
write("Update " .. tostring(info.localVer) .. " -> " .. tostring(info.remoteVer) .. "? [Y/n] ")
local ans = read()
if ans and string.lower(string.sub(ans, 1, 1)) == "n" then
  print("Cancelled.")
  return
end

print("Updating...")
local okCall, okP, err = pcall(Updater.perform, info.baseURL, function(path, i, total)
  print("[" .. i .. "/" .. total .. "] " .. path)
end)
if not okCall then
  printErr("Update crashed: " .. tostring(okP))
  return
end
if not okP then
  printErr("Update failed: " .. tostring(err))
  return
end

print("")
print("Updated to " .. tostring(info.remoteVer) .. ".")
write("Reboot now? [Y/n] ")
local ans2 = read()
if not ans2 or string.lower(string.sub(ans2, 1, 1)) ~= "n" then
  os.reboot()
end
