-- Macaroon OS - shell API bootstrap
-- The CraftOS `shell` API is not a true global: rom shell.lua builds a
-- local table and injects it only into programs IT launches. Our
-- startup.lua isn't launched by a shell, so `shell` is nil and the
-- Terminal app (plus anything using shell.run) is dead on arrival.
-- Fix: execute the ROM shell's own definition block (everything above
-- its `local tArgs` REPL driver) with a pre-made table, giving us the
-- genuine, version-matched API. Fails soft: returns false and the OS
-- boots anyway, minus shell-dependent features.

local function bootstrap()
  if type(shell) == "table" and type(shell.run) == "function" then
    return true -- already provided (e.g. launched from a real shell)
  end
  if not fs.exists("/rom/programs/shell.lua") then
    return false, "no rom shell"
  end
  local h = fs.open("/rom/programs/shell.lua", "r")
  if not h then return false, "cannot open rom shell" end
  local src = h.readAll()
  h.close()
  if type(src) ~= "string" then return false, "cannot read rom shell" end
  -- Cut before the REPL driver (`local tArgs = { ... }`); everything
  -- above only DEFINES the API on the local `shell` table.
  local defs = string.match(src, "^(.-)\nlocal tArgs")
  if not defs then return false, "no REPL marker" end
  -- CC:T's definitions open their require helper via a RELATIVE dofile,
  -- which cannot resolve without a shell. Absolute-path it (no-op on
  -- sources that already use an absolute path or a different loader).
  defs = string.gsub(defs, 'dofile%(%"rom/modules/main/cc/require%.lua"%)',
    'dofile("/rom/modules/main/cc/require.lua")', 1)
  local t = { multishell = multishell }
  setmetatable(t, { __index = _G })
  -- NOTE: the ROM chunk declares its own `local shell = {}`, so a
  -- pre-made env table would stay empty. Capture the local instead.
  local fn, err = load(defs .. "\nreturn shell", "shell-bootstrap", "t", t)
  if not fn then return false, "load failed" end
  local ok, captured = pcall(fn)
  if not ok then return false, "defs failed" end
  if type(captured) ~= "table" or type(captured.run) ~= "function" then
    return false, "bad api"
  end
  shell = captured
  -- Sane defaults for a parentless shell, then standard aliases.
  pcall(shell.setDir, "/")
  pcall(shell.setAlias, "ls", "list")
  pcall(shell.setAlias, "dir", "list")
  return true
end

local ok, res, reason = pcall(bootstrap)
if ok and res == true then
  return true
end
return false, reason
