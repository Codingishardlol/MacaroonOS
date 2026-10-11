-- Macaroon OS - Update app (desktop GUI)
-- Shows local/remote versions, Check + Install buttons.
-- State lives in file-scope upvalues (fresh per window via dofile).

local status = "Press Check."
local localVer = "?"
local remoteVer = "?"
local updateAvailable = false
local baseURL = nil
local busy = false

local function refreshLocals()
  if fs.exists("macaroon/version.lua") then
    local ok, info = pcall(dofile, "macaroon/version.lua")
    if ok and type(info) == "table" and info.version then
      localVer = info.version
    end
  end
end
refreshLocals()

local function doCheck()
  if busy then return end
  busy = true
  status = "Checking..."
  if not fs.exists("macaroon/updater.lua") then
    status = "Updater missing."
    busy = false
    return
  end
  local okU, Updater = pcall(dofile, "macaroon/updater.lua")
  if not okU or type(Updater) ~= "table" then
    status = "Updater load failed."
    busy = false
    return
  end
  local ok, info = pcall(Updater.check)
  if not ok or type(info) ~= "table" then
    status = "Check crashed."
    busy = false
    return
  end
  localVer = tostring(info.localVer or localVer)
  baseURL = info.baseURL
  if info.remoteVer then
    remoteVer = tostring(info.remoteVer)
    updateAvailable = info.updateAvailable and true or false
    if updateAvailable then
      status = "Update ready!"
    else
      status = "Up to date."
    end
  else
    remoteVer = "?"
    updateAvailable = false
    status = "Check failed: " .. tostring(info.err or "?"):sub(1, 18)
  end
  busy = false
end

local function doInstall()
  if busy or not updateAvailable then return end
  busy = true
  status = "Installing..."
  local okU, Updater = pcall(dofile, "macaroon/updater.lua")
  if not okU or type(Updater) ~= "table" then
    status = "Updater load failed."
    busy = false
    return
  end
  local ok, err = Updater.perform(baseURL)
  if ok then
    refreshLocals()
    updateAvailable = false
    status = "Done! Reboot soon."
  else
    status = "Failed: " .. tostring(err or "?"):sub(1, 18)
  end
  busy = false
end

return {
  title = "Update",
  width = 30,
  height = 11,

  draw = function(win)
    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.black)
    win.clear()
    win.setCursorPos(2, 1)
    win.write("Local:  " .. tostring(localVer))
    win.setCursorPos(2, 2)
    win.write("Remote: " .. tostring(remoteVer))
    win.setCursorPos(2, 3)
    if updateAvailable then
      win.setTextColor(colours.green)
    else
      win.setTextColor(colours.grey)
    end
    win.write(tostring(status))

    -- Check button row 5
    win.setCursorPos(2, 5)
    if busy then
      win.setBackgroundColor(colours.grey)
    else
      win.setBackgroundColor(colours.blue)
    end
    win.setTextColor(colours.white)
    win.write(" [ Check ] ")

    -- Install button row 6 (only highlighted when update available)
    win.setCursorPos(2, 6)
    if updateAvailable and not busy then
      win.setBackgroundColor(colours.green)
      win.setTextColor(colours.white)
    else
      win.setBackgroundColor(colours.grey)
      win.setTextColor(colours.white)
    end
    win.write(" [ Install ] ")

    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.grey)
    win.setCursorPos(2, 8)
    win.write("Reboot after install")
    win.setCursorPos(2, 9)
    win.write("to finish update.")
  end,

  onEvent = function(win, event, p1, cx, cy)
    if event ~= "mouse_click" or not cx or not cy then
      return false
    end
    -- Buttons occupy cols 2..12 on rows 5 and 6
    if cy == 5 and cx >= 2 and cx <= 12 then
      doCheck()
      return true
    end
    if cy == 6 and cx >= 2 and cx <= 12 then
      doInstall()
      return true
    end
    return false
  end
}
