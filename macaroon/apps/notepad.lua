-- Macaroon OS - Notepad app (desktop GUI)
-- Plain-text editor for USER files. Never touches OS files.
-- State lives in file-scope upvalues (fresh per window via dofile).

local lines = { "" }
local cx, cy = 1, 1          -- 1-based cursor in text
local scroll = 1             -- first visible text row
local fname = nil            -- nil = untitled
local dirty = false
local confirmDiscard = false -- armed by canClose veto / New with changes
local confirmNew = false
local mode = "edit"          -- edit | open | saveas
local prompt = ""
local msg = ""

local VIEW_ROWS = 11 -- text rows between header and status

local function cleanPath(p)
  return (string.gsub(tostring(p or ""), "^%s*(.-)%s*$", "%1"))
end

-- Canonicalise a user path before any check or fs call. This closes the
-- obvious bypasses: "./startup.lua", "macaroon//users.dat", "a/../macaroon",
-- and absolute paths. Returns nil for anything that escapes the root.
local function normalizePath(p)
  p = cleanPath(p)
  if p == "" then return nil end
  local first = string.sub(p, 1, 1)
  if first == "/" or first == "\\" then return nil end
  -- Backslashes are not path separators in CraftOS; reject them rather
  -- than risk a host filesystem treating them as one.
  if string.find(p, "\\", 1, true) then return nil end
  local parts = {}
  local start = 1
  while true do
    local slash = string.find(p, "/", start, true)
    local part
    if slash then
      part = string.sub(p, start, slash - 1)
      start = slash + 1
    else
      part = string.sub(p, start)
    end
    if part == ".." then
      if #parts == 0 then return nil end
      table.remove(parts)
    elseif part ~= "" and part ~= "." then
      table.insert(parts, part)
    end
    if not slash then break end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, "/")
end

-- Security gate (single choke point for open AND save): the OS's own
-- files are never readable or writable here. Everything else (user
-- files anywhere else, e.g. notes.txt, docs/todo.txt) is allowed.
local function isProtected(p)
  local n = normalizePath(p)
  if not n then return true end
  n = string.lower(n)
  if n == "startup.lua" then return true end
  if n == "macaroon" or string.sub(n, 1, 9) == "macaroon/" then return true end
  return false
end

local function markDirty()
  dirty = true
  confirmDiscard = false
  confirmNew = false
end

local function curLine()
  return lines[cy] or ""
end

local function clampCursor()
  if cy < 1 then cy = 1 end
  if cy > #lines then cy = #lines end
  if #lines < 1 then lines = { "" } cy = 1 end
  local n = #(lines[cy] or "") + 1
  if cx < 1 then cx = 1 end
  if cx > n then cx = n end
  if cy < scroll then scroll = cy end
  if cy > scroll + VIEW_ROWS - 1 then scroll = cy - VIEW_ROWS + 1 end
  if scroll < 1 then scroll = 1 end
end

local function insertChar(c)
  local ln = curLine()
  lines[cy] = string.sub(ln, 1, cx - 1) .. c .. string.sub(ln, cx)
  cx = cx + 1
  markDirty()
end

local function backspace()
  if cx > 1 then
    local ln = curLine()
    lines[cy] = string.sub(ln, 1, cx - 2) .. string.sub(ln, cx)
    cx = cx - 1
    markDirty()
  elseif cy > 1 then
    local prev = lines[cy - 1] or ""
    cx = #prev + 1
    lines[cy - 1] = prev .. curLine()
    table.remove(lines, cy)
    cy = cy - 1
    markDirty()
  end
end

local function splitLine()
  local ln = curLine()
  lines[cy] = string.sub(ln, 1, cx - 1)
  table.insert(lines, cy + 1, string.sub(ln, cx))
  cy = cy + 1
  cx = 1
  markDirty()
end

local function moveCursor(dx, dy)
  if dy ~= 0 then
    cy = cy + dy
    clampCursor()
  elseif dx ~= 0 then
    if dx < 0 and cx == 1 and cy > 1 then
      cy = cy - 1
      cx = #(lines[cy] or "") + 1
    elseif dx > 0 and cx == #(curLine()) + 1 and cy < #lines then
      cy = cy + 1
      cx = 1
    else
      cx = cx + dx
    end
    clampCursor()
  end
end

local function loadPath(path)
  path = normalizePath(path)
  if not path or isProtected(path) then
    msg = "Protected file."
    return false
  end
  if not fs.exists(path) then
    msg = "Not found."
    return false
  end
  local h = fs.open(path, "r")
  if not h then
    msg = "Cannot read."
    return false
  end
  local okR, data = pcall(h.readAll)
  pcall(h.close)
  if not okR or type(data) ~= "string" then
    msg = "Cannot read."
    return false
  end
  lines = {}
  local start = 1
  while true do
    local nl = string.find(data, "\n", start, true)
    if not nl then
      local last = string.gsub(string.sub(data, start), "\r$", "")
      table.insert(lines, last)
      break
    end
    local line = string.gsub(string.sub(data, start, nl - 1), "\r$", "")
    table.insert(lines, line)
    start = nl + 1
  end
  if #lines < 1 then lines = { "" } end
  cx, cy, scroll = 1, 1, 1
  fname = path
  dirty = false
  confirmDiscard = false
  confirmNew = false
  msg = ""
  return true
end

local function saveNow()
  if not fname then
    mode = "saveas"
    prompt = ""
    msg = ""
    return false
  end
  local path = normalizePath(fname)
  if not path or isProtected(path) then
    msg = "Protected file."
    return false
  end
  fname = path
  local dir = fs.getDir(fname)
  if dir ~= "" and not fs.exists(dir) then
    local okM = pcall(fs.makeDir, dir)
    if not okM then
      msg = "Cannot write."
      return false
    end
  end
  local h = fs.open(fname, "w")
  if not h then
    msg = "Cannot write."
    return false
  end
  local okW = pcall(h.write, table.concat(lines, "\n"))
  pcall(h.close)
  if not okW then
    msg = "Cannot write."
    return false
  end
  dirty = false
  confirmDiscard = false
  msg = "Saved."
  return true
end

local function doNew()
  if dirty and not confirmNew then
    confirmNew = true
    msg = "Unsaved! N again drops it."
    return
  end
  lines = { "" }
  cx, cy, scroll = 1, 1, 1
  fname = nil
  dirty = false
  confirmDiscard = false
  confirmNew = false
  mode = "edit"
  msg = ""
end

local function submitPrompt()
  local path = normalizePath(prompt)
  mode = "edit"
  prompt = ""
  if not path then
    msg = "Cancelled."
    return
  end
  if isProtected(path) then
    msg = "Protected file."
    return
  end
  loadPath(path)
end

local function submitSaveAs()
  local path = normalizePath(prompt)
  mode = "edit"
  prompt = ""
  if not path then
    msg = "Cancelled."
    return
  end
  if isProtected(path) then
    msg = "Protected file."
    return
  end
  fname = path
  saveNow()
end

local function headerText(w)
  local t = "note: " .. (fname or "untitled")
  if dirty then t = t .. " *" end
  if #t > w - 1 then t = string.sub(t, 1, w - 1) end
  return t
end

return {
  title = "Notepad",
  width = 44,
  height = 14,

  -- Close guard: unsaved work vetoes manager-close (X / Delete) once;
  -- the veto arms confirmDiscard and the app explains itself via msg.
  -- A second close attempt discards. Clean buffers always close.
  canClose = function()
    if dirty and not confirmDiscard then
      confirmDiscard = true
      msg = "Unsaved! X/Del again drops it."
      return false
    end
    return true
  end,

  draw = function(win)
    local w = 44
    local h = 13
    if win.getSize then
      local okS, ww, hh = pcall(win.getSize)
      if okS and type(ww) == "number" and ww > 10 then w = ww end
      if okS and type(hh) == "number" and hh > 5 then h = hh end
    end
    local bodyRows = h - 2
    if bodyRows > VIEW_ROWS then bodyRows = VIEW_ROWS end
    if bodyRows < 1 then bodyRows = 1 end
    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.black)
    win.clear()
    -- Header: filename + unsaved marker.
    win.setCursorPos(2, 1)
    win.setTextColor(colours.blue)
    win.write(headerText(w))
    win.setTextColor(colours.black)
    -- Text viewport.
    clampCursor()
    for r = 1, bodyRows do
      local ln = lines[scroll + r - 1] or ""
      win.setCursorPos(2, 1 + r)
      if #ln > w - 3 then ln = string.sub(ln, 1, w - 3) end
      win.write(ln)
    end
    -- Cursor block.
    local ccx = cx
    if ccx > w - 2 then ccx = w - 2 end
    local ccy = 1 + (cy - scroll + 1)
    if ccy >= 2 and ccy <= 1 + bodyRows then
      win.setCursorPos(1 + ccx, ccy)
      win.setBackgroundColor(colours.black)
      win.setTextColor(colours.white)
      win.write("_")
      win.setBackgroundColor(colours.white)
      win.setTextColor(colours.black)
    end
    -- Status / prompt row.
    win.setCursorPos(2, h)
    if mode == "open" then
      win.write("Open: " .. prompt .. "_")
    elseif mode == "saveas" then
      win.write("Save: " .. prompt .. "_")
    elseif msg ~= "" then
      local m = msg
      if #m > w - 3 then m = string.sub(m, 1, w - 3) end
      win.write(m)
    else
      win.write("F4 New  F3 Open  F2 Save  F5 As")
    end
  end,

  onEvent = function(win, event, p1, cxArg, cyArg)
    if event == "close_request" then
      return true -- redraw so the veto message shows
    end
    if mode == "open" or mode == "saveas" then
      if event == "char" then
        if #prompt < 64 then prompt = prompt .. tostring(p1) end
        return true
      elseif event == "key" and p1 == 14 then
        prompt = string.sub(prompt, 1, -2)
        return true
      elseif event == "key" and p1 == 28 then
        if mode == "open" then submitPrompt() else submitSaveAs() end
        return true
      elseif event == "key" and p1 == 1 then
        mode = "edit"
        prompt = ""
        msg = "Cancelled."
        return true
      end
      return false
    end
    if event == "char" then
      insertChar(tostring(p1))
      return true
    elseif event == "key" then
      if p1 == 14 then backspace()
      elseif p1 == 28 then splitLine()
      elseif p1 == 60 then saveNow()                 -- F2
      elseif p1 == 61 then mode = "open" prompt = "" msg = ""  -- F3
      elseif p1 == 62 then doNew()                   -- F4
      elseif p1 == 63 then mode = "saveas" prompt = "" msg = "" -- F5
      elseif p1 == 200 then moveCursor(0, -1)
      elseif p1 == 208 then moveCursor(0, 1)
      elseif p1 == 203 then moveCursor(-1, 0)
      elseif p1 == 205 then moveCursor(1, 0)
      elseif p1 == 201 then scroll = scroll - 10 clampCursor()
      elseif p1 == 209 then scroll = scroll + 10 clampCursor()
      else return false end
      return true
    elseif event == "mouse_click" then
      local w = 44
      if win.getSize then
        local okS, ww = pcall(win.getSize)
        if okS and type(ww) == "number" and ww > 10 then w = ww end
      end
      local h = 13
      if cyArg == h then
        -- Status buttons in 4 zones.
        if cxArg ~= nil and cxArg <= 11 then
          doNew()
        elseif cxArg ~= nil and cxArg <= 22 then
          mode = "open" prompt = "" msg = ""
        elseif cxArg ~= nil and cxArg <= 33 then
          saveNow()
        else
          mode = "saveas" prompt = "" msg = ""
        end
        return true
      elseif cyArg ~= nil and cyArg >= 2 and cyArg <= 1 + VIEW_ROWS then
        -- Click-to-move-cursor in the viewport.
        local ln = cyArg - 2 + scroll
        if ln >= 1 and ln <= #lines then
          cy = ln
          cx = (cxArg or 2) - 1
          clampCursor()
          return true
        end
      end
      return false
    elseif event == "mouse_scroll" then
      if p1 == 1 then scroll = scroll + 3 else scroll = scroll - 3 end
      clampCursor()
      return true
    end
    return false
  end
}
