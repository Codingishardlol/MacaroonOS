-- Macaroon OS - window library
-- One Window = outer frame (incl. title bar) + content area for the app.
-- Compatible with CC: Tweaked (Lua 5.2 subset, no 5.4-only syntax).

local Window = {}
Window.__index = Window

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function Window.new(title, x, y, w, h, appDef)
  local self = setmetatable({}, Window)
  self.title = title or "Window"
  self.x = x or 2
  self.y = y or 2
  self.w = math.max(w or 20, 12)
  self.h = math.max(h or 8, 4)
  self.appDef = appDef
  self.focused = false
  local parent = term.current()
  self.handle = window.create(parent, self.x, self.y, self.w, self.h)
  return self
end

function Window:move(nx, ny, screenW, screenH)
  screenW = screenW or 51
  screenH = screenH or 19
  -- Keep title bar reachable: allow partial off-screen but not lost.
  self.x = clamp(nx, 1 - self.w + 6, screenW - 4)
  self.y = clamp(ny, 1, screenH - 2)
  self.handle.reposition(self.x, self.y, self.w, self.h)
end

function Window:contains(gx, gy)
  return gx >= self.x and gx < self.x + self.w
     and gy >= self.y and gy < self.y + self.h
end

function Window:isTitleBar(gx, gy)
  return gy == self.y and self:contains(gx, gy)
end

function Window:isCloseButton(gx, gy)
  if not self:isTitleBar(gx, gy) then return false end
  local lx = gx - self.x + 1
  -- " X" occupies last 2 cells of title bar
  return lx >= self.w - 1
end

function Window:toContentCoords(gx, gy)
  -- Returns nil if not inside content area (excludes title bar).
  if not self:contains(gx, gy) then return nil end
  local lx = gx - self.x + 1
  local ly = gy - self.y + 1
  if ly <= 1 then return nil end
  return lx, ly - 1
end

function Window:draw()
  local win = self.handle
  local titleBg = colours.blue
  local titleFg = colours.white
  if not self.focused then
    titleBg = colours.grey
    titleFg = colours.white
  end

  -- Title bar (row 1)
  win.setBackgroundColor(titleBg)
  win.setTextColor(titleFg)
  win.setCursorPos(1, 1)
  local bar = string.rep(" ", self.w)
  win.write(bar)
  win.setCursorPos(2, 1)
  local maxTitle = self.w - 6
  local t = self.title
  if #t > maxTitle then
    t = string.sub(t, 1, maxTitle - 1) .. "+"
  end
  win.write(t)

  -- Close button
  win.setCursorPos(self.w - 1, 1)
  if self.focused then
    win.setBackgroundColor(colours.red)
  else
    win.setBackgroundColor(colours.grey)
  end
  win.setTextColor(colours.white)
  win.write(" X")

  -- Body background
  win.setBackgroundColor(colours.white)
  win.setTextColor(colours.black)
  for row = 2, self.h do
    win.setCursorPos(1, row)
    win.write(string.rep(" ", self.w))
  end

  -- App content in a sub-window (excludes title bar)
  if self.appDef and self.appDef.draw then
    local content = window.create(win, 1, 2, self.w, self.h - 1)
    local prev = term.current()
    term.redirect(content)
    local ok, err = pcall(self.appDef.draw, content)
    term.redirect(prev)
    if not ok then
      term.redirect(content)
      content.setBackgroundColor(colours.white)
      content.setTextColor(colours.red)
      content.setCursorPos(2, 2)
      content.write("App error")
      content.setCursorPos(2, 3)
      local msg = tostring(err):sub(1, self.w - 3)
      content.write(msg)
      term.redirect(prev)
    end
    -- Restore outer handle as current (desktop draws sequentially anyway)
    self.handle.redraw()
  end
end

function Window:forwardEvent(event, p1, p2, p3)
  -- Forward content-area mouse events to the app with local coords.
  -- Returns true if app requested a redraw.
  if not self.appDef or not self.appDef.onEvent then
    return false
  end
  if event ~= "mouse_click" and event ~= "mouse_up" and event ~= "mouse_drag" and event ~= "mouse_scroll" then
    local ok, res = pcall(self.appDef.onEvent, self:contentWindow(), event, p1, p2, p3)
    if ok and res then return true end
    return false
  end
  -- Mouse events: p1=button, p2=gx, p3=gy
  local cx, cy = self:toContentCoords(p2, p3)
  if not cx then return false end
  local ok, res = pcall(self.appDef.onEvent, self:contentWindow(), event, p1, cx, cy)
  if ok and res then return true end
  return false
end

function Window:contentWindow()
  return window.create(self.handle, 1, 2, self.w, self.h - 1)
end

return Window
