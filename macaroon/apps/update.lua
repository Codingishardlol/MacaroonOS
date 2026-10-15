-- Macaroon OS - Update app (desktop GUI)
-- Shows local/remote versions, Check + Install buttons.
-- State lives in file-scope upvalues (fresh per window via dofile).

local status = "Press Check."
local detail = ""
local localVer = "?"
local remoteVer = "?"
local updateAvailable = false
local baseURL = nil
local busy = false
local channel = "stable"
local confirmSwitch = false

local function refreshChannel()
  if not fs.exists("macaroon/channel.lua") then
    channel = "stable"
    return
  end
  local okC, Ch = pcall(dofile, "macaroon/channel.lua")
  if okC and type(Ch) == "table" and type(Ch.get) == "function" then
    local okG, ch = pcall(Ch.get)
    if okG and (ch == "beta" or ch == "stable") then channel = ch end
  end
end
refreshChannel()

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
  confirmSwitch = false
  busy = true
  status = "Checking..."
  detail = ""
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
  if not ok then
    status = "CRASH"
    detail = tostring(info):sub(1, 26)
    busy = false
    return
  end
  if type(info) ~= "table" then
    status = "CRASH"
    detail = "bad check result"
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
    status = "Check failed"
    detail = tostring(info.err or "?"):sub(1, 26)
  end
  busy = false
end

local function doInstall()
  if busy or not updateAvailable then return end
  confirmSwitch = false
  busy = true
  status = "Installing..."
  local okU, Updater = pcall(dofile, "macaroon/updater.lua")
  if not okU or type(Updater) ~= "table" then
    status = "Updater load failed."
    busy = false
    return
  end
  local okC, ok, err = pcall(Updater.perform, baseURL)
  if not okC then
    status = "Install crashed"
    detail = tostring(ok):sub(1, 26)
    busy = false
    return
  end
  if ok then
    refreshLocals()
    updateAvailable = false
    status = "Done! Reboot soon."
    detail = ""
  else
    status = "Install failed"
    detail = tostring(err or "?"):sub(1, 26)
  end
  busy = false
end

local function channelLabel()
  if channel == "beta" then return "Beta" end
  return "Stable"
end

local function doSwitchChannel()
  if busy then return end
  busy = true
  local other = "stable"
  if channel ~= "beta" then other = "beta" end
  status = "Switching..."
  detail = ""
  local okU, Updater = pcall(dofile, "macaroon/updater.lua")
  if not okU or type(Updater) ~= "table" then
    status = "Updater load failed."
    busy = false
    confirmSwitch = false
    return
  end
  local okS, ok, err = pcall(Updater.switchChannel, other)
  if not okS then
    status = "Switch crashed"
    detail = tostring(ok):sub(1, 26)
  elseif ok then
    refreshLocals()
    refreshChannel()
    updateAvailable = false
    status = "Done! Reboot soon."
    detail = ""
  else
    status = "Switch failed"
    detail = tostring(err or "?"):sub(1, 26)
  end
  busy = false
  confirmSwitch = false
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
    win.setCursorPos(2, 4)
    win.setTextColor(colours.red)
    win.write(string.sub(tostring(detail), 1, 26))
    win.setTextColor(colours.black)

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

    -- Channel button row 7: first click arms, second click switches.
    win.setCursorPos(2, 7)
    if busy then
      win.setBackgroundColor(colours.grey)
    elseif confirmSwitch then
      win.setBackgroundColor(colours.orange)
    else
      win.setBackgroundColor(colours.blue)
    end
    win.setTextColor(colours.white)
    win.write(" [ Channel: " .. channelLabel() .. " ] ")

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
    if cy == 7 and cx >= 2 and cx <= 22 then
      if busy then return false end
      if not confirmSwitch then
        local other = "Beta"
        if channel == "beta" then other = "Stable" end
        confirmSwitch = true
        status = "Switch to " .. other .. "? Again!"
        detail = "Switching reinstalls files."
        return true
      end
      doSwitchChannel()
      return true
    end
    return false
  end
}
