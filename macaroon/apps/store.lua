-- Macaroon OS - Store app (install individual programs)
-- Lists macaroon/apps/*.lua from the remote manifest, shows
-- [have]/[get] per entry, downloads single files on click.
-- State in file-scope upvalues (fresh per window via dofile).

local entries = {} -- { path, name, have }
local scroll = 0
local status = "Press List."
local detail = ""
local count = ""
local busy = false

local PREFIX = "macaroon/apps/"

local function shortName(path)
  -- strip "macaroon/apps/" prefix and ".lua" suffix
  return string.sub(path, string.len(PREFIX) + 1, -5)
end

local function refreshHave(e)
  local ok, has = pcall(fs.exists, e.path)
  e.have = (ok and has) and true or false
end

local function doList()
  if busy then return end
  busy = true
  status = "Loading..."
  detail = ""
  if not fs.exists("macaroon/updater.lua") then
    status = "Updater missing."
    busy = false
    return
  end
  local okU, Updater = pcall(dofile, "macaroon/updater.lua")
  if not okU or type(Updater) ~= "table" or type(Updater.getFileList) ~= "function" then
    status = "Updater load failed."
    busy = false
    return
  end
  local ok, list, err = pcall(Updater.getFileList)
  if not ok then
    status = "List failed"
    detail = tostring(list):sub(1, 30)
    busy = false
    return
  end
  if type(list) ~= "table" then
    status = "List failed"
    detail = tostring(err or "?"):sub(1, 30)
    busy = false
    return
  end
  entries = {}
  for _, path in ipairs(list) do
    if type(path) == "string" and string.match(path, "^macaroon/apps/.+%.lua$")
      and not string.find(path, "%.%.") then -- traversal never listed
      local e = { path = path, name = shortName(path), have = false }
      refreshHave(e)
      entries[#entries + 1] = e
    end
  end
  table.sort(entries, function(a, b) return a.name < b.name end)
  scroll = 0
  count = #entries .. " app(s)"
  if #entries == 0 then
    status = "No apps found."
  else
    status = "Pick an app."
  end
  busy = false
end

local function doGet(e)
  if busy or not e then return end
  busy = true
  status = "Getting " .. e.name .. "..."
  detail = ""
  local baseURL = nil
  local safePath = nil
  local okU, Updater = pcall(dofile, "macaroon/updater.lua")
  if okU and type(Updater) == "table" then
    if type(Updater.getBaseURL) == "function" then
      local okB, u = pcall(Updater.getBaseURL)
      if okB and type(u) == "string" and u ~= "" then
        baseURL = u
      end
    end
    if type(Updater.safePath) == "function" then
      safePath = Updater.safePath
    end
  end
  -- Belt and braces: entries come from a remote manifest, so re-validate
  -- here too (dot-dot like macaroon/apps/../../startup.lua must die).
  local okS = false
  if safePath then
    local okC, res = pcall(safePath, e.path)
    okS = okC and res
  else
    okS = type(e.path) == "string"
      and string.sub(e.path, 1, 1) ~= "/"
      and not string.find(e.path, "%.%.")
      and string.sub(e.path, -4) == ".lua"
  end
  if not okS then
    status = "Get failed"
    detail = "blocked path"
    busy = false
    return
  end
  if not baseURL then
    status = "Get failed"
    detail = "no base URL"
    busy = false
    return
  end
  if not http or not http.get then
    status = "Get failed"
    detail = "HTTP disabled"
    busy = false
    return
  end
  local okH, res, herr = pcall(http.get, baseURL .. "/" .. e.path)
  if not okH then
    status = "Get failed"
    detail = tostring(res):sub(1, 30)
    busy = false
    return
  end
  if res == nil then
    status = "Get failed"
    detail = tostring(herr or "?"):sub(1, 30)
    busy = false
    return
  end
  local okR, data = pcall(res.readAll)
  pcall(res.close)
  if not okR or type(data) ~= "string" or #data == 0 then
    status = "Get failed"
    detail = "empty file"
    busy = false
    return
  end
  if #data > 262144 then
    status = "Get failed"
    detail = "file too big"
    busy = false
    return
  end
  local okD, dir = pcall(fs.getDir, e.path)
  if okD and dir ~= "" and dir ~= "." then
    pcall(fs.makeDir, dir)
  end
  local okO, out = pcall(fs.open, e.path, "w")
  if not okO or not out then
    status = "Get failed"
    detail = "cannot write"
    busy = false
    return
  end
  local okW = pcall(out.write, data)
  pcall(out.close)
  if not okW then
    status = "Get failed"
    detail = "cannot write"
    busy = false
    return
  end
  refreshHave(e)
  status = "got " .. e.name
  detail = "reboot to use"
  busy = false
end

-- Never throws: every external call above is pcall-guarded.
local function safeCall(fn)
  local ok, err = pcall(fn)
  if not ok then
    busy = false
    status = "error"
    detail = tostring(err):sub(1, 30)
  end
end

safeCall(doList) -- auto-list on open; button re-tries offline

return {
  title = "Store",
  width = 38,
  height = 14,

  draw = function(win)
    local w, h = win.getSize()
    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.black)
    win.clear()
    -- row 1: List button + count
    win.setCursorPos(2, 1)
    if busy then
      win.setBackgroundColor(colours.grey)
    else
      win.setBackgroundColor(colours.blue)
    end
    win.setTextColor(colours.white)
    win.write("[ List ]")
    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.grey)
    win.setCursorPos(12, 1)
    win.write(string.sub(count, 1, w - 12))
    -- list rows 2..h-3
    local top = 2
    local bot = h - 3
    for r = top, bot do
      local e = entries[scroll + (r - top + 1)]
      if e then
        win.setCursorPos(2, r)
        win.setBackgroundColor(colours.white)
        win.setTextColor(colours.black)
        win.write(string.sub(e.name, 1, w - 10))
        win.setCursorPos(w - 7, r)
        if e.have then
          win.setTextColor(colours.grey)
          win.write("[have]")
        else
          win.setBackgroundColor(colours.green)
          win.setTextColor(colours.white)
          win.write("[get] ")
          win.setBackgroundColor(colours.white)
        end
      end
    end
    win.setBackgroundColor(colours.white)
    win.setCursorPos(2, h - 2)
    win.setTextColor(colours.black)
    win.write(string.sub(status, 1, w - 2))
    win.setCursorPos(2, h - 1)
    win.setTextColor(colours.red)
    win.write(string.sub(detail, 1, w - 2))
    win.setCursorPos(2, h)
    win.setTextColor(colours.grey)
    win.write("reboot to appear in Start")
  end,

  onEvent = function(win, event, p1, cx, cy)
    local w, h = win.getSize()
    if event == "mouse_scroll" then
      local top = 2
      local rows = (h - 3) - top + 1
      local max = #entries - rows
      if max < 0 then max = 0 end
      local step = -1
      if p1 == 1 then step = 1 end
      scroll = scroll + step
      if scroll < 0 then scroll = 0 end
      if scroll > max then scroll = max end
      return true
    end
    if event ~= "mouse_click" or not cx or not cy then
      return false
    end
    if cy == 1 and cx >= 2 and cx <= 9 then
      safeCall(doList)
      return true
    end
    local top = 2
    local bot = h - 3
    if cy >= top and cy <= bot then
      local e = entries[scroll + (cy - top + 1)]
      if e then
        if e.have then
          status = "have " .. e.name
          detail = "reboot to use"
        else
          safeCall(function() doGet(e) end)
        end
        return true
      end
    end
    return false
  end
}
