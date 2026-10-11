-- Macaroon OS - Settings app
-- Wallpaper color, 12/24h clock, auto-update toggle.
-- Writes via macaroon/settings.lua; desktop picks it up live.

local status = "loaded"
local wp = 8
local clock24 = true
local autoupdate = true

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

return {
  title = "Settings",
  width = 30,
  height = 12,

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
  end,

  onEvent = function(win, event, p1, cx, cy)
    if event ~= "mouse_click" or not cx or not cy then
      return false
    end
    local function inBtn(y)
      return cy == y and cx >= 2 and cx <= 13
    end
    if inBtn(2) then
      local idx = 1
      for i, c in ipairs(COLORS) do
        if c.value == wp then idx = i break end
      end
      idx = idx % #COLORS + 1
      wp = COLORS[idx].value
      persist()
      return true
    elseif inBtn(5) then
      clock24 = not clock24
      persist()
      return true
    elseif inBtn(8) then
      autoupdate = not autoupdate
      persist()
      return true
    end
    return false
  end
}
