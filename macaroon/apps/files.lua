-- Macaroon OS - Files app (file manager)
-- Click a row to select, [Open] to enter/view, [Del] twice to delete.
-- State in file-scope upvalues (fresh per window via dofile).

local cwd = "/"
local entries = {}
local scroll = 0
local selected = 0 -- absolute index into entries, 0 = none
local delArm = false
local mode = "browse" -- or "view"
local viewName = ""
local viewLines = {}
local viewScroll = 0
local status = ""

local function normDir(d)
  if d == "" or d == "." then return "/" end
  if string.sub(d, 1, 1) ~= "/" then d = "/" .. d end
  if #d > 1 and string.sub(d, -1) == "/" then
    d = string.sub(d, 1, -2)
  end
  return d
end

local function refresh()
  cwd = normDir(cwd)
  local ok, list = pcall(fs.list, cwd)
  if not ok or type(list) ~= "table" then
    status = "cannot list"
    entries = {}
    selected = 0
    return
  end
  table.sort(list, function(a, b)
    local da = fs.isDir(fs.combine(cwd, a))
    local db = fs.isDir(fs.combine(cwd, b))
    if da ~= db then return da end
    return string.lower(a) < string.lower(b)
  end)
  entries = list
  if selected > #entries then selected = #entries end
  if selected < 0 then selected = 0 end
  scroll = 0
  delArm = false
  status = #entries .. " item(s)"
end
refresh()

local function entryRows(h)
  return math.max(h - 6, 1) -- rows 3..h-4
end

local function loadView(name)
  local path = fs.combine(cwd, name)
  if fs.isDir(path) then return end
  local h = fs.open(path, "r")
  if not h then status = "cannot open" return end
  local data = h.readAll()
  h.close()
  if data == nil then status = "cannot read" return end
  if #data > 8192 then
    status = "too big to view"
    return
  end
  viewLines = {}
  for line in string.gmatch(data .. "\n", "([^\n]*)\n") do
    viewLines[#viewLines + 1] = line
  end
  viewName = name
  viewScroll = 0
  mode = "view"
  status = #viewLines .. " line(s)"
end

local function openSelected()
  local e = entries[selected]
  if not e then status = "nothing selected" return end
  local full = fs.combine(cwd, e)
  if fs.isDir(full) then
    cwd = normDir(full)
    selected = 0
    refresh()
  else
    loadView(e)
  end
end

local function deleteSelected()
  local e = entries[selected]
  if not e then status = "nothing selected" return false end
  if not delArm then
    delArm = true
    status = "click Del again: " .. e
    return true
  end
  local ok = pcall(fs.delete, fs.combine(cwd, e))
  delArm = false
  if ok then
    status = "deleted " .. e
    selected = 0
    refresh()
  else
    status = "delete failed"
  end
  return true
end

return {
  title = "Files",
  width = 38,
  height = 14,

  draw = function(win)
    local w, h = win.getSize()
    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.black)
    win.clear()
    if mode == "view" then
      win.setCursorPos(2, 1)
      win.setTextColor(colours.blue)
      win.write(string.sub("< " .. viewName, 1, w - 2))
      win.setTextColor(colours.black)
      local rows = h - 2
      for r = 1, rows do
        local line = viewLines[viewScroll + r]
        win.setCursorPos(1, 1 + r)
        if line then
          win.write(" " .. string.sub(line, 1, w - 1))
        end
      end
      win.setCursorPos(1, h)
      win.setTextColor(colours.grey)
      win.write(" click < back, scroll up/dn")
      return
    end
    -- row 1: path + +Dir
    win.setCursorPos(2, 1)
    win.setTextColor(colours.blue)
    win.write(string.sub(cwd, 1, w - 12))
    win.setCursorPos(w - 9, 1)
    win.setBackgroundColor(colours.grey)
    win.setTextColor(colours.white)
    win.write(" +Dir ")
    win.setBackgroundColor(colours.white)
    -- row 2: up + selection
    win.setCursorPos(2, 2)
    win.setTextColor(colours.grey)
    win.write("[..]")
    local sel = entries[selected]
    win.setTextColor(colours.black)
    win.setCursorPos(8, 2)
    win.write(string.sub(sel and ("* " .. sel) or "(none)", 1, w - 8))
    -- entries rows 3..h-4
    local rows = entryRows(h)
    for r = 1, rows do
      local idx = scroll + r
      local e = entries[idx]
      win.setCursorPos(1, 2 + r)
      if e then
        if idx == selected then
          win.setBackgroundColor(colours.lightBlue)
        else
          win.setBackgroundColor(colours.white)
        end
        local full = fs.combine(cwd, e)
        if fs.isDir(full) then
          win.setTextColor(colours.blue)
          win.write(" [" .. string.sub(e, 1, w - 5) .. "/]")
        else
          win.setTextColor(colours.black)
          win.write("  " .. string.sub(e, 1, w - 4))
        end
        win.setBackgroundColor(colours.white)
      end
    end
    -- action row h-3: [Open] [Del]
    win.setCursorPos(2, h - 3)
    win.setBackgroundColor(colours.green)
    win.setTextColor(colours.white)
    win.write(" Open ")
    win.setCursorPos(9, h - 3)
    if delArm then
      win.setBackgroundColor(colours.red)
    else
      win.setBackgroundColor(colours.grey)
    end
    win.write(" Del ")
    win.setBackgroundColor(colours.white)
    -- status rows
    win.setCursorPos(1, h - 1)
    win.setTextColor(colours.grey)
    win.write(" " .. string.sub(status, 1, w - 1))
  end,

  onEvent = function(win, event, p1, cx, cy)
    local w, h = win.getSize()
    if event == "mouse_scroll" then
      local step = (p1 == 1) and 1 or -1
      if mode == "view" then
        viewScroll = math.max(0, math.min(math.max(#viewLines - (h - 2), 0),
          viewScroll + step))
      else
        scroll = math.max(0, math.min(math.max(#entries - entryRows(h), 0),
          scroll + step))
      end
      return true
    end
    if event ~= "mouse_click" or not cx or not cy then
      return false
    end
    if mode == "view" then
      if cy == 1 and cx <= 4 then
        mode = "browse"
        return true
      end
      return false
    end
    if cy == 1 and cx >= w - 9 then -- +Dir
      local n = 1
      while fs.exists(fs.combine(cwd, "folder" .. n)) do n = n + 1 end
      local ok = pcall(fs.makeDir, fs.combine(cwd, "folder" .. n))
      status = ok and ("made folder" .. n) or "mkdir failed"
      refresh()
      return true
    end
    if cy == 2 and cx <= 6 then -- [..] up
      if cwd ~= "/" then
        cwd = normDir(fs.getDir(cwd))
        selected = 0
        refresh()
        return true
      end
      return false
    end
    if cy == h - 3 then
      if cx >= 2 and cx <= 7 then -- Open
        openSelected()
        return true
      elseif cx >= 9 and cx <= 13 then -- Del
        deleteSelected()
        return true
      end
      return false
    end
    local rows = entryRows(h)
    if cy >= 3 and cy <= 2 + rows then
      local idx = scroll + (cy - 2)
      if entries[idx] then
        if selected == idx then
          openSelected() -- second click opens
        else
          selected = idx
          delArm = false
          status = entries[idx]
        end
        return true
      end
    end
    return false
  end
}
