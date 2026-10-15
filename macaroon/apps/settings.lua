-- Macaroon OS - Settings app
-- Wallpaper color, 12/24h clock, auto-update toggle.
-- Writes via macaroon/settings.lua; desktop picks it up live.

local status = "loaded"
local wp = 8
local clock24 = true
local autoupdate = true
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

local COLORS = {
  { name = "black",     value = 32768 },
  { name = "blue",      value = 2048 },
  { name = "purple",    value = 1024 },
  { name = "lightBlue", value = 8 },
  { name = "cyan",      value = 512 },
  { name = "grey",      value = 128 },
}

local function reload()
  if not fs.exists("macaroon/settings.lua") then
    status = "settings lib missing"
    return
  end
  local ok, S = pcall(dofile, "macaroon/settings.lua")
  if not ok or type(S) ~= "table" then
    status = "settings load failed"
    return
  end
  local s = S.load()
  wp = s.wallpaper
  clock24 = s.clock24
  autoupdate = s.autoupdate
  status = "loaded"
  refreshChannel()
end
reload()

local function persist()
  local ok, S = pcall(dofile, "macaroon/settings.lua")
  if not ok or type(S) ~= "table" then
    status = "settings load failed"
    return
  end
  if S.save({ wallpaper = wp, clock24 = clock24, autoupdate = autoupdate }) then
    status = "saved!"
  else
    status = "save failed"
  end
end

local function wpName()
  for _, c in ipairs(COLORS) do
    if c.value == wp then return c.name end
  end
  return tostring(wp)
end

local function channelShown()
  if channel == "beta" then return "Beta" end
  return "Stable"
end

local function doSwitchChannel()
  local other = "stable"
  if channel ~= "beta" then other = "beta" end
  local okU, Updater = pcall(dofile, "macaroon/updater.lua")
  if not okU or type(Updater) ~= "table" or type(Updater.switchChannel) ~= "function" then
    status = "switch unavailable"
    confirmSwitch = false
    return
  end
  local okS, ok, err = pcall(Updater.switchChannel, other)
  if not okS then
    status = "switch crashed"
  elseif ok then
    refreshChannel()
    status = "now on " .. channel .. "! reboot"
  else
    status = "switch failed"
  end
  confirmSwitch = false
end

return {
  title = "Settings",
  width = 30,
  height = 14,

  draw = function(win)
    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.black)
    win.clear()
    win.setCursorPos(2, 1)
    win.write("Wallpaper: " .. wpName())
    win.setCursorPos(2, 2)
    win.setBackgroundColor(colours.grey)
    win.setTextColor(colours.white)
    win.write(" < change > ")
    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.black)
    win.setCursorPos(2, 4)
    win.write("Clock: " .. (clock24 and "24h" or "12h"))
    win.setCursorPos(2, 5)
    win.setBackgroundColor(colours.grey)
    win.setTextColor(colours.white)
    win.write(" < toggle > ")
    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.black)
    win.setCursorPos(2, 7)
    win.write("AutoUpdate: " .. (autoupdate and "ON" or "OFF"))
    win.setCursorPos(2, 8)
    win.setBackgroundColor(colours.grey)
    win.setTextColor(colours.white)
    win.write(" < toggle > ")
    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.grey)
    win.setCursorPos(2, 10)
    win.write(tostring(status))
    win.setCursorPos(2, 11)
    win.write("saves instantly")
    win.setCursorPos(2, 12)
    win.write("Channel: " .. channelShown())
    win.setCursorPos(2, 13)
    win.setBackgroundColor(colours.grey)
    win.setTextColor(colours.white)
    win.write(" < switch > ")
    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.grey)
  end,

  onEvent = function(win, event, p1, cx, cy)
    if event ~= "mouse_click" or not cx or not cy then
      return false
    end
    local function inBtn(y)
      return cy == y and cx >= 2 and cx <= 13
    end
    if inBtn(2) then
      confirmSwitch = false
      local idx = 1
      for i, c in ipairs(COLORS) do
        if c.value == wp then idx = i break end
      end
      idx = idx % #COLORS + 1
      wp = COLORS[idx].value
      persist()
      return true
    elseif inBtn(5) then
      confirmSwitch = false
      clock24 = not clock24
      persist()
      return true
    elseif inBtn(8) then
      autoupdate = not autoupdate
      persist()
      confirmSwitch = false
      return true
    elseif inBtn(13) then
      if not confirmSwitch then
        local other = "Stable"
        if channel ~= "beta" then other = "Beta" end
        confirmSwitch = true
        status = "Switch to " .. other .. "? again!"
        return true
      end
      status = "switching: reinstalls files"
      doSwitchChannel()
      return true
    end
    confirmSwitch = false
    return false
  end
}
