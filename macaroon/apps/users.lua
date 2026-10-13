-- Macaroon OS - Users app (account manager)
-- Lists accounts, add / delete / change password.
-- State in file-scope upvalues (fresh per window via dofile).

local users = {}
local sel = 1
local top = 1
local status = "loaded"
local statusErr = false
local mode = "idle"
local buf = ""
local pendingName = nil
local pendingPw = nil
local confirmDel = false

local MAXROWS = 5
local LIST_Y = 2
local PROMPT_Y = 7
local BTN_Y = 8
local STATUS_Y1 = 9
local STATUS_Y2 = 10
local HINT_Y = 11

local function setStatus(msg, isErr)
  status = tostring(msg or "")
  statusErr = isErr and true or false
end

local function loadUsersLib()
  local ok, UL = pcall(dofile, "macaroon/users.lua")
  if ok and type(UL) == "table" then
    return UL
  end
  return nil
end

local function ensureVisible()
  if sel < 1 then sel = 1 end
  if #users > 0 and sel > #users then sel = #users end
  if #users <= MAXROWS then
    top = 1
    return
  end
  if sel < top then top = sel end
  if sel > top + MAXROWS - 1 then top = sel - MAXROWS + 1 end
  if top < 1 then top = 1 end
  local maxTop = #users - MAXROWS + 1
  if top > maxTop then top = maxTop end
end

local function refresh()
  local UL = loadUsersLib()
  if not UL then
    users = {}
    sel = 1
    top = 1
    return false
  end
  local ok, list = pcall(UL.list)
  if ok and type(list) == "table" then
    users = list
  else
    users = {}
  end
  if sel < 1 then sel = 1 end
  if #users > 0 and sel > #users then sel = #users end
  ensureVisible()
  return true
end

refresh()

local function selectedName()
  if type(users) ~= "table" then return nil end
  local n = users[sel]
  if type(n) == "string" then return n end
  return nil
end

local function cancelInput(msg)
  mode = "idle"
  buf = ""
  pendingName = nil
  pendingPw = nil
  if msg then setStatus(msg, false) end
end

local function doCreate(name, pw)
  local UL = loadUsersLib()
  if not UL then
    setStatus("users lib missing", true)
    cancelInput()
    -- keep message, mode already idle
    setStatus("users lib missing", true)
    return
  end
  local ok, res, err = pcall(UL.create, name, pw)
  if ok and res == true then
    local wasPass = (mode == "chgPw2")
    cancelInput()
    refresh()
    -- point selection at the new/changed name
    if type(users) == "table" then
      for i, n in ipairs(users) do
        if n == name then sel = i break end
      end
    end
    ensureVisible()
    if wasPass then
      setStatus("pw changed: " .. name, false)
    else
      setStatus("added " .. name, false)
    end
  else
    local msg = "create failed"
    if ok then
      if type(err) == "string" and #err > 0 then msg = err end
    else
      msg = tostring(res or "error")
    end
    setStatus(string.sub(msg, 1, 28), true)
    -- stay in first pw step so user can retry
    if mode == "addPw2" then
      mode = "addPw1"
      buf = ""
      pendingPw = nil
    elseif mode == "chgPw2" then
      mode = "chgPw1"
      buf = ""
      pendingPw = nil
    end
  end
end

local function handleEnter()
  if mode == "addName" then
    if buf == "" then
      setStatus("name empty", true)
      return
    end
    pendingName = buf
    buf = ""
    pendingPw = nil
    mode = "addPw1"
    setStatus("pw for " .. pendingName, false)
  elseif mode == "addPw1" then
    pendingPw = buf
    buf = ""
    mode = "addPw2"
    setStatus("repeat pw", false)
  elseif mode == "addPw2" then
    if buf ~= pendingPw then
      setStatus("passwords differ", true)
      mode = "addPw1"
      buf = ""
      pendingPw = nil
      return
    end
    local pw = buf
    local name = pendingName
    doCreate(name, pw)
  elseif mode == "chgPw1" then
    pendingPw = buf
    buf = ""
    mode = "chgPw2"
    setStatus("repeat new pw", false)
  elseif mode == "chgPw0" then
    -- Prove the current password before touching anything.
    local name = selectedName()
    if not name then
      setStatus("no user", true)
      cancelInput()
      return
    end
    local UL = loadUsersLib()
    local okV, good = UL and pcall(UL.verify, name, buf)
    buf = ""
    if not (okV and good) then
      setStatus("wrong password", true)
      cancelInput("wrong password")
      return
    end
    pendingPw = nil
    mode = "chgPw1"
    setStatus("new pw for " .. name, false)
  elseif mode == "chgPw2" then
    if buf ~= pendingPw then
      setStatus("passwords differ", true)
      mode = "chgPw1"
      buf = ""
      pendingPw = nil
      return
    end
    local name = selectedName()
    if not name then
      setStatus("no user", true)
      cancelInput()
      return
    end
    doCreate(name, buf)
  end
end

local function handleDel()
  refresh()
  local name = selectedName()
  if not name then
    confirmDel = false
    setStatus("no user", true)
    return
  end
  if #users <= 1 then
    confirmDel = false
    setStatus("cannot remove last", true)
    return
  end
  if not confirmDel then
    confirmDel = true
    setStatus("click Del again", false)
    return
  end
  local UL = loadUsersLib()
  if not UL then
    confirmDel = false
    setStatus("users lib missing", true)
    return
  end
  local ok, res = pcall(UL.remove, name)
  if ok and res then
    confirmDel = false
    refresh()
    if sel > #users then sel = #users end
    if sel < 1 then sel = 1 end
    ensureVisible()
    setStatus("removed " .. name, false)
  else
    confirmDel = false
    setStatus("remove failed", true)
  end
end

return {
  title = "Users",
  width = 30,
  height = 13,

  draw = function(win)
    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.black)
    win.clear()
    -- header
    win.setCursorPos(2, 1)
    local n = 0
    if type(users) == "table" then n = #users end
    win.write("Users (" .. tostring(n) .. ")")
    -- list rows
    for r = 1, MAXROWS do
      local y = LIST_Y + r - 1
      local idx = top + r - 1
      local name = nil
      if type(users) == "table" then name = users[idx] end
      win.setCursorPos(2, y)
      if type(name) == "string" then
        local label = string.sub(name, 1, 26)
        if idx == sel then
          win.setBackgroundColor(colours.blue)
          win.setTextColor(colours.white)
          win.write("> " .. label)
          -- pad to clear leftover chars
          local pad = 26 - #label
          if pad > 0 then win.write(string.rep(" ", pad)) end
          win.setBackgroundColor(colours.white)
          win.setTextColor(colours.black)
        else
          win.setBackgroundColor(colours.white)
          win.setTextColor(colours.black)
          win.write("  " .. label)
        end
      else
        win.setBackgroundColor(colours.white)
        win.setTextColor(colours.grey)
        if r == 1 and n == 0 then
          win.write("(no users)")
        else
          win.write("")
        end
        win.setTextColor(colours.black)
      end
    end
    -- prompt / input line
    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.black)
    win.setCursorPos(2, PROMPT_Y)
    if mode == "addName" then
      win.write(string.sub("Name: " .. buf .. "_", 1, 28))
    elseif mode == "addPw1" then
      win.write(string.sub("Pw: " .. string.rep("*", #buf) .. "_", 1, 28))
    elseif mode == "addPw2" then
      win.write(string.sub("Repeat: " .. string.rep("*", #buf) .. "_", 1, 28))
    elseif mode == "chgPw0" then
      win.write(string.sub("Current: " .. string.rep("*", #buf) .. "_", 1, 28))
    elseif mode == "chgPw1" then
      win.write(string.sub("New pw: " .. string.rep("*", #buf) .. "_", 1, 28))
    elseif mode == "chgPw2" then
      win.write(string.sub("Repeat: " .. string.rep("*", #buf) .. "_", 1, 28))
    else
      local cur = selectedName()
      if confirmDel then
        win.setTextColor(colours.red)
        win.write("Sure? Del again!")
      elseif type(cur) == "string" then
        win.setTextColor(colours.grey)
        win.write(string.sub("Sel: " .. cur, 1, 28))
      else
        win.setTextColor(colours.grey)
        win.write("click row to select")
      end
      win.setTextColor(colours.black)
    end
    -- buttons
    win.setCursorPos(2, BTN_Y)
    win.setBackgroundColor(colours.grey)
    win.setTextColor(colours.white)
    win.write("[ Add ]")
    win.setCursorPos(10, BTN_Y)
    if confirmDel then
      win.setBackgroundColor(colours.red)
    else
      win.setBackgroundColor(colours.grey)
    end
    win.setTextColor(colours.white)
    win.write("[ Del ]")
    win.setCursorPos(18, BTN_Y)
    win.setBackgroundColor(colours.grey)
    win.setTextColor(colours.white)
    win.write("[ Pass ]")
    win.setBackgroundColor(colours.white)
    -- status (2 lines)
    win.setBackgroundColor(colours.white)
    if statusErr then
      win.setTextColor(colours.red)
    else
      win.setTextColor(colours.grey)
    end
    win.setCursorPos(2, STATUS_Y1)
    win.write(string.sub(tostring(status or ""), 1, 28))
    if #tostring(status or "") > 28 then
      win.setCursorPos(2, STATUS_Y2)
      win.write(string.sub(tostring(status or ""), 29, 56))
    else
      win.setCursorPos(2, STATUS_Y2)
      win.write("")
    end
    -- hint
    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.grey)
    win.setCursorPos(2, HINT_Y)
    if mode == "idle" then
      win.write("Del needs 2 clicks")
    else
      win.write("Enter ok, Esc cancel")
    end
    win.setCursorPos(2, 12)
    win.write("")
    win.setBackgroundColor(colours.white)
    win.setTextColor(colours.black)
  end,

  onEvent = function(win, event, p1, cx, cy)
    if event == "char" then
      if mode == "idle" then return false end
      if type(p1) ~= "string" or #p1 ~= 1 then return false end
      local cap = 32
      if mode == "addName" then cap = 16 end
      if #buf >= cap then return false end
      buf = buf .. p1
      return true
    elseif event == "key" then
      if p1 == 1 then -- Esc
        if mode ~= "idle" then
          cancelInput("cancelled")
          return true
        end
        if confirmDel then
          confirmDel = false
          setStatus("cancelled", false)
          return true
        end
        return false
      elseif p1 == 14 then -- Backspace
        if mode == "idle" then return false end
        if #buf > 0 then
          buf = string.sub(buf, 1, #buf - 1)
          return true
        end
        return false
      elseif p1 == 28 then -- Enter
        if mode == "idle" then return false end
        local ok = pcall(handleEnter)
        if not ok then
          cancelInput("error")
          setStatus("error", true)
        end
        return true
      end
      return false
    elseif event == "mouse_click" then
      if mode ~= "idle" then return false end
      if not cx or not cy then return false end
      -- user rows
      if cy >= LIST_Y and cy < LIST_Y + MAXROWS then
        local idx = top + (cy - LIST_Y)
        if type(users) == "table" and idx >= 1 and idx <= #users then
          if sel ~= idx then
            sel = idx
            ensureVisible()
            confirmDel = false
            return true
          end
          if confirmDel then
            confirmDel = false
            setStatus("cancelled", false)
            return true
          end
          return false
        end
        return false
      end
      -- buttons
      if cy == BTN_Y then
        if cx >= 2 and cx <= 8 then
          mode = "addName"
          buf = ""
          pendingName = nil
          pendingPw = nil
          confirmDel = false
          setStatus("enter name, Enter ok", false)
          return true
        elseif cx >= 10 and cx <= 16 then
          local ok = pcall(handleDel)
          if not ok then setStatus("remove failed", true) end
          return true
        elseif cx >= 18 and cx <= 25 then
          local name = selectedName()
          if not name then
            setStatus("no user", true)
            return true
          end
          mode = "chgPw0"
          buf = ""
          pendingPw = nil
          confirmDel = false
          setStatus("current pw for " .. name, false)
          return true
        end
      end
      return false
    end
    return false
  end
}
