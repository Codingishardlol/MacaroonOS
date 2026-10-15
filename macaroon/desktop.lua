-- Macaroon OS - desktop environment
-- Owns the event loop, wallpaper, taskbar, start menu, window z-order.
-- Usage: local Desktop = dofile("macaroon/desktop.lua"); Desktop.run(Window, apps)

local Desktop = {}

function Desktop.run(Window, apps, opts)
  apps = apps or {}
  opts = opts or {}
  local sessionUser = opts.user -- may be nil (no accounts)
  -- Live settings (reloaded every draw so the Settings app applies instantly).
  local wallpaper = colours.lightBlue
  local clock24 = true
  local function loadSettings()
    if not fs.exists("macaroon/settings.lua") then return end
    local ok, S = pcall(dofile, "macaroon/settings.lua")
    if not ok or type(S) ~= "table" then return end
    local ok2, s = pcall(S.load)
    if not ok2 or type(s) ~= "table" then return end
    if type(s.wallpaper) == "number" then wallpaper = s.wallpaper end
    if type(s.clock24) == "boolean" then clock24 = s.clock24 end
  end
  loadSettings()
  local base = term.current()
  if term.native then
    local ok, native = pcall(term.native)
    if ok and native then base = native end
  end
  term.redirect(base)

  local screenW, screenH = term.getSize()
  local windows = {}
  local startOpen = false
  local dragging = nil
  local dragOffX, dragOffY = 0, 0
  local clockTimer = os.startTimer(1)
  local clockText = "--:--"

  local function updateClock()
    local ok, t = pcall(textutils.formatTime, os.time(), clock24 ~= false)
    if ok and type(t) == "string" then
      clockText = t
    else
      clockText = tostring(os.time())
    end
  end
  updateClock()

  local function focusWindow(win)
    for i, w in ipairs(windows) do
      w.focused = false
      if w == win then
        table.remove(windows, i)
        break
      end
    end
    win.focused = true
    table.insert(windows, win)
  end

  local function openApp(appEntry)
    local ok, appDef = pcall(dofile, appEntry.path)
    if not ok or type(appDef) ~= "table" then
      return false
    end
    local title = appDef.title or appEntry.name or "App"
    local w = math.min(appDef.width or 30, screenW - 2)
    local h = math.min(appDef.height or 10, screenH - 3)
    if w < 12 then w = 12 end
    if h < 4 then h = 4 end
    -- Cascade new windows so they don't stack exactly.
    local n = #windows
    local x = math.max(2, math.floor((screenW - w) / 2) + (n % 4) - 2)
    local y = math.max(2, math.floor((screenH - h) / 2) - 1 + (n % 3))
    local win = Window.new(title, x, y, w, h, appDef)
    focusWindow(win)
    return true
  end

  local function closeWindow(win)
    for i, w in ipairs(windows) do
      if w == win then
        table.remove(windows, i)
        break
      end
    end
    if #windows > 0 then
      windows[#windows].focused = true
    end
  end

  -- Close guard: an app may veto closing (e.g. unsaved work) by
  -- providing canClose() -> false. On veto, the app gets a single
  -- "close_request" event so it can explain itself (status line);
  -- a second close attempt while still vetoed... the app decides:
  -- canClose is consulted on EVERY attempt, so arm-and-confirm
  -- (first veto arms, second allows) works. No canClose = closable.
  local function closeBlocked(win)
    if win.appDef and win.appDef.canClose then
      local okC, allow = pcall(win.appDef.canClose)
      if okC and allow == false then
        if win.appDef.onEvent then
          pcall(win.appDef.onEvent, win:contentWindow(), "close_request")
        end
        return true
      end
    end
    return false
  end

  local function drawWallpaper()
    term.setBackgroundColor(wallpaper)
    term.setTextColor(colours.white)
    term.clear()
    term.setCursorPos(1, 1)
    -- Simple centered logo
    local logo1 = "macaroon"
    local logo2 = "OS v1"
    if sessionUser then
      logo2 = sessionUser .. " - OS"
    end
    local x1 = math.max(1, math.floor((screenW - #logo1) / 2) + 1)
    local x2 = math.max(1, math.floor((screenW - #logo2) / 2) + 1)
    local yMid = math.floor(screenH / 2) - 1
    if yMid >= 1 and yMid + 1 < screenH then
      term.setCursorPos(x1, yMid)
      term.write(logo1)
      term.setCursorPos(x2, yMid + 1)
      term.write(logo2)
    end
  end

  local function drawWindows()
    for _, win in ipairs(windows) do
      -- Re-anchor handle in case terminal was redirected
      win.handle.reposition(win.x, win.y, win.w, win.h)
      win:draw()
    end
    term.redirect(base)
  end

  local function drawTaskbar()
    local barY = screenH
    term.setBackgroundColor(colours.grey)
    term.setTextColor(colours.white)
    term.setCursorPos(1, barY)
    term.write(string.rep(" ", screenW))

    -- Start button
    local label = " Macaroon "
    term.setCursorPos(1, barY)
    if startOpen then
      term.setBackgroundColor(colours.lime)
      term.setTextColor(colours.black)
    else
      term.setBackgroundColor(colours.green)
      term.setTextColor(colours.white)
    end
    term.write(label)

    -- Clock + user (right)
    term.setBackgroundColor(colours.grey)
    term.setTextColor(colours.white)
    local c = " " .. clockText .. " "
    if sessionUser then
      c = " " .. tostring(sessionUser) .. " " .. clockText .. " "
      if #c > screenW - #label - 1 then
        c = " " .. clockText .. " " -- narrow screen: clock only
      end
    end
    term.setCursorPos(math.max(#label + 1, screenW - #c + 1), barY)
    term.write(c)
  end

  local function drawStartMenu()
    if not startOpen then return end
    -- Menu above taskbar, left side
    local menuW = 16
    local menuH = #apps + 4 -- title + apps + lock + shutdown + padding
    local menuX = 1
    local menuY = screenH - menuH
    if menuY < 1 then menuY = 1 end

    local m = window.create(base, menuX, menuY, menuW, menuH)
    m.setBackgroundColor(colours.white)
    m.setTextColor(colours.black)
    m.clear()
    -- Border title
    m.setBackgroundColor(colours.blue)
    m.setTextColor(colours.white)
    m.setCursorPos(1, 1)
    m.write(string.rep(" ", menuW))
    m.setCursorPos(2, 1)
    m.write("Macaroon")

    for i, app in ipairs(apps) do
      m.setBackgroundColor(colours.white)
      m.setTextColor(colours.black)
      m.setCursorPos(2, 1 + i)
      local name = app.name or ("App " .. i)
      if #name > menuW - 3 then
        name = string.sub(name, 1, menuW - 4) .. "+"
      end
      m.write(name)
    end
    -- Lock row
    m.setBackgroundColor(colours.white)
    m.setTextColor(colours.orange)
    m.setCursorPos(2, menuH - 2)
    m.write("Lock")
    -- Shutdown row
    m.setBackgroundColor(colours.white)
    m.setTextColor(colours.red)
    m.setCursorPos(2, menuH - 1)
    m.write("Shutdown")
    term.redirect(base)
  end

  local function drawAll()
    pcall(loadSettings)
    term.redirect(base)
    screenW, screenH = term.getSize()
    drawWallpaper()
    drawWindows()
    drawStartMenu()
    drawTaskbar()
    term.setCursorPos(screenW, screenH)
  end

  local function startMenuHit(gx, gy)
    if not startOpen then return nil end
    local menuW = 16
    local menuH = #apps + 4
    local menuX = 1
    local menuY = screenH - menuH
    if menuY < 1 then menuY = 1 end
    if gx < menuX or gx >= menuX + menuW then return nil end
    if gy < menuY or gy >= menuY + menuH then return nil end
    local row = gy - menuY + 1
    if row == 1 then return "title" end
    if row >= 2 and row <= 1 + #apps then
      return apps[row - 1]
    end
    if row == menuH - 2 then return "lock" end
    if row == menuH - 1 then return "shutdown" end
    return "title"
  end

  drawAll()

  while true do
    -- pullEventRaw: Ctrl+T ("terminate") must NOT drop a locked machine
    -- to shell, so it is swallowed here. Shutdown/Reboot menu items
    -- remain the way out.
    local event, p1, p2, p3 = os.pullEventRaw()
    if event == "terminate" then
      drawAll()
    elseif event == "timer" and p1 == clockTimer then
      updateClock()
      clockTimer = os.startTimer(1)
      drawAll()
    elseif event == "term_resize" then
      screenW, screenH = term.getSize()
      drawAll()
    elseif event == "mouse_click" and p1 == 1 then
      local gx, gy = p2, p3
      local barY = screenH

      -- 1. Start button
      if gy == barY and gx <= #" Macaroon " then
        startOpen = not startOpen
        drawAll()
      -- 2. Start menu click
      elseif startOpen and startMenuHit(gx, gy) ~= nil then
        local hit = startMenuHit(gx, gy)
        if hit == "shutdown" then
          os.shutdown()
        elseif hit == "lock" then
          os.reboot() -- reboot returns to the login gate
        elseif type(hit) == "table" then
          startOpen = false
          openApp(hit)
          drawAll()
        else
          drawAll()
        end
      else
        -- 3. Windows (top-most first)
        local consumed = false
        for i = #windows, 1, -1 do
          local win = windows[i]
          if win:contains(gx, gy) then
            focusWindow(win)
            if win:isCloseButton(gx, gy) then
              if not closeBlocked(win) then closeWindow(win) end
            elseif win:isTitleBar(gx, gy) then
              dragging = win
              dragOffX = gx - win.x
              dragOffY = gy - win.y
            else
              if win:forwardEvent(event, p1, p2, p3) then
                -- app requested redraw, handled by drawAll below
              end
            end
            consumed = true
            break
          end
        end
        if not consumed and startOpen then
          -- Clicked desktop: close start menu
          startOpen = false
        end
        drawAll()
      end
    elseif event == "mouse_drag" and dragging then
      dragging:move(p2 - dragOffX, p3 - dragOffY, screenW, screenH)
      drawAll()
    elseif event == "mouse_up" then
      if dragging then
        dragging = nil
        drawAll()
      end
    elseif event == "mouse_scroll" then
      -- Forward scroll to focused window content if hovered
      local gx, gy = p2, p3
      for i = #windows, 1, -1 do
        local win = windows[i]
        if win:contains(gx, gy) then
          if win:forwardEvent(event, p1, p2, p3) then
            drawAll()
          end
          break
        end
      end
    elseif event == "key" then
      -- F1 toggles start menu, Delete closes focused window
      if p1 == 59 then -- F1
        startOpen = not startOpen
        drawAll()
      elseif p1 == 211 and #windows > 0 then -- Delete
        if not closeBlocked(windows[#windows]) then
          closeWindow(windows[#windows])
        end
        drawAll()
      elseif #windows > 0 then
        -- Forward keys to focused window's app
        local win = windows[#windows]
        local ok, res = pcall(win.appDef.onEvent or function() end,
          win:contentWindow(), event, p1)
        if ok and res then drawAll() end
      end
    elseif event == "char" then
      if #windows > 0 then
        local win = windows[#windows]
        if win.appDef and win.appDef.onEvent then
          local ok, res = pcall(win.appDef.onEvent,
            win:contentWindow(), event, p1)
          if ok and res then drawAll() end
        end
      end
    end
  end
end

return Desktop
