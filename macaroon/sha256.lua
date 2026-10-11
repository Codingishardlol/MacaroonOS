-- Macaroon OS - SHA256 (pure Lua, no bit32 / 5.3 ops)
-- Double-safe: all intermediates stay below 2^33 so CraftOS numbers stay exact.
-- Used for salted password hashes. Not audited crypto, but real SHA256.

local SHA = {}

local MOD32 = 4294967296

local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function bxor(a, b)
  local r, m = 0, 1
  while a > 0 or b > 0 do
    local ba, bb = a % 2, b % 2
    if ba ~= bb then r = r + m end
    a = (a - ba) / 2
    b = (b - bb) / 2
    m = m * 2
  end
  return r
end

local function band(a, b)
  local r, m = 0, 1
  while a > 0 and b > 0 do
    local ba, bb = a % 2, b % 2
    if ba == 1 and bb == 1 then r = r + m end
    a = (a - ba) / 2
    b = (b - bb) / 2
    m = m * 2
  end
  return r
end

local function rrot(a, n)
  n = n % 32
  if n == 0 then return a % MOD32 end
  local hi = math.floor(a / (2 ^ n))
  local low = a % (2 ^ n)
  return hi + low * (2 ^ (32 - n))
end

local function shr(a, n)
  return math.floor(a / (2 ^ n))
end

local function bnot(a)
  return (MOD32 - 1) - (a % MOD32)
end

local function num2hex(n)
  local s = ""
  for _ = 1, 8 do
    local d = n % 16
    if d < 10 then
      s = string.char(48 + d) .. s
    else
      s = string.char(87 + d) .. s
    end
    n = math.floor(n / 16)
  end
  return s
end

-- Returns 64-char lowercase hex digest of string msg.
function SHA.digest(msg)
  msg = tostring(msg or "")
  local len = #msg
  local bitlenLow = (len * 8) % MOD32

  -- Padding: 0x80, zeros, 64-bit big-endian length (high=0, short msgs).
  local padLen = (56 - (len + 1) % 64) % 64
  local bytes = {}
  for i = 1, len do bytes[i] = string.byte(msg, i) end
  bytes[len + 1] = 0x80
  for _ = 1, padLen do bytes[#bytes + 1] = 0 end
  for _ = 1, 4 do bytes[#bytes + 1] = 0 end
  bytes[#bytes + 1] = math.floor(bitlenLow / 16777216) % 256
  bytes[#bytes + 1] = math.floor(bitlenLow / 65536) % 256
  bytes[#bytes + 1] = math.floor(bitlenLow / 256) % 256
  bytes[#bytes + 1] = bitlenLow % 256

  local h0 = 0x6a09e667
  local h1 = 0xbb67ae85
  local h2 = 0x3c6ef372
  local h3 = 0xa54ff53a
  local h4 = 0x510e527f
  local h5 = 0x9b05688c
  local h6 = 0x1f83d9ab
  local h7 = 0x5be0cd19

  local w = {}
  for chunk = 1, #bytes, 64 do
    for i = 0, 15 do
      local j = chunk + i * 4
      w[i + 1] = bytes[j] * 16777216 + bytes[j + 1] * 65536
               + bytes[j + 2] * 256 + bytes[j + 3]
    end
    for i = 17, 64 do
      local a, b, c = w[i - 15], w[i - 2], w[i - 7]
      local s0 = bxor(bxor(rrot(a, 7), rrot(a, 18)), shr(a, 3))
      local s1 = bxor(bxor(rrot(b, 17), rrot(b, 19)), shr(b, 10))
      w[i] = (c + s0 + w[i - 16] + s1) % MOD32
    end

    local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
    for i = 1, 64 do
      local S1 = bxor(bxor(rrot(e, 6), rrot(e, 11)), rrot(e, 25))
      local ch = bxor(band(e, f), band(bnot(e), g))
      local t1 = (h + S1 + ch + K[i] + w[i]) % MOD32
      local S0 = bxor(bxor(rrot(a, 2), rrot(a, 13)), rrot(a, 22))
      local mj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
      local t2 = (S0 + mj) % MOD32
      h, g, f, e, d, c, b, a = g, f, e, (d + t1) % MOD32, c, b, a, (t1 + t2) % MOD32
    end

    h0 = (h0 + a) % MOD32
    h1 = (h1 + b) % MOD32
    h2 = (h2 + c) % MOD32
    h3 = (h3 + d) % MOD32
    h4 = (h4 + e) % MOD32
    h5 = (h5 + f) % MOD32
    h6 = (h6 + g) % MOD32
    h7 = (h7 + h) % MOD32
  end

  return num2hex(h0) .. num2hex(h1) .. num2hex(h2) .. num2hex(h3)
       .. num2hex(h4) .. num2hex(h5) .. num2hex(h6) .. num2hex(h7)
end

return SHA
