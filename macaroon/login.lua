-- Macaroon OS - login screen (secure boot gate)
-- Fullscreen prompt run by startup.lua before the desktop.
-- Returns username on success, or nil + reason ("shutdown", "locked").

local Login = {}

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

  term.setBackgroundColor(colours.black)
  term.setTextColor(colours.white)
  term.clear()

  local attempts = 0
  while attempts < 5 do
    term.setCursorPos(1, 1)
    term.clear()
    term.setTextColor(colours.cyan)
    print("  macaroon OS - login")
    term.setTextColor(colours.white)
    print("")
    for i, n in ipairs(names) do
      print("  [" .. i .. "] " .. n)
    end
    print("")
    print("  Type 'shutdown' as user to power off.")
    print("")
    write("  User: ")
    local who = read()
    who = string.gsub(who or "", "^%s*(.-)%s*$", "%1")
    if who == "shutdown" or who == "off" then
      return nil, "shutdown"
    end
    -- Allow number selection
    local idx = tonumber(who)
    if idx and names[idx] then
      who = names[idx]
    end
    write("  Password: ")
    local pw = read("*")
    if UserLib.verify(who, pw or "") then
      return who
    end
    attempts = attempts + 1
    term.setTextColor(colours.red)
    print("  Wrong user or password. (" .. attempts .. "/5)")
    term.setTextColor(colours.white)
    sleep(1)
  end
  return nil, "locked"
end

return Login
