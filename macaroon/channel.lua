-- Macaroon OS release channel: "stable" (main branch) or "beta".
-- Stored in macaroon/channel.txt (a data file: never in the manifest).
-- Missing or garbage file means "stable".

local Channel = {}

local PATH = "macaroon/channel.txt"
local BRANCH = { stable = "main", beta = "beta" }

local function trim(s)
  return string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")
end

function Channel.get()
  if not fs.exists(PATH) then return "stable" end
  local h = fs.open(PATH, "r")
  if not h then return "stable" end
  local v = string.lower(trim(h.readAll() or ""))
  h.close()
  if v == "beta" then return "beta" end
  return "stable"
end

function Channel.set(ch)
  if ch ~= "stable" and ch ~= "beta" then return false end
  local dir = fs.getDir(PATH)
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
  local h = fs.open(PATH, "w")
  if not h then return false end
  h.write(ch)
  h.close()
  return true
end

function Channel.branch(ch)
  if ch == "beta" then return "beta" end
  return "main"
end

-- Branch-aware base URL: takes a stored root (update_url.txt or the
-- fallback, which may point at either branch or a custom fork) and
-- returns it pointed at the given channel's branch.
function Channel.baseFor(ch, base)
  local branch = BRANCH[ch] or "main"
  base = trim(base)
  if string.sub(base, -1) == "/" then
    base = string.sub(base, 1, -2)
  end
  local root = string.match(base, "^(.*)/[^/]+$")
  if root and root ~= "" then
    local tail = string.match(base, "/([^/]+)$")
    if tail == "main" or tail == "beta" or tail == "master" then
      base = root
    end
  end
  return base .. "/" .. branch
end

return Channel
