-- Macaroon OS - graphical login screen (secure boot gate)
-- Windows-style: wallpaper background, user tiles, password box,
-- Welcome spinner on success. Fullscreen term UI, no desktop needed.
-- Returns username on success, or nil + reason ("shutdown", "locked",
-- "no accounts", ...). Ignores terminate so Ctrl+T can't escape it;
-- startup's trap remains the backstop for any other abort.

local Login = {}

local MAX_ATTEMPTS = 5

local function base()
  local b = term.current()
  if term.native then
    local ok, native = pcall(term.native)
    if ok and native then b = native end
  end
  return b
end

local function wallpaperColor()
  local c = colours.blue
  if fs.exists("macaroon/settings.lua") then
    local ok, S = pcall(dofile, "macaroon/settings.lua")
    if ok and S then
      local ok2, s = pcall(S.load)
      if ok2 and type(s) == "table" and type(s.wallpaper) == "number" then
        c = s.wallpaper
      end
    end
  end
  return c
end

function Login.run()
  if not fs.exists("macaroon/users.lua") then
    return nil, "no accounts system"
  end
  local okU, UserLib = pcall(dofile, "macaroon/users.lua")
  if not okU or type(UserLib) ~= "table" then
    return nil, "accounts load failed"
  end
  local names = UserLib.list()
  if #names == 0 then
    return nil, "no accounts" -- fresh install without accounts: skip login
  end

  local bg = wallpaperColor()
  local sel = 1
  local pw = ""
  local focused = true -- password box always focused (single purpose screen)
  local attempts = 0
  local notice = ""
  local noticeBad = false
  local blinkOn = true
  local blinkTimer = os.startTimer(0.5)
  -- Layout (recomputed each draw).
  local L = {}

  local function layout()
    local w, h = term.getSize()
    L.w, L.h = w, h
    L.listY = math.max(3, math.floor(h / 2) - math.floor(#names / 2) - 3)
    L.boxY = L.listY + #names + 2
    if L.boxY > h - 3 then L.boxY = h - 3 end
    L.boxX = math.max(2, math.floor((w - 22) / 2) + 1)
    L.boxW = 22
    L.msgY = L.boxY + 2
    if L.msgY > h - 1 then L.msgY = h - 1 end
  end

  local function draw()
    term.redirect(base())
    layout()
    local w, h = L.w, L.h
    term.setBackgroundColor(bg)
    term.setTextColor(colours.white)
    term.clear()
    -- Brand, small, top-left.
    term.setCursorPos(2, 1)
    term.write("macaroon OS")
    -- User tiles.
    for i, n in ipairs(names) do
      local y = L.listY + i - 1
      if y >= 1 and y <= h then
        local label = (i == sel and "> " or "  ") .. n
        if i == sel then
          term.setBackgroundColor(colours.white)
          term.setTextColor(bg)
        else
          term.setBackgroundColor(bg)
          term.setTextColor(colours.white)
        end
        term.setCursorPos(math.max(2, math.floor((w - 24) / 2) + 1), y)
        term.write(string.sub(label .. string.rep(" ", 24), 1, 24))
      end
    end
    -- Avatar initial for selected user.
    local who = names[sel] or "?"
    term.setBackgroundColor(colours.white)
    term.setTextColor(bg)
    term.setCursorPos(math.floor(w / 2), L.boxY - 1)
    term.write(" " .. string.upper(string.sub(who, 1, 1)) .. " ")
    -- Password box.
    term.setBackgroundColor(colours.white)
    term.setTextColor(colours.lightGrey)
    term.setCursorPos(L.boxX, L.boxY)
    term.write(string.rep(" ", L.boxW))
    term.setCursorPos(L.boxX + 1, L.boxY)
    if pw == "" then
      term.setTextColor(colours.grey)
      term.write("Password")
    else
      term.setTextColor(colours.black)
      term.write(string.sub(string.rep("*", #pw), 1, L.boxW - 2))
    end
    if focused and blinkOn and pw ~= "" then
      local cx = L.boxX + 1 + #pw
      if cx < L.boxX + L.boxW then
        term.setCursorPos(cx, L.boxY)
        term.write("_")
      end
    end
    -- Notice line.
    term.setBackgroundColor(bg)
    if noticeBad then
      term.setTextColor(colours.yellow)
    else
      term.setTextColor(colours.white)
    end
    term.setCursorPos(2, L.msgY)
    term.write(string.rep(" ", w - 2))
    term.setCursorPos(2, L.msgY)
    term.write(string.sub(notice, 1, w - 2))
    -- Shutdown button, bottom-right.
    local sLabel = "[ Shutdown ]"
    term.setBackgroundColor(colours.red)
    term.setTextColor(colours.white)
    term.setCursorPos(math.max(1, w - #sLabel), h)
    term.write(sLabel)
    term.setBackgroundColor(bg)
  end

  local function welcome(name)
    term.redirect(base())
    local w, h = term.getSize()
    term.setBackgroundColor(bg)
    term.setTextColor(colours.white)
    term.clear()
    local frames = { "|", "/", "-", "\\" }
    local cy = math.floor(h / 2)
    for i = 1, 10 do
      term.setCursorPos(math.max(1, math.floor((w - 7) / 2) + 1), cy)
      term.write("Welcome")
      term.setCursorPos(math.floor(w / 2), cy + 2)
      term.write(frames[(i - 1) % 4 + 1])
      sleep(0.15)
    end
  end

  local function tryLogin()
    if pw == "" then
      notice = "Type your password."
      noticeBad = true
      return nil
    end
    notice = "Signing in..."
    noticeBad = false
    draw()
    local who = names[sel]
    local okV, good = pcall(UserLib.verify, who, pw)
    if okV and good then
      welcome(who)
      return who
    end
    attempts = attempts + 1
    pw = ""
    if attempts >= MAX_ATTEMPTS then
      return false -- locked sentinel (nil-safe: distinct from retry)
    end
    notice = "Incorrect password. " .. (MAX_ATTEMPTS - attempts) .. " left."
    noticeBad = true
    return nil
  end

  draw()
  while true do
    local event, p1, p2, p3 = os.pullEventRaw()
    if event == "terminate" then
      -- Swallowed: Ctrl+T must not escape the gate. drawAll to repaint.
      draw()
    elseif event == "timer" and p1 == blinkTimer then
      blinkOn = not blinkOn
      blinkTimer = os.startTimer(0.5)
      draw()
    elseif event == "term_resize" then
      draw()
    elseif event == "mouse_click" and p1 == 1 then
      local gx, gy = p2, p3
      local sLabel = "[ Shutdown ]"
      if gy == L.h and gx >= L.w - #sLabel then
        return nil, "shutdown"
      end
      for i in ipairs(names) do
        if gy == L.listY + i - 1 then
          sel = i
          notice = ""
          draw()
          break
        end
      end
    elseif event == "key" then
      if p1 == 200 then -- up
        sel = sel - 1
        if sel < 1 then sel = #names end
        notice = ""
        draw()
      elseif p1 == 208 then -- down
        sel = sel + 1
        if sel > #names then sel = 1 end
        notice = ""
        draw()
      elseif p1 == 28 then -- enter
        local r = tryLogin()
        if type(r) == "string" then
          return r
        elseif r == false then
          return nil, "locked"
        else
          draw()
        end
      elseif p1 == 14 then -- backspace
        pw = string.sub(pw, 1, -2)
        draw()
      end
    elseif event == "char" then
      if #pw < 32 then
        pw = pw .. tostring(p1)
      end
      draw()
    end
  end
end

return Login
