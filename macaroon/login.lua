-- Macaroon OS - graphical login screen (secure boot gate)
-- Cookie logo + wordmark, badge user tiles, pill password box,
-- Welcome spinner on success. Fullscreen term UI, no desktop needed.
-- Returns username on success, or nil + reason ("shutdown", "locked",
-- "no accounts", ...). Ignores terminate so Ctrl+T can't escape it;
-- startup's trap remains the backstop for any other abort.

local Login = {}

local MAX_ATTEMPTS = 5
local TILE_W = 26
local BOX_W = 24
local MAX_TILES = 5

-- 12x6 macaroon cookie (same art as the boot splash).
local COOKIE = {
  "fffccccccfff",
  "ffccccccccff",
  "fcccfccfcccf",
  "fccfccccfccf",
  "ffcccfccccff",
  "fffccccccfff",
}

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
  local top = 1 -- first visible tile (scrolls for long lists)
  local pw = ""
  local attempts = 0
  local notice = ""
  local noticeBad = false
  local blinkOn = true
  local blinkTimer = os.startTimer(0.5)
  local L = {} -- layout cache, recomputed each draw

  local function layout()
    local w, h = term.getSize()
    L.w, L.h = w, h
    L.logoX = math.max(1, math.floor((w - 12) / 2) + 1)
    L.logoY = 2
    L.wordY = 9
    L.tileY = 11
    L.tileX = math.max(1, math.floor((w - TILE_W) / 2) + 1)
    L.boxY = L.tileY + math.min(#names, MAX_TILES) + 1
    if L.boxY > h - 3 then L.boxY = h - 3 end
    L.boxX = math.max(1, math.floor((w - BOX_W) / 2) + 1)
    L.msgY = L.boxY + 2
    if L.msgY > h - 1 then L.msgY = h - 1 end
    if sel < top then top = sel end
    if sel > top + MAX_TILES - 1 then top = sel - MAX_TILES + 1 end
  end

  local function draw()
    term.redirect(base())
    layout()
    local w, h = L.w, L.h
    term.setBackgroundColor(bg)
    term.setTextColor(colours.white)
    term.clear()
    -- Cookie logo.
    for i, rowBg in ipairs(COOKIE) do
      local y = L.logoY + i - 1
      if y >= 1 and y <= h then
        term.setCursorPos(L.logoX, y)
        term.blit(string.rep(" ", 12), string.rep("f", 12), rowBg)
      end
    end
    -- Wordmark.
    term.setBackgroundColor(bg)
    term.setTextColor(colours.white)
    local word = "macaroon"
    term.setCursorPos(math.max(1, math.floor((w - #word) / 2) + 1), L.wordY)
    term.write(word)
    -- User tiles.
    for r = 1, MAX_TILES do
      local idx = top + r - 1
      local y = L.tileY + r - 1
      if idx <= #names and y >= 1 and y <= h then
        local n = names[idx]
        term.setCursorPos(L.tileX, y)
        if idx == sel then
          -- Selected: bright bar with initial badge.
          term.setBackgroundColor(colours.white)
          term.setTextColor(bg)
          term.write(" " .. string.upper(string.sub(n, 1, 1)) .. " ")
          term.setBackgroundColor(bg)
          term.setTextColor(colours.white)
          term.write(" " .. string.sub(n, 1, TILE_W - 6))
        else
          term.setBackgroundColor(bg)
          term.setTextColor(colours.lightGrey)
          term.write("   " .. string.sub(n, 1, TILE_W - 6))
        end
      end
    end
    -- Scroll hint.
    if #names > MAX_TILES then
      term.setBackgroundColor(bg)
      term.setTextColor(colours.lightGrey)
      term.setCursorPos(L.tileX + TILE_W - 6, L.tileY + MAX_TILES - 1)
      term.write("v more")
    end
    -- Password pill.
    term.setBackgroundColor(colours.white)
    term.setCursorPos(L.boxX, L.boxY)
    term.write(string.rep(" ", BOX_W))
    term.setCursorPos(L.boxX + 1, L.boxY)
    if pw == "" then
      term.setTextColor(colours.grey)
      term.write("Password")
    else
      term.setTextColor(colours.black)
      term.write(string.sub(string.rep("*", #pw), 1, BOX_W - 2))
      if blinkOn then
        local cx = L.boxX + 1 + #pw
        if cx < L.boxX + BOX_W then
          term.setCursorPos(cx, L.boxY)
          term.write("_")
        end
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
    -- Bottom bar: brand left, shutdown right.
    term.setBackgroundColor(bg)
    term.setTextColor(colours.lightGrey)
    term.setCursorPos(2, h)
    term.write("macaroon OS")
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
    local line1 = "Welcome,"
    local line2 = name
    for i = 1, 10 do
      term.setCursorPos(math.max(1, math.floor((w - #line1) / 2) + 1), cy)
      term.write(line1)
      term.setCursorPos(math.max(1, math.floor((w - #line2) / 2) + 1), cy + 1)
      term.write(string.sub(line2, 1, w))
      term.setCursorPos(math.floor(w / 2), cy + 3)
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
      return false -- locked sentinel
    end
    notice = "Incorrect password. " .. (MAX_ATTEMPTS - attempts) .. " left."
    noticeBad = true
    return nil
  end

  draw()
  while true do
    local event, p1, p2, p3 = os.pullEventRaw()
    if event == "terminate" then
      draw() -- swallowed: Ctrl+T must not escape the gate
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
      for r = 1, MAX_TILES do
        local idx = top + r - 1
        if idx <= #names and gy == L.tileY + r - 1
           and gx >= L.tileX and gx < L.tileX + TILE_W then
          sel = idx
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
