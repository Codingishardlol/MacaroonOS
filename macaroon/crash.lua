-- Macaroon OS - crash screen (graceful death)
-- Classic blue screen: error details, crash log append, any-key or
-- 15s auto-reboot. Terminate-proof (pullEventRaw, terminate ignored)
-- so a dying session can't be left in a weird half state.

local Crash = {}

local TIMEOUT = 15

local function logCrash(err, context)
  local ok = pcall(function()
    -- Single line, no newlines: the message is attacker-influenced
    -- (it can contain a whole hostile program's error) and must not
    -- forge extra log lines.
    local clean = string.gsub(tostring(err), "[\r\n]", " ")
    local ctx = string.gsub(tostring(context or "?"), "[\r\n]", " ")
    local line = (os.date and os.date("%Y-%m-%d %H:%M:%S") or "?")
      .. " [" .. ctx .. "] " .. string.sub(clean, 1, 300) .. "\n"
    local h = fs.open("macaroon/crash.log", "a")
    if h then
      h.write(line)
      h.close()
      return
    end
    -- No append mode: read + rewrite.
    local old = ""
    local r = fs.open("macaroon/crash.log", "r")
    if r then
      old = r.readAll() or ""
      r.close()
    end
    local w = fs.open("macaroon/crash.log", "w")
    if w then
      w.write(old .. line)
      w.close()
    end
  end)
  return ok
end

local function version()
  if fs.exists("macaroon/version.lua") then
    local ok, V = pcall(dofile, "macaroon/version.lua")
    if ok and type(V) == "table" and type(V.version) == "string" then
      return V.version
    end
  end
  return "?.?.?"
end

local function wrap(msg, width)
  local lines = {}
  msg = tostring(msg or "unknown error")
  for chunk in string.gmatch(msg, "[^\n]+") do
    while #chunk > width do
      lines[#lines + 1] = string.sub(chunk, 1, width)
      chunk = string.sub(chunk, width + 1)
    end
    lines[#lines + 1] = chunk
  end
  if #lines == 0 then lines[1] = "unknown error" end
  return lines
end

-- Shows the screen and only returns via reboot (which never returns).
function Crash.fatal(err, context)
  logCrash(err, context)
  local base = term.current()
  if term.native then
    local ok, native = pcall(term.native)
    if ok and native then base = native end
  end
  term.redirect(base)
  local w, h = term.getSize()
  term.setBackgroundColor(colours.blue)
  term.setTextColor(colours.white)
  term.clear()
  term.setCursorPos(3, 2)
  term.write(":(")
  term.setCursorPos(3, 4)
  term.write("Macaroon OS ran into a problem.")
  local elines = wrap(err, w - 6)
  for i = 1, math.min(#elines, 4) do
    term.setCursorPos(3, 5 + i)
    term.write(string.sub(elines[i], 1, w - 4))
  end
  local id = "?"
  if os.getComputerID then
    local ok, cid = pcall(os.getComputerID)
    if ok then id = tostring(cid) end
  end
  term.setCursorPos(3, h - 4)
  term.write("macaroon OS v" .. version() .. " | PC " .. id
    .. " | see macaroon/crash.log")
  term.setCursorPos(3, h - 2)
  term.write("Press any key to reboot (auto in " .. TIMEOUT .. "s).")
  local rebootTimer = os.startTimer(TIMEOUT)
  while true do
    local event, p1 = os.pullEventRaw()
    if event == "timer" and p1 == rebootTimer then
      os.reboot()
      return
    elseif event == "key" or event == "char"
        or event == "mouse_click" or event == "mouse_up" then
      os.reboot()
      return
    end
    -- everything else (incl. terminate) ignored
  end
end

return Crash
