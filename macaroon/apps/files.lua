-- Macaroon OS - Files app (file manager)
-- Click a row to select, second click / [Open] enters dirs or views text.
-- [Del] twice deletes, [Copy] duplicates, [Ren] renames inline, [New] makes file.
-- State in file-scope upvalues (fresh per window via dofile).

local cwd = "/"
local entries = {}
local isDirCache = {} -- parallel to entries, cached in refresh (keeps draw fs-free)
local scroll = 0
local selected = 0 -- absolute index into entries, 0 = none
local delArm = false
local mode = "browse" -- or "view"
local viewName = ""
local viewLines = {}
local viewScroll = 0
local status = ""
local inputMode = nil -- nil or "rename"
local inputText = ""
local renameOrig = ""

local function normDir(d)
  if d == "" or d == "." then return "/" end
  if string.sub(d, 1, 1) ~= "/" then d = "/" .. d end
  if #d > 1 and string.sub(d, -1) == "/" then
    d = string.sub(d, 1, -2)
  end
  return d
end

-- Safe wrappers: never throw.
local function isDirSafe(p)
  local ok, v = pcall(fs.isDir, p)
  if ok then return v else return false end
end

local function existsSafe(p)
  local ok, v = pcall(fs.exists, p)
  if ok then return v else return false end
end

-- Copy one file via open/read/write.
local function copyFile(src, dst)
  local rh = nil
  local ok, h = pcall(fs.open, src, "r")
  if not ok or not h then return false end
  rh = h
  local okR, data = pcall(function() return rh.readAll() end)
  pcall(function() rh.close() end)
  if not okR or data == nil then return false end
  local wh = nil
  local okW, h2 = pcall(fs.open, dst, "w")
  if not okW or not h2 then return false end
  wh = h2
  local okWr = pcall(function() wh.write(data) end)
  pcall(function() wh.close() end)
  return okWr
end

local function copyTree(src, dst)
  if isDirSafe(src) then
    pcall(fs.makeDir, dst)
    local okL, list = pcall(fs.list, src)
    if not okL or type(list) ~= "table" then return false end
    for _, n in ipairs(list) do
      local s = fs.combine(src, n)
      local d = fs.combine(dst, n)
      if not copyTree(s, d) then return false end
    end
    return true
  end
  return copyFile(src, dst)
end

local function refresh()
  cwd = normDir(cwd)
  local ok, list = pcall(fs.list, cwd)
  if not ok or type(list) ~= "table" then
    status = "cannot list"
    entries = {}
    isDirCache = {}
    selected = 0
    return
  end
  table.sort(list, function(a, b)
    local da = isDirSafe(fs.combine(cwd, a))
    local db = isDirSafe(fs.combine(cwd, b))
    if da ~= db then return da end
    return string.lower(a) < string.lower(b)
  end)
  entries = list
  isDirCache = {}
  for i, e in ipairs(entries) do
    isDirCache[i] = isDirSafe(fs.combine(cwd, e))
  end
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
  if isDirSafe(path) then return end
  -- Password hashes are not reading material, even for the owner
  -- browsing idly: they exist only for offline cracking.
  local tail = string.match(normDir(path), "([^/]+)$") or ""
  if tail == "users.dat" then
    status = "protected file"
    return
  end
  local okO, h = pcall(fs.open, path, "r")
  if not okO or not h then status = "cannot open" return end
  local okR, data = pcall(function() return h.readAll() end)
  pcall(function() h.close() end)
  if not okR or data == nil then status = "cannot read" return end
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
  inputMode = nil
  inputText = ""
  status = #viewLines .. " line(s)"
end

local function openSelected()
  local e = entries[selected]
  if not e then status = "nothing selected" return end
  local full = fs.combine(cwd, e)
  if isDirSafe(full) then
    cwd = normDir(full)
    selected = 0
    inputMode = nil
    inputText = ""
    refresh()
  else
    loadView(e)
  end
end

-- System paths the Files app must never delete or move:
-- /startup.lua (boot) and everything under /macaroon/ (OS itself).
-- Viewing and copying them stays allowed (useful for backup).
local function sysPath(name)
  local a = normDir(fs.combine(cwd, name))
  if a == "/startup.lua" or a == "/macaroon" then return true end
  return string.sub(a, 1, 10) == "/macaroon/"
end

local function deleteSelected()
  local e = entries[selected]
  if not e then status = "nothing selected" return false end
  if not delArm then
    delArm = true
    status = "click Del again: " .. e
    return true
  end
  if sysPath(e) then
    delArm = false
    status = "system file protected"
    return true
  end
  local target = fs.combine(cwd, e)
  pcall(fs.delete, target)
  delArm = false
  if not existsSafe(target) then
    selected = 0
    inputMode = nil
    inputText = ""
    refresh()
    status = "deleted " .. e
  else
    status = "delete failed"
  end
  return true
end

-- Build "base_copyN.ext" (dirs: "name_copyN") that does not exist.
local function uniqueCopyName(name, isDir)
  local base, ext = name, ""
  if not isDir then
    local b, x = string.match(name, "^(.*)%.([^%.]+)$")
    if b and b ~= "" then base, ext = b, "." .. x end
  end
  local n = 1
  while n < 1000 do
    local cand = base .. "_copy" .. n .. ext
    if not existsSafe(fs.combine(cwd, cand)) then return cand end
    n = n + 1
  end
  return nil
end

local function doCopy()
  local e = entries[selected]
  if not e then status = "nothing selected" return end
  local tail = string.match(e, "([^/]+)$") or e
  if tail == "users.dat" then
    status = "protected file"
    return
  end
  local idx = selected
  local isD = isDirCache[idx] or isDirSafe(fs.combine(cwd, e))
  local cand = uniqueCopyName(e, isD)
  if not cand then status = "copy failed" return end
  local ok = copyTree(fs.combine(cwd, e), fs.combine(cwd, cand))
  delArm = false
  inputMode = nil
  inputText = ""
  refresh()
  if ok then
    status = "copied to " .. cand
  else
    status = "copy failed"
  end
end

local function startRename()
  local e = entries[selected]
  if not e then status = "nothing selected" return end
  delArm = false
  inputMode = "rename"
  renameOrig = e
  inputText = e
  status = "Ren: Enter ok, Esc cancel"
end

local function commitRename()
  local newName = string.gsub(inputText or "", "^%s*(.-)%s*$", "%1")
  local orig = renameOrig
  inputMode = nil
  inputText = ""
  if newName == "" then status = "empty name" return end
  if newName == orig then status = "unchanged" return end
  if string.find(newName, "/") then status = "no / in name" return end
  if sysPath(orig) or sysPath(newName) then
    status = "system file protected"
    return
  end
  local src = fs.combine(cwd, orig)
  local dst = fs.combine(cwd, newName)
  if existsSafe(dst) then status = "name exists" return end
  local moved = false
  if fs.move then
    local ok = pcall(fs.move, src, dst)
    if ok and not existsSafe(src) then moved = true end
  end
  if not moved then
    -- Fallback: copy then delete.
    if copyTree(src, dst) then
      pcall(fs.delete, src)
      moved = not existsSafe(src)
    end
  end
  delArm = false
  selected = 0
  refresh()
  if moved then
    -- Reselect renamed entry.
    for i, e in ipairs(entries) do
      if e == newName then selected = i break end
    end
    status = "renamed to " .. newName
  else
    status = "rename failed"
  end
end

local function doNew()
  local n = 1
  while n < 1000 and existsSafe(fs.combine(cwd, "newfile" .. n .. ".txt")) do
    n = n + 1
  end
  local name = "newfile" .. n .. ".txt"
  local okO, h = pcall(fs.open, fs.combine(cwd, name), "w")
  if not okO or not h then status = "create failed" return end
  pcall(function() h.close() end)
  delArm = false
  inputMode = nil
  inputText = ""
  refresh()
  for i, e in ipairs(entries) do
    if e == name then selected = i break end
  end
  loadView(name) -- opens empty file in view mode
  if mode ~= "view" then status = "made " .. name end
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
        if isDirCache[idx] then
          win.setTextColor(colours.blue)
          win.write(" [" .. string.sub(e, 1, w - 5) .. "/]")
        else
          win.setTextColor(colours.black)
          win.write("  " .. string.sub(e, 1, w - 4))
        end
        win.setBackgroundColor(colours.white)
      end
    end
    -- action row h-3: Open Del Copy Ren New
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
    win.setCursorPos(15, h - 3)
    win.setBackgroundColor(colours.grey)
    win.write(" Copy ")
    win.setCursorPos(22, h - 3)
    win.setBackgroundColor(colours.grey)
    win.write(" Ren ")
    win.setCursorPos(28, h - 3)
    win.setBackgroundColor(colours.grey)
    win.write(" New ")
    win.setBackgroundColor(colours.white)
    -- status row h-1
    win.setCursorPos(1, h - 1)
    win.setTextColor(colours.grey)
    win.write(" " .. string.sub(status, 1, w - 1))
    -- inline rename input on last row h
    if inputMode == "rename" then
      win.setCursorPos(1, h)
      win.setTextColor(colours.black)
      win.write(" Ren:" .. string.sub(inputText, math.max(#inputText - (w - 8), 1)) .. "_")
    end
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
    if event == "char" then
      if mode == "browse" and inputMode == "rename" then
        if type(p1) == "string" and #p1 > 0 and p1 ~= "/" then
          inputText = string.sub(inputText .. p1, 1, 32)
        end
        return true
      end
      return false
    end
    if event == "key" then
      if mode == "browse" and inputMode == "rename" then
        if p1 == 28 then -- Enter commits
          commitRename()
          return true
        elseif p1 == 14 then -- Backspace
          inputText = string.sub(inputText, 1, -2)
          return true
        elseif p1 == 1 then -- Esc cancels
          inputMode = nil
          inputText = ""
          status = "rename cancelled"
          return true
        end
        return false
      end
      return false
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
    -- browse: keep scroll/up/view paths alive during rename; cancel rename silently
    local wasRenaming = (inputMode == "rename")
    if wasRenaming then
      inputMode = nil
      inputText = ""
    end
    if cy == 1 and cx >= w - 9 then -- +Dir
      local n = 1
      while existsSafe(fs.combine(cwd, "folder" .. n)) do n = n + 1 end
      local ok = pcall(fs.makeDir, fs.combine(cwd, "folder" .. n))
      refresh()
      if wasRenaming then
        status = "rename cancelled"
      else
        status = ok and ("made folder" .. n) or "mkdir failed"
      end
      if wasRenaming and ok then status = "made folder" .. n end
      return true
    end
    if cy == 2 and cx <= 6 then -- [..] up
      if cwd ~= "/" then
        cwd = normDir(fs.getDir(cwd))
        selected = 0
        refresh()
        if wasRenaming then status = "rename cancelled" end
        return true
      end
      if wasRenaming then status = "rename cancelled" return true end
      return false
    end
    if cy == h - 3 then
      if cx >= 2 and cx <= 7 then -- Open
        if wasRenaming then
          -- swallow: cancel only, do not open on the cancelling click
          status = "rename cancelled"
          return true
        end
        openSelected()
        return true
      elseif cx >= 9 and cx <= 13 then -- Del
        if wasRenaming then status = "rename cancelled" return true end
        deleteSelected()
        return true
      elseif cx >= 15 and cx <= 20 then -- Copy
        if wasRenaming then status = "rename cancelled" return true end
        doCopy()
        return true
      elseif cx >= 22 and cx <= 26 then -- Ren
        startRename()
        return true
      elseif cx >= 28 and cx <= 32 then -- New
        if wasRenaming then status = "rename cancelled" return true end
        doNew()
        return true
      end
      if wasRenaming then status = "rename cancelled" return true end
      return false
    end
    local rows = entryRows(h)
    if cy >= 3 and cy <= 2 + rows then
      local idx = scroll + (cy - 2)
      if entries[idx] then
        if wasRenaming then
          -- cancel only, reselect, do not trigger second-click open
          selected = idx
          delArm = false
          status = entries[idx]
          return true
        end
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
    if wasRenaming then status = "rename cancelled" return true end
    return false
  end
}
