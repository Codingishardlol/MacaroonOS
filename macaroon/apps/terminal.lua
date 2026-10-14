-- Macaroon OS - Terminal app
-- Type commands, Enter runs them via shell, output scraped back
-- into scrollback. `clear` wipes, `exit`/`logout` hint at closing.
-- State in file-scope upvalues (fresh per window via dofile).

local lines = { "macaroon Terminal - type help" }
local input = ""
local scroll = 0
local MAX = 120

local function push(line)
  lines[#lines + 1] = tostring(line or "")
  while #lines > MAX do
    table.remove(lines, 1)
  end
  scroll = 0
end

local function runCommand(win, cmd)
  cmd = string.gsub(cmd or "", "^%s*(.-)%s*$", "%1")
  if cmd == "" then return end
  push("> " .. cmd)
  if cmd == "clear" then
    lines = {}
    return
  end
  if cmd == "exit" or cmd == "logout" or cmd == "quit" then
    push("close the window (X) to exit")
    return
  end
  if not shell then
    -- Startup normally bootstraps this; retry here so the message
    -- says WHY instead of just "no shell API".
    local okB, booted, reason = pcall(dofile, "macaroon/shellboot.lua")
    if not (okB and booted) then
      push("no shell API (" .. tostring(reason or "bootstrap failed") .. ")")
      return
    end
  end
  -- Snapshot _G AND one level of shared API tables: commands run with
  -- full access, so `os.pullEventRaw = ...` mutates the shared os table
  -- rather than _G, and would otherwise hijack the desktop persistently.
  local snap = {}
  local sub = {}
  for k, v in pairs(_G) do
    snap[k] = v
    if type(v) == "table" then
      local inner = {}
      for sk, sv in pairs(v) do
        inner[sk] = sv
      end
      sub[k] = inner
    end
  end
  local prev = term.current()
  term.redirect(win)
  local ok, err = pcall(shell.run, cmd)
  -- Restore globals changed or added by the command.
  local added = {}
  for k in pairs(_G) do
    if snap[k] == nil then
      added[#added + 1] = k
    end
  end
  for _, k in ipairs(added) do
    _G[k] = nil
  end
  for k, v in pairs(snap) do
    if _G[k] ~= v then
      _G[k] = v
    end
  end
  -- Restore mutated API tables still present under the same key.
  for k, inner in pairs(sub) do
    local t = _G[k]
    if type(t) == "table" then
      local subAdded = {}
      for sk in pairs(t) do
        if inner[sk] == nil then
          subAdded[#subAdded + 1] = sk
        end
      end
      for _, sk in ipairs(subAdded) do
        t[sk] = nil
      end
      for sk, sv in pairs(inner) do
        if t[sk] ~= sv then
          t[sk] = sv
        end
      end
    end
  end
  -- Scrape visible window content into scrollback before desktop redraws.
  local w, h = win.getSize()
  for r = 1, h do
    local okLine, text = pcall(win.getLine, r)
    if okLine and type(text) == "string" then
      local t = string.gsub(text, "%s+$", "")
      if t ~= "" then push(t) end
    end
  end
  term.redirect(prev)
  if not ok then
    push("error: " .. tostring(err))
  end
end

return {
  title = "Terminal",
  width = 44,
  height = 14,

  draw = function(win)
    local w, h = win.getSize()
    win.setBackgroundColor(colours.black)
    win.setTextColor(colours.white)
    win.clear()
    local rows = h - 1
    local start = math.max(#lines - rows + 1 - scroll, 1)
    for r = 1, rows do
      local line = lines[start + r - 1]
      win.setCursorPos(1, r)
      if line then
        win.write(string.sub(line, 1, w))
      end
    end
    win.setCursorPos(1, h)
    win.setTextColor(colours.yellow)
    win.write("> " .. string.sub(input, math.max(#input - w + 3, 1)))
  end,

  onEvent = function(win, event, p1, cx, cy)
    if event == "char" then
      input = input .. tostring(p1)
      return true
    elseif event == "key" then
      if p1 == 28 then -- Enter
        local cmd = input
        input = ""
        runCommand(win, cmd)
        return true
      elseif p1 == 14 then -- Backspace
        input = string.sub(input, 1, -2)
        return true
      end
      return false
    elseif event == "mouse_scroll" then
      local h = select(2, win.getSize())
      local maxScroll = math.max(#lines - (h - 1), 0)
      if p1 == 1 then
        scroll = math.min(maxScroll, scroll + 1)
      else
        scroll = math.max(0, scroll - 1)
      end
      return true
    end
    return false
  end
}
