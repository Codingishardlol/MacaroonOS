-- Macaroon OS - boot splash (Windows-style)
-- Fullscreen logo + version + status line + spinner.
-- All calls are cheap; the caller drives timing via status()/spinTick().

local Boot = {}

local frames = { "|", "/", "-", "\\" }
local frame = 1
local statusY = nil
local spinnerX = nil

-- Brown disc (c) with dark chips (f) on black (f). 12 wide x 6 tall.
local COOKIE = {
  "fffccccccfff",
  "ffccccccccff",
  "fcccfccfcccf",
  "fccfccccfccf",
  "ffcccfccccff",
  "fffccccccfff",
}
local COOKIE_W = 12

-- Redirect defensively like desktop.lua does.
local function nativeBase()
  local base = term.current()
  if term.native then
    local ok, native = pcall(term.native)
    if ok and native then
      base = native
    end
  end
  return base
end

local function getVersion()
  local ok, V = pcall(dofile, "macaroon/version.lua")
  if ok and type(V) == "table" and type(V.version) == "string" then
    return V.version
  end
  return "?.?.?"
end

local function centerX(w, s)
  return math.max(1, math.floor((w - string.len(s)) / 2) + 1)
end

local function drawSpinner()
  if not statusY or not spinnerX then
    return
  end
  term.setBackgroundColor(colours.black)
  term.setTextColor(colours.white)
  term.setCursorPos(spinnerX, statusY)
  term.write(frames[frame])
end

-- Redraws only the status row. Returns false if show() never ran.
local function drawStatus(msg)
  if not statusY or not spinnerX then
    return false
  end
  local w = term.getSize()
  msg = tostring(msg or "")
  term.setBackgroundColor(colours.black)
  term.setTextColor(colours.white)
  term.setCursorPos(1, statusY)
  term.write(string.rep(" ", w))
  local room = w - spinnerX - 1
  if room < 0 then
    room = 0
  end
  if string.len(msg) > room then
    msg = string.sub(msg, 1, room)
  end
  term.setCursorPos(spinnerX, statusY)
  term.write(frames[frame])
  term.write(" " .. msg)
  return true
end

local function showFn(opts)
  opts = opts or {}
  term.redirect(nativeBase())
  term.setBackgroundColor(colours.black)
  term.setTextColor(colours.white)
  term.clear()
  term.setCursorPos(1, 1)
  local w, h = term.getSize()
  local startY = math.floor(h / 2) - 5
  if startY < 1 then
    startY = 1
  end
  local cx = math.max(1, math.floor((w - COOKIE_W) / 2) + 1)
  for i, bg in ipairs(COOKIE) do
    local y = startY + i - 1
    if y >= 1 and y <= h then
      term.setCursorPos(cx, y)
      term.blit(string.rep(" ", COOKIE_W), string.rep("f", COOKIE_W), bg)
    end
  end
  local ver = opts.version
  if type(ver) ~= "string" then
    ver = getVersion()
  end
  local title = "macaroon OS"
  local vline = "v" .. ver
  local titleY = startY + 7
  local verY = startY + 8
  term.setBackgroundColor(colours.black)
  term.setTextColor(colours.white)
  if titleY >= 1 and titleY <= h then
    term.setCursorPos(centerX(w, title), titleY)
    term.write(title)
  end
  term.setTextColor(colours.grey)
  if verY >= 1 and verY <= h then
    term.setCursorPos(centerX(w, vline), verY)
    term.write(vline)
  end
  term.setTextColor(colours.white)
  statusY = startY + 10
  if statusY > h then
    statusY = h
  end
  if statusY < 1 then
    statusY = 1
  end
  spinnerX = math.max(1, math.floor(w / 2) - 14)
  frame = 1
  local first = opts.message
  if type(first) ~= "string" then
    first = "Starting..."
  end
  drawStatus(first)
end

local function spinTick()
  if not statusY then
    return
  end
  frame = frame + 1
  if frame > #frames then
    frame = 1
  end
  drawSpinner()
end

local function status(msg)
  if not drawStatus(msg) then
    print(tostring(msg or ""))
  end
end

local function hide()
  statusY = nil
  spinnerX = nil
  term.setBackgroundColor(colours.lightBlue)
  term.setTextColor(colours.white)
  term.clear()
  term.setCursorPos(1, 1)
end

-- show is a plain function (startup.lua gates on type() == "function").
local function show(opts)
  return showFn(opts)
end

Boot.show = show
Boot.spinTick = spinTick
Boot.status = status
Boot.hide = hide

return Boot
