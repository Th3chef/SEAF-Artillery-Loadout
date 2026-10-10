-- HD2-Addon: mods/chef/seaf_artillery_loadout
-- SEAF Artillery Loadout for Helldivers 2 (Bingus Shared Loader v19+ addon).
-- Once the SEAF Artillery objective is done, the shells still loaded in the artillery are shown as icons, in firing
-- order, right of the SEAF Artillery stratagem while the stratagem list is open; the next shell is marked.
-- It also has the game redo the row's "SEAF ARTILLERY: <shell>" name when the next shell changes: the game only sets
-- that name when the row gets a new stratagem, so after a shot it can keep naming a shell that was already fired.
-- That is its only write to game memory (one value in the HUD's own row, which the game sets back on its next
-- update); everything else is read only. It finds the game's addresses again by itself after a game update.
local VERSION = '1.0.0'
local TEST_BUILD = false      -- numbered test builds: the log goes to Logs\test
local TESTER = false          -- the release's Tester build: more detail in the log

if rawget(_G, 'ChefSeafArtilleryLoadout') then return end
local SS = { version = VERSION, status = 'starting' }
rawset(_G, 'ChefSeafArtilleryLoadout', SS)

local ffi = require('ffi')
local bit = require('bit')
local SR = rawget(_G, 'stingray')

-- ======================================================================================================
-- Windows API (private names, so they never clash with another mod's declarations)
-- ======================================================================================================
for _, d in ipairs({
  'void *SsGetModuleHandleA(const char *name) __asm__("GetModuleHandleA");',
  'void *SsGetCurrentProcess(void) __asm__("GetCurrentProcess");',
  'int SsReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *done) __asm__("ReadProcessMemory");',
  'int SsWriteProcessMemory(void *process, void *address, const void *buffer, size_t size, size_t *done) __asm__("WriteProcessMemory");',
  'int SsCreateDirectoryA(const char *path, void *security) __asm__("CreateDirectoryA");',
  'int SsQueryPerformanceCounter(int64_t *count) __asm__("QueryPerformanceCounter");',
  'int SsQueryPerformanceFrequency(int64_t *freq) __asm__("QueryPerformanceFrequency");',
}) do pcall(ffi.cdef, d) end
local K32 = ffi.load('kernel32')
local PROCESS = K32.SsGetCurrentProcess()

-- ======================================================================================================
-- Log: Logs\SeafArtilleryLoadout.log (numbered test builds: Logs\test\...)
-- ======================================================================================================
local LOADER = rawget(_G, 'CowboyBingusModLoader')
local V19 = type(LOADER) == 'table' and type(rawget(LOADER, 'capabilities')) == 'table'
  and type(rawget(LOADER, 'after_startup')) == 'function'
local LOGDIR
do
  local dir = type(LOADER) == 'table' and type(rawget(LOADER, 'log_directory')) == 'string' and LOADER.log_directory or nil
  if not dir then
    local base = os.getenv('LOCALAPPDATA')
    dir = base and (base .. '\\CowboyBingus\\Helldivers2\\Logs') or nil
  end
  if dir and TEST_BUILD then
    pcall(K32.SsCreateDirectoryA, dir .. '\\test', nil)
    local f = io.open(dir .. '\\test\\SeafArtilleryLoadout.log', 'a')
    if f then f:close(); dir = dir .. '\\test' end
  end
  LOGDIR = dir
end
local LOGNAME = 'SeafArtilleryLoadout'
local session = { started = os.date('%Y-%m-%d %H:%M:%S'), events = {} }
local dirty_log = true
local function event(msg)
  local e = session.events
  e[#e + 1] = os.date('%H:%M:%S ') .. msg
  if #e > 400 then table.remove(e, 1) end
  dirty_log = true
end

-- ======================================================================================================
-- Memory: ReadProcessMemory on our own process (a bad address fails cleanly instead of crashing) into one
-- reusable buffer
-- ======================================================================================================
local stats = { reads = 0, read_fails = 0, frames = 0, redraws = 0, writes = 0 }
local BUF_SIZE = 65536
local BUF = ffi.new('uint8_t[?]', BUF_SIZE)
local DONE = ffi.new('size_t[1]')
local PVOID = ffi.typeof('const void *')
local PU32, PF32 = ffi.typeof('const uint32_t *'), ffi.typeof('const float *')
local cast = ffi.cast
local function fetch(addr, n)
  if type(addr) ~= 'number' or addr < 65536 or addr >= 140737488355328 or n <= 0 then return false end
  if n > BUF_SIZE then
    while BUF_SIZE < n do BUF_SIZE = BUF_SIZE * 2 end
    BUF = ffi.new('uint8_t[?]', BUF_SIZE)
  end
  stats.reads = stats.reads + 1
  if K32.SsReadProcessMemory(PROCESS, cast(PVOID, addr), BUF, n, DONE) == 0 or DONE[0] ~= n then
    stats.read_fails = stats.read_fails + 1
    return false
  end
  return true
end
local function b8(o) return BUF[o] end
local function b32(o) return tonumber(cast(PU32, BUF + o)[0]) end
local function bf32(o)
  local v = tonumber(cast(PF32, BUF + o)[0])
  if v == nil or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end
local function bptr(o)
  local lo, hi = b32(o), b32(o + 4)
  local p = hi * 4294967296 + lo
  if p < 65536 or p >= 140737488355328 then return nil end
  return p
end
local function bstr(o, n) return ffi.string(BUF + o, n) end
local function read_string(addr, n) return fetch(addr, n) and bstr(0, n) or nil end
local function read_ptr(addr) return fetch(addr, 8) and bptr(0) or nil end
local WBUF = ffi.new('uint32_t[1]')
local PWVOID = ffi.typeof('void *')
local function write_u32(addr, v)        -- the name fix's one write (fails cleanly on a bad address)
  if type(addr) ~= 'number' or addr < 65536 or addr >= 140737488355328 then return false end
  WBUF[0] = v
  stats.writes = stats.writes + 1
  return K32.SsWriteProcessMemory(PROCESS, cast(PWVOID, addr), WBUF, 4, DONE) ~= 0 and DONE[0] == 4
end

-- ======================================================================================================
-- Finding the game's addresses (the pattern list is further down)
-- ======================================================================================================
local function su32(t, o) local a, b, c, d = t:byte(o + 1, o + 4); return a + b * 256 + c * 65536 + d * 16777216 end
local function si32(t, o) local v = su32(t, o); return v >= 2147483648 and v - 4294967296 or v end
local function compile(p)
  local segs, cur_off, cur = {}, nil, {}
  for k = 0, #p / 2 - 1 do
    local h = p:sub(2 * k + 1, 2 * k + 2)
    if h == '??' then
      if cur_off then segs[#segs + 1] = { cur_off, table.concat(cur) }; cur_off, cur = nil, {} end
    else
      cur_off = cur_off or k
      cur[#cur + 1] = string.char(tonumber(h, 16))
    end
  end
  if cur_off then segs[#segs + 1] = { cur_off, table.concat(cur) } end
  local anchor = 1
  for j = 2, #segs do if #segs[j][2] > #segs[anchor][2] then anchor = j end end
  return segs, anchor, #p / 2
end
local function find_all(text, p, limit)
  local segs, anchor, n = compile(p)
  local a = segs[anchor]
  local init, out = 1, {}
  while #out < (limit or 16) do
    local s = string.find(text, a[2], init, true)
    if not s then break end
    local start = s - 1 - a[1]
    local ok = start >= 0 and start + n <= #text
    if ok then
      for j, seg in ipairs(segs) do
        if j ~= anchor and text:sub(start + seg[1] + 1, start + seg[1] + #seg[2]) ~= seg[2] then ok = false; break end
      end
    end
    if ok then out[#out + 1] = start end
    init = s + 1
  end
  return out
end
local function module_info(module)
  local b = ffi.cast('uint8_t *', module)
  local function r32(p) return tonumber(ffi.cast('uint32_t *', p)[0]) end
  local function r16(p) return tonumber(ffi.cast('uint16_t *', p)[0]) end
  local pe = r32(b + 0x3c)
  local stamp, image = r32(b + pe + 8), r32(b + pe + 24 + 56)
  local count, optsize = r16(b + pe + 6), r16(b + pe + 20)
  local sec = b + pe + 24 + optsize
  local code
  for i = 0, count - 1 do
    local s = sec + 40 * i
    local vsize, rva, flags = r32(s + 8), r32(s + 12), r32(s + 36)
    if bit.band(flags, 0x20000000) ~= 0 and vsize > 0x100000 and not code then code = { rva = rva, size = vsize } end
  end
  return { base = tonumber(ffi.cast('uintptr_t', module)), stamp = stamp, image = image, code = code }
end
local function code_text(info)          -- read into its own buffer, so the 64 KiB read buffer never grows
  local n = info.code.size
  local tmp = ffi.new('uint8_t[?]', n)
  stats.reads = stats.reads + 1
  local ok = K32.SsReadProcessMemory(PROCESS, cast(PVOID, info.base + info.code.rva), tmp, n, DONE) ~= 0 and DONE[0] == n
  assert(ok, 'cannot read the game code')
  return ffi.string(tmp, n)
end

-- ======================================================================================================
-- Where the game keeps things: code patterns ('??' = any byte), each item read out of every place its pattern
-- matches (all places must agree). An item is a RIP-relative address (rip) or a number in the code.
-- ======================================================================================================
local P = {
  -- the artillery's shell racks (component manager: count +8; entities +0x38; networked state records +0x50)
  rack = { { p = '488b2d????????0f84????????448b4d2833c9448b5530', at = 3, rip = true },
           { p = '4c8b1d????????0f84????????48895c2430', at = 3, rip = true } },
  -- the projectile settings by type (array of pointers; an image-relative address in the code)
  proj = { { p = '488bcee8????????85c0740d8bc0498b84c5????????8b7804', at = 18 } },
  -- the HUD manager, and the stratagem list inside it
  hud = { { p = 'c780????????01000000488b0d????????4885c9', at = 13, rip = true } },
  hud_a = { { p = '488d8f????????0f28cfe8????????0f28cf488d8f58020000', at = 3 } },
  hud_b = { { p = '488d8e????????4889ac2480000000448bc3e8', at = 3 } },
  hud_c = { { p = '498d8e????????448bc5410f28c8e8????????', at = 3 } },
  open = { { p = '410fb68e????????0fb6c184c974204138b6????????', at = 4 } },
  rowbase = { { p = '488dbe????????4c8db6????????41bc10000000', at = 10 } },
  -- the name fix (optional): where the game's row update keeps the row's stratagem id, read as the old id and then
  -- overwritten with the new one (the name is only redone when they differ); both offsets must agree
  rowid_r = { { p = '418b87????????4b8d0c764c8b55??4803c98945??418b94ca????????418997????????', at = 3 } },
  rowid_w = { { p = '418b87????????4b8d0c764c8b55??4803c98945??418b94ca????????418997????????', at = 32 } },
}
local OPTIONAL = { rowid_r = true, rowid_w = true }
local P_ORDER = { 'rack', 'proj', 'hud', 'hud_a', 'hud_b', 'hud_c', 'open', 'rowbase', 'rowid_r', 'rowid_w' }
-- what the 2026-09-24 build had (a cross-check: the log says what moved)
local KNOWN = { rack = 0x3326710, proj = 0x37c7670, hud = 0x346d538, hud_a = 0x24e340, hud_b = 0x146dc0,
  hud_c = 0x1040, open = 0x38769, rowbase = 0x110, rowid_r = 0x374c, rowid_w = 0x374c }
local CACHE = LOGDIR and (LOGDIR .. '\\' .. LOGNAME .. '.cache') or nil

local function cache_load()
  if not CACHE then return nil end
  local f = io.open(CACHE, 'r'); if not f then return nil end
  local s = f:read('*a'); f:close()
  local fn = loadstring('return ' .. s)
  if not fn then return nil end
  setfenv(fn, {})
  local ok, t = pcall(fn)
  return ok and type(t) == 'table' and t or nil
end
local function cache_save(key, found)
  if not CACHE then return end
  local f = io.open(CACHE, 'w'); if not f then return end
  local t = {}
  for _, k in ipairs(P_ORDER) do t[#t + 1] = string.format('%s=%d', k, found[k] or -1) end
  f:write(string.format('{key=%q,%s}', key, table.concat(t, ','))); f:close()
end

local L
local function resolve()
  local t0 = os.clock()
  local gmod = K32.SsGetModuleHandleA('game.dll')
  if gmod == nil then error('game.dll not loaded', 0) end
  local G = module_info(gmod)
  assert(G.code, 'no code section')
  local key = string.format('%08x-%08x-%08x', G.stamp, G.image, G.code.size)
  local found, how
  local c = cache_load()
  if c and c.key == key then
    found, how = {}, 'cached for this game build'
    for _, k in ipairs(P_ORDER) do
      if type(c[k]) ~= 'number' then found = nil; break end
      found[k] = c[k]
    end
  end
  if not found then
    local text = code_text(G)
    local why, moved = {}, {}
    found = {}
    for _, name in ipairs(P_ORDER) do
      local val, disagree = nil, false
      for _, p in ipairs(P[name]) do
        for _, o in ipairs(find_all(text, p.p)) do
          local v = p.rip and (G.code.rva + o + p.at + 4 + si32(text, o + p.at)) or su32(text, o + p.at)
          if val and val ~= v then disagree = true end
          val = val or v
        end
      end
      if OPTIONAL[name] and (not val or disagree) then
        moved[#moved + 1] = name .. (val and ' disagrees (name fix off)' or ' not found (name fix off)')
      elseif not val then why[#why + 1] = name .. ' not found'
      elseif disagree then why[#why + 1] = name .. ': its places disagree'
      else
        found[name] = val
        if KNOWN[name] ~= val then moved[#moved + 1] = string.format('%s %x -> %x', name, KNOWN[name], val) end
      end
    end
    text = nil
    collectgarbage()
    if #why > 0 then error(table.concat(why, '; '), 0) end
    -- plausibility: the offsets inside the HUD are small, the open flag sits after the list
    if found.hud_a + found.hud_b > 0x1000000 or found.open < found.hud_c or found.rowbase > 0x1000 then error('layout not plausible', 0) end
    cache_save(key, found)
    how = #moved == 0 and 'found in the game code (same as the September 2026 build)'
      or ('found in the game code (new game build; moved: ' .. table.concat(moved, ', ') .. ')')
  end
  local A = {}
  for k, v in pairs(found) do if v ~= -1 then A[k] = v end end
  for _, k in ipairs({ 'rack', 'proj', 'hud' }) do A[k] = G.base + A[k] end
  session.layout = how
  session.scan_seconds = os.clock() - t0
  return A
end

-- ======================================================================================================
-- The shell types. A loaded shell is a projectile type; the projectile's settings carry its display name's string
-- ids (+4 "SEAF ARTILLERY: EXPLOSIVE", +8 "SEAF Artillery: Explosive"), which tell the shell types apart.
-- ======================================================================================================
local KINDS = {
  { id = 'explosive', name = 'Explosive', ids = { 0x4cd8b3f6, 0x02694b60 } },
  { id = 'high_yield', name = 'High-Yield Explosive', ids = { 0x67c62820, 0x1e12f273 } },
  { id = 'mini_nuke', name = 'Mini Nuke', ids = { 0x36bc898f, 0xd84656b7 } },
  { id = 'napalm', name = 'Napalm', ids = { 0x38a1a8dc, 0x780ff8a9 } },
  { id = 'smoke', name = 'Smoke', ids = { 0x09687c34, 0xf73287fe } },
  { id = 'static_field', name = 'Static Field', ids = { 0xce97a651, 0x5d4cbc38 } },
  { id = 'unknown', name = 'unknown shell', ids = {} },
}
local KIND = {}
for _, k in ipairs(KINDS) do KIND[k.id] = k end
local KIND_BY_TEXT = {}
for _, k in ipairs(KINDS) do for _, id in ipairs(k.ids) do KIND_BY_TEXT[id] = k end end
--@@ICONS@@
SS.textures = {}
for _, k in ipairs(KINDS) do SS.textures[k.id] = k.texture end
local SEAF_STRATAGEM = 28

local kind_of = {}            -- [projectile type] = kind (each looked up once)
local function kind_for(v)
  local k = kind_of[v]
  if k then return k end
  if v < 1 or v >= 65536 then
    kind_of[v] = KIND.unknown
    event(string.format('shell value %d is out of range (shown as unknown)', v))
    return KIND.unknown
  end
  local p = read_ptr(L.proj + 8 * v)
  if not p or not fetch(p, 12) then return KIND.unknown end    -- not readable now: tried again at the next look
                                                                -- (no redraw while what's shown stays the same)
  k = KIND_BY_TEXT[b32(4)] or KIND_BY_TEXT[b32(8)]
  if not k then
    k = KIND.unknown
    event(string.format('projectile %d is not a known shell (names %08x / %08x)', v, b32(4), b32(8)))
  end
  kind_of[v] = k
  event(string.format('shell value %d = %s', v, k.name))
  return k
end

-- ======================================================================================================
-- The loaded shells: per rack the networked state (44 bytes: count +0, up to 8 projectile types +4, ready order
-- +0x24, -1 = not ready). The stratagem fires the ready racks in ready order, each from its first shell.
-- ======================================================================================================
local queue = { kinds = {}, sig = '', text = 'none', fails = 0 }   -- sig nil: read again next time
local function by_ready(a, b) if a.ready ~= b.ready then return a.ready < b.ready end return a.i < b.i end
local function read_queue()
  local rm = read_ptr(L.rack)
  if not rm or not fetch(rm, 0x58) then
    -- the racks can't be read (twice in a row): nothing is shown rather than an old list
    queue.fails = queue.fails + 1
    if queue.fails >= 2 and #queue.kinds > 0 then
      queue.kinds, queue.sig, queue.text = {}, '', 'none'
      event('loaded shells: the artillery could not be read (none shown)')
      return true
    end
    return false
  end
  queue.fails = 0
  local n, st = b32(8), bptr(0x50)
  if n > 8 then n = 8 end
  local racks = {}
  if n > 0 and st and fetch(st, 44 * n) then
    for i = 0, n - 1 do
      local o = 44 * i
      local cnt, ready = b32(o), b32(o + 0x24)
      if cnt > 0 and cnt <= 8 and ready ~= 0xFFFFFFFF then
        local r = { i = i, ready = ready, v = {} }
        for k = 1, cnt do r.v[k] = b32(o + 4 * k) end
        racks[#racks + 1] = r
      end
    end
  end
  if #racks > 1 then table.sort(racks, by_ready) end
  local vals = {}
  for _, r in ipairs(racks) do for _, v in ipairs(r.v) do vals[#vals + 1] = v end end
  local sig = table.concat(vals, ',')
  if sig ~= queue.sig then
    local kinds, names, settled = {}, {}, true
    for i, v in ipairs(vals) do
      kinds[i] = kind_for(v); names[i] = kinds[i].name
      if kind_of[v] == nil then settled = false end
    end
    queue.sig = settled and sig or nil
    -- a change only when the shell types shown change (not for a value still being looked up, or another value of
    -- the same type)
    local same = #kinds == #queue.kinds
    for i = 1, same and #kinds or 0 do if kinds[i] ~= queue.kinds[i] then same = false; break end end
    if same then return false end
    queue.kinds = kinds
    local text = #names > 0 and table.concat(names, ', ') or 'none'
    if text ~= queue.text then event('loaded shells (next first): ' .. text) end
    if TESTER then
      local raw = {}
      for _, r in ipairs(racks) do raw[#raw + 1] = string.format('rack %d ready %d: %s', r.i, r.ready, table.concat(r.v, ',')) end
      event(string.format('racks %d, ready %d; %s', n, #racks, #raw > 0 and table.concat(raw, '; ') or 'none ready'))
    end
    queue.text = text
    return true
  end
  return false
end

-- ======================================================================================================
-- The stratagem list (inside the HUD manager): its open flag, its 16 row widgets (slot +0x3748, stratagem id +0x374c).
-- A widget: local position +4/+8, size +0xC/+0x10, scale +0x14/+0x18, anchor in its parent +0x2C/+0x30, opacity
-- +0x44, its own pivot +0x3C/+0x40, parent +0xF0. y goes up; the root's scale turns its units into screen pixels.
-- ======================================================================================================
local ROWS, ROW_STRIDE = 16, 0x3760
local W_SPAN = 0x48
local OPACITY = 0x44
local W_KEYS = { 'x', 'y', 'w', 'h', 'sx', 'sy', 'ax', 'ay', 'qx', 'qy' }
local function widget(addr, w)          -- w: a table to fill (the row and the list reuse theirs every frame)
  if not fetch(addr, W_SPAN) then return nil end
  w = w or {}
  w.at, w.x, w.y, w.w, w.h, w.sx, w.sy = addr, bf32(4), bf32(8), bf32(12), bf32(16), bf32(0x14), bf32(0x18)
  w.ax, w.ay, w.qx, w.qy, w.alpha = bf32(0x2c), bf32(0x30), bf32(0x3c), bf32(0x40), bf32(OPACITY)
  for i = 1, #W_KEYS do
    local v = w[W_KEYS[i]]
    if not v or math.abs(v) > 100000 then return nil end
  end
  return w
end
local function parent_of(addr) return read_ptr(addr + 0xf0) end
-- the chain from a widget up to the root: { widget, its parent, ..., root }
local function chain_of(addr)
  local chain = {}
  local p = addr
  for _ = 1, 16 do
    local w = widget(p)
    if not w then return nil end
    chain[#chain + 1] = w
    p = parent_of(p)
    if not p then return chain end
  end
  return nil
end
-- the rectangle in screen pixels (left, bottom, width, height; y up) of the chain's first widget, plus the right
-- edge of its parent (the list), in one pass from the root down
local function rect_of(chain)
  local n = #chain
  local root = chain[n]
  local px = root.sx > 0 and root.sx or 1
  local l, b, w, h, sx, sy = 0, 0, root.w, root.h, 1, 1
  local right
  for k = n - 1, 1, -1 do
    local c = chain[k]
    local ax, ay = l + c.ax * w, b + c.ay * h
    local x, y = ax + c.x * sx, ay + c.y * sy
    sx, sy = sx * c.sx, sy * c.sy
    w, h = c.w * sx, c.h * sy
    l, b = x - c.qx * w, y - c.qy * h
    if k == 2 then right = l + w end
  end
  return l * px, b * px, w * px, h * px, (right or l + w) * px
end
-- the opacity the list and its parents add on top (another mod can hide the whole list, e.g. HD2 HUD+'s own panel)
local function chain_opacity(chain)
  local a = 1
  for k = 3, #chain - 1 do
    local at = chain[k].at
    if not fetch(at + OPACITY, 4) then return 0 end
    local v = bf32(0)
    if not v then return 0 end
    chain[k].alpha = v
    a = a * v
  end
  return a
end

-- ======================================================================================================
-- Drawing: screen GUIs in the game's overlay world, one per shell type (its icon bound to a copy of the game's UI
-- material), plus one for the marks. Bitmaps are kept between frames and only moved when something changed.
-- ======================================================================================================
local A, W, G, V2, V3, C, ID, MAT
local UI_MATERIAL, SLOT = 'e2d6ed90906c1e8b', '3aa8b87e00000000'   -- content/ui/shared/misc/yellow_logo, its texture slot
local gui = { world = nil, list = {}, state = 'not needed yet', next_check = 0, icons = nil, update = nil }
local function api_ok()
  if A then return true end
  if type(SR) ~= 'table' then return false end
  local a, w, g = SR.Application, SR.World, SR.Gui
  if not (a and a.worlds and a.main_world and a.can_get and w and w.create_screen_gui and g and g.bitmap and g.destroy_bitmap
          and g.triangle and g.destroy_triangle and g.material and SR.Material and SR.Material.set_texture and SR.Vector2
          and SR.Vector3 and SR.Color and SR.IdString64 and SR.IdString64.from_hex) then
    gui.state = 'this game version lacks a GUI function'; return false
  end
  A, W, G, V2, V3, C, ID, MAT = a, w, g, SR.Vector2, SR.Vector3, SR.Color, SR.IdString64, SR.Material
  gui.update = type(G.update_bitmap) == 'function'
  return true
end
local function loaded(kind, hexid)
  local ok, v = pcall(ID.from_hex, hexid)
  if not ok then return false end
  local okc, yes = pcall(A.can_get, kind, v)
  return okc and yes == true
end
local function gui_for(key, layer)
  local g = gui.list[key]
  if g then return g end
  local ok, h = pcall(W.create_screen_gui, gui.world, 'scale', 1, 1)
  if not ok or h == nil then gui.state = 'create_screen_gui failed: ' .. tostring(h); return nil end
  g = { h = h, bitmaps = {}, tris = {}, layer = layer or 20 }
  gui.list[key] = g
  return g
end
local function drop_tris(g)
  for _, id in ipairs(g.tris) do pcall(G.destroy_triangle, g.h, id) end
  g.tris = {}
end
local function clear(g)
  for _, id in ipairs(g.bitmaps) do pcall(G.destroy_bitmap, g.h, id) end
  g.bitmaps = {}
  drop_tris(g)
end
local function clear_all() for _, g in pairs(gui.list) do clear(g) end end

-- Safety net for our textures: a marker file says 'trying' until icons have been on screen 60 frames (or the list
-- closed with them shown); if the game closed in between, the next start draws plain shapes instead (once).
local CHECK = LOGDIR and (LOGDIR .. '\\' .. LOGNAME .. '.iconcheck') or nil
local function iconcheck(text)
  if not CHECK then return nil end
  if text then local f = io.open(CHECK, 'w'); if f then f:write(text); f:close() end; return end
  local f = io.open(CHECK, 'r'); if not f then return nil end
  local t = f:read('*a'); f:close(); return t
end
local function icons_usable()
  if gui.icons ~= nil then return gui.icons end
  local last = iconcheck()
  if last and last:find('^trying') then
    iconcheck('skipped once\n'); gui.icons = false
    gui.icon_state = 'plain shapes for now (the last try ended with the game closing; icons are tried again next start)'
    return false
  end
  local missing = {}
  if not loaded('material', UI_MATERIAL) then missing[#missing + 1] = 'UI material' end
  for _, k in ipairs(KINDS) do if not loaded('texture', k.texture) then missing[#missing + 1] = k.id end end
  gui.icons = #missing == 0
  gui.icon_state = gui.icons and 'icons' or ('plain shapes (not loaded: ' .. table.concat(missing, ', ') .. ')')
  if gui.icons then iconcheck('trying\n'); gui.icon_watch = 60 end
  return gui.icons
end
local function icons_proven()
  if gui.icon_watch and gui.drawn then gui.icon_watch = nil; iconcheck('ok\n') end
end
local view = { sig = nil }     -- sig nil: draw again next frame
local function icon_refused(why)
  gui.icons, gui.icon_watch, view.sig = false, nil, nil
  gui.icon_state = 'plain shapes (' .. why .. ')'
  iconcheck('refused\n')
end
-- bitmaps of texture `tex` into GUI g: pts[i] = { left, bottom, width, height, alpha }; existing bitmaps are moved
local function bitmaps(g, tex, pts, n)
  local okm, m = pcall(ID.from_hex, UI_MATERIAL)
  local okt, t = pcall(ID.from_hex, tex)
  local oks, s = pcall(ID.from_hex, SLOT)
  local okg, mh = false, nil
  if okm and okt and oks then okg, mh = pcall(G.material, g.h, m) end
  if not okg or mh == nil or not pcall(MAT.set_texture, mh, s, t) then icon_refused('the UI material was refused'); return false end
  local old = g.bitmaps
  for i = 1, n do
    local p = pts[i]
    local pos, dims, color = V3(p[1], p[2], g.layer), V2(p[3], p[4]), C(p[5], 255, 255, 255)
    local id = old[i]
    local ok = false
    if id ~= nil and gui.update then
      ok = pcall(G.update_bitmap, g.h, id, m, pos, dims, color)
      if not ok then gui.update = false; event('Gui.update_bitmap refused; bitmaps are replaced instead') end
    end
    if not ok then
      if id ~= nil then pcall(G.destroy_bitmap, g.h, id) end
      local okb, nid = pcall(G.bitmap, g.h, m, pos, dims, color)
      if not okb or nid == nil then old[i] = nil; icon_refused('bitmap refused: ' .. tostring(nid)); return false end
      old[i] = nid
    end
  end
  for i = #old, n + 1, -1 do pcall(G.destroy_bitmap, g.h, old[i]); old[i] = nil end
  gui.drawn = true
  return true
end
local function tri(g, a, b, c, layer, col)
  local ok, id = pcall(G.triangle, g.h, a, b, c, layer, col)
  if ok and id ~= nil then g.tris[#g.tris + 1] = id end
end
local function quad(g, x1, y1, x2, y2, x3, y3, x4, y4, layer, col)
  local a, b, c, d = V3(x1, 0, y1), V3(x2, 0, y2), V3(x3, 0, y3), V3(x4, 0, y4)
  tri(g, a, b, c, layer, col)
  tri(g, a, c, d, layer, col)
end
local function rect(g, x0, y0, x1, y1, layer, col) quad(g, x0, y0, x1, y0, x1, y1, x0, y1, layer, col) end
-- plain shapes: the fallback when our textures can't be used (a shell: body, colored tip, brass base)
local function plain_shell(g, k, p)
  local l, b, w, h, a = p[1], p[2], p[3], p[4], p[5]
  local cx, bw = l + w / 2, w * 0.36
  local dark = C(a, 10, 10, 10)
  rect(g, cx - bw / 2 - 1, b + h * 0.06 - 1, cx + bw / 2 + 1, b + h * 0.68 + 1, 21, dark)
  rect(g, cx - bw / 2, b + h * 0.06, cx + bw / 2, b + h * 0.30, 21.1, C(a, 176, 150, 82))
  rect(g, cx - bw / 2, b + h * 0.30, cx + bw / 2, b + h * 0.68, 21.1, C(a, 84, 90, 74))
  local t = k.rgb
  tri(g, V3(cx - bw / 2, 0, b + h * 0.68), V3(cx + bw / 2, 0, b + h * 0.68), V3(cx, 0, b + h * 0.95), 21.1,
    C(a, t[1], t[2], t[3]))
end

-- ======================================================================================================
-- The shell row: right of the stratagem list, level with the SEAF Artillery row, as tall as the row allows.
-- The next shell sits on a thin yellow bar.
-- ======================================================================================================
local ICON_H = 0.86           -- icon height, of the row's height
local STEP = 0.46             -- icon spacing, of the icon height
local GAP = 0.18              -- gap after the list, of the row's height
local function draw(rl, rb, rw, rh, list_right, alpha)
  local n = #queue.kinds
  if n == 0 or alpha <= 0 then clear_all(); return end
  local size = rh * ICON_H
  local x0 = math.max(rl + rw, list_right) + rh * GAP
  local y0 = rb + (rh - size) / 2
  local a = math.floor(255 * alpha + 0.5)
  local per = {}
  for i, k in ipairs(queue.kinds) do
    local list = per[k.id]
    if not list then list = {}; per[k.id] = list end
    local fade = i == 1 and 1 or 0.82
    list[#list + 1] = { x0 + (i - 1) * size * STEP, y0, size, size, math.floor(a * fade + 0.5), i }
  end
  -- the marks: a yellow bar under the next shell
  local mg = gui.list.marks or gui_for('marks', 20)
  if mg then
    drop_tris(mg)
    local bx = x0 + size * 0.18
    rect(mg, bx, y0 - size * 0.02, bx + size * 0.64, y0 + size * 0.03, 20, C(a, 255, 231, 16))
  end
  local use_icons = icons_usable()
  for _, k in ipairs(KINDS) do
    local pts = per[k.id]
    local g = gui.list[k.id]
    if pts then
      g = g or gui_for(k.id, 21)
      if g then
        local done = use_icons and bitmaps(g, k.texture, pts, #pts)
        if not done then
          clear(g)
          for _, p in ipairs(pts) do plain_shell(g, k, p) end
        end
      end
    elseif g then clear(g) end
  end
end

local function overlay_world()
  local okm, main = pcall(A.main_world)
  local okw, worlds = pcall(A.worlds)
  if not okm or not okw or type(worlds) ~= 'table' then return nil, nil end
  local target, live = nil, false
  for i = 1, #worlds do
    local x = worlds[i]
    if x ~= nil and x ~= main and not target then target = x end
    if gui.world ~= nil and x == gui.world then live = true end
  end
  return target, live
end
-- the mission is over (no HUD): our GUIs are only destroyed if their world still exists, otherwise just forgotten
local function release_gui()
  if A and gui.world and next(gui.list) then
    local _, live = overlay_world()
    if not live then gui.world, gui.list = nil, {}; return end
  end
  clear_all()
end

-- ======================================================================================================
-- Every frame. List closed: one 1-byte read. List open: the SEAF row and the list (two reads), the shells four
-- times a second; drawing only when something moved or changed.
-- ======================================================================================================
local ready = not V19
local broken, last_error = false, nil
local hud, next_second, open_was = nil, 0, false
local row = { at = nil, chain = nil, looked = -1, checked = 0 }
local ID_AT = 0x374c          -- a row's stratagem id (its slot is just before it, +0x3748)
local floor = math.floor
-- another mod hiding the game's list (HD2 HUD+'s stratagem panel sets the list's group to opacity 0, a few frames after
-- the list opens): once seen (or when HD2 HUD+ is installed), each opening starts hidden and the icons only show once
-- the list's parents have stayed visible for half a second; the parents are read every frame right after opening
local HUDPLUS = 'mods/hd2_hud/hd2_hud_plus'
local cover = { known = nil, since = nil, fast_until = 0 }
local next_queue = 0
local stats_open = 0

local function find_seaf_row(first)
  for i = 0, ROWS - 1 do
    local at = first + i * ROW_STRIDE
    if fetch(at + ID_AT, 4) and b32(0) == SEAF_STRATAGEM then return at, i end
  end
  return nil
end

-- ======================================================================================================
-- Mod Options Menu (optional): two toggles under ESC > MODS > SEAF ARTILLERY LOADOUT. Both off: nothing is read.
-- ======================================================================================================
local enabled = true          -- the shell icons
local fix_name = true         -- the game's "SEAF ARTILLERY: <shell>" name redone when the next shell changes
local menu_state = 'Mod Options Menu not installed (both on)'
local menu_linked = false
local function link_menu()
  local M = rawget(_G, 'ModOptionsMenu')
  if type(M) ~= 'table' or M.api ~= 1 or type(M.register_option) ~= 'function' then return false end
  local added, failed = 0, nil
  local function toggle(id, label, description, set, what)
    local ok, yes = pcall(M.register_option, id, {
      type = 'toggle', mod = 'SEAF Artillery Loadout', label = label, default = true, description = description })
    if not (ok and yes) then failed = failed or tostring(yes); return end
    added = added + 1
    local function apply(v)
      if type(v) == 'boolean' and set(v) then event('options menu: ' .. what .. ' ' .. (v and 'on' or 'off')) end
    end
    local okg, v = pcall(M.get, id)
    if okg then apply(v) end
    pcall(M.on_change, id, apply)
  end
  toggle('seaf_artillery_loadout.on', 'Show the loaded shells',
    'Icons for the shells still loaded in the SEAF artillery, next to the SEAF Artillery stratagem while the stratagem list is open.',
    function(v) if v == enabled then return false end enabled = v; return true end, 'shell icons')
  toggle('seaf_artillery_loadout.fix_name', 'Fix the next-shell name',
    'The game\'s SEAF Artillery row can keep naming a shell that was already fired. This has the game redo the name whenever the next shell changes.',
    function(v) if v == fix_name then return false end fix_name = v; return true end, 'name fix')
  menu_state = string.format('Mod Options Menu: %d toggle%s', added, added == 1 and '' or 's')
    .. (failed and (' (could not add one: ' .. failed .. ')') or '')
  dirty_log = true
  return true
end

-- The name fix: the game's row update keeps the row's stratagem id and only redoes the row's name when the id it
-- finds differs from the kept one. Setting the kept id to 0 once (while the list is open) makes the game's next
-- update see a "new" stratagem and redo the name with its own code, which names the shell that really fires next.
-- The game writes the real id back in that same update; if it hasn't within half a second, the mod puts it back
-- itself and leaves the fix off for the rest of the session.
-- The id is only put back while the row is provably still ours: the same HUD manager, the same slot (+0x3748), id
-- still 0. (Leaving a 0 is harmless anyway: the game's row update sets the id from the player's list every time.)
local fix = { kind = nil, pending = nil, hud = nil, slot = nil, until_ = 0, done = 0, off = nil }
local function fix_restore()
  local p = fix.pending
  fix.pending = nil
  if not p or read_ptr(L.hud) ~= fix.hud or not fetch(p + L.rowid_r - 4, 8) or b32(0) ~= fix.slot or b32(4) ~= 0 then
    return false
  end
  return write_u32(p + L.rowid_r, SEAF_STRATAGEM)
end
local function fix_settle(now, open)    -- open: true, false (list closed) or nil (no HUD: the mission is over)
  local p = fix.pending
  if not p then return end
  if open == nil then fix.pending, fix.kind = nil, nil; return end     -- the HUD is gone: nothing to put back
  if not fetch(p + L.rowid_r, 4) then fix.pending = nil; return end
  local v = b32(0)
  if v ~= 0 then
    fix.pending = nil
    if TESTER then event(string.format('name fix: the game redid the row (id %d)', v)) end
  elseif not open then
    -- the list closed before the game's update: put the id back, try again at the next opening
    fix_restore()
    fix.kind = nil
    if TESTER then event('name fix: the list closed first; id put back, again next time') end
  elseif now >= fix.until_ then
    fix_restore()
    fix.off = 'the game did not redo the row (id put back); off for this session'
    event('name fix: ' .. fix.off)
  end
end

local function tick()
  stats.frames = stats.frames + 1
  local now = os.clock()
  if not menu_linked and stats.frames % 60 == 0 and stats.frames < 3600 then menu_linked = link_menu() end
  if not L then
    if not ready then SS.status = 'waiting for start-up'; return end
    local ok, res = pcall(resolve)
    if not ok then broken, last_error, SS.status = true, 'could not find the game addresses: ' .. tostring(res), 'off'; event(last_error); return end
    L = res
    event('game addresses: ' .. session.layout .. string.format(' (%.2f s)', session.scan_seconds))
  end
  -- both off in the options menu: the addresses are still found at start-up (no hitch when turned on), nothing else
  if not enabled and not fix_name then
    if fix.pending then fix_restore() end
    if open_was then
      clear_all(); open_was = false; view.sig = nil; row.at, row.looked, row.told = nil, -1, nil
    end
    SS.status = 'off (options menu)'
    return
  end
  if now >= next_second then
    next_second = now + 1
    hud = nil                                    -- the HUD manager pointer: looked up again once a second
  end
  hud = hud or read_ptr(L.hud)
  local parent = hud and hud + L.hud_a + L.hud_b
  local open = parent and fetch(parent + L.open, 1) and b8(0) or nil
  fix_settle(now, open and open == 1)
  if open ~= 1 then
    if open_was then
      if open == nil then release_gui() else clear_all() end
      open_was = false; view.sig = nil; row.at, row.looked, row.told = nil, -1, nil
      icons_proven()
    end
    SS.status = open == nil and 'no mission' or 'list closed'
    return
  end
  SS.status = 'list open'
  stats_open = stats_open + 1
  local opened = not open_was
  open_was = true
  if opened then
    cover.fast_until, cover.since, row.alpha = now + 0.6, nil, nil
    if cover.known == nil then
      local ok, found = pcall(function() return SR.Application.can_get('lua', HUDPLUS) end)
      cover.known = ok and found == true
      if cover.known then event('HD2 HUD+ is installed: the icons wait until the game\'s list is really showing') end
    end
  end
  -- the icons need the engine's GUI functions and the overlay world (the name fix doesn't)
  local icons_on = enabled and api_ok()
  if icons_on and (opened or now >= gui.next_check) then          -- (once a second even while there's no world)
    gui.next_check = now + 1
    local target, live = overlay_world()
    if gui.world and not live then gui.world, gui.list = nil, {} end
    if not gui.world then
      if not target then gui.state = 'no overlay world'; icons_on = false
      else gui.world, gui.state, view.sig = target, 'screen GUIs in the overlay world', nil end
    end
  end
  -- the loaded shells: when the list opens and four times a second while it's open
  local changed = false
  if opened or now >= next_queue then
    next_queue = now + 0.25
    changed = read_queue()
  end
  if #queue.kinds == 0 then
    if view.sig then clear_all(); view.sig = nil end
    fix.kind = nil                               -- a new mission starts the name fix afresh
    return
  end
  -- the row still shows SEAF Artillery (checked when the shells change and once a second)
  if row.at and fix.pending ~= row.at and (changed or now >= row.checked) then
    row.checked = now + 1
    if not fetch(row.at + ID_AT, 4) or b32(0) ~= SEAF_STRATAGEM then
      event('the SEAF Artillery row moved; looking again')
      row.at, row.looked = nil, -1
    end
  end
  -- the SEAF Artillery row (looked for when the list opens, then twice a second until found) and its parents
  local list = parent + L.hud_c
  if not row.at and now >= row.looked then
    row.looked = now + 0.5
    local at, i = find_seaf_row(list + L.rowbase)
    if at then
      local chain = chain_of(at)
      if chain and #chain >= 3 then
        row.at, row.chain, row.checked, row.alpha, row.wr, row.wl = at, chain, now + 1, nil, {}, {}
        local l, b, w, h = rect_of(chain)
        -- logged when it differs from last time (its x changes with the slide-in, so it's left out of the check)
        local key = string.format('%d,%d,%.0f,%.0f,%.0f,%.3f', i, #chain, b, w, h, chain[#chain].sx)
        if key ~= row.logged then
          row.logged = key
          event(string.format('SEAF Artillery row %d: %d levels up to the screen; at %.0f, %.0f size %.0f x %.0f px (screen scale %.3f)',
            i, #chain, l, b, w, h, chain[#chain].sx))
        end
      else
        event('SEAF Artillery row found, but its parents could not be read')
        row.looked = now + 5
      end
    end
  end
  if not row.at then
    if view.sig then clear_all(); view.sig = nil end
    return
  end
  -- the name fix: once each time the next shell changes (and once per mission), while the list is open
  local front = queue.kinds[1]
  if fix_name and not fix.off and L.rowid_r and L.rowid_r == L.rowid_w and L.rowid_r == ID_AT
     and not fix.pending and front ~= fix.kind then
    if fetch(row.at + ID_AT - 4, 8) and b32(4) == SEAF_STRATAGEM then
      local slot = b32(0)
      if write_u32(row.at + ID_AT, 0) then
        fix.kind, fix.pending, fix.hud, fix.slot, fix.until_, fix.done = front, row.at, hud, slot, now + 0.5, fix.done + 1
        row.checked = now + 1                    -- our own row check waits for the game to put the id back
        event('name fix: had the game redo the row\'s name (next shell: ' .. front.name .. ')')
      end
    end
  end
  if not icons_on then
    if view.sig then clear_all(); view.sig = nil end
    return
  end
  -- every frame while open: the row (it slides in) and the list (its width and opacity); the opacity of the list's
  -- parents (another mod may hide the game's list) when the row is found and four times a second
  local rw_, lw_ = widget(row.at, row.wr), widget(row.chain[2].at, row.wl)
  if not rw_ or not lw_ then return end
  row.chain[1], row.chain[2] = rw_, lw_
  if not row.alpha or now >= row.alpha_next or now < cover.fast_until then
    row.alpha, row.alpha_next = chain_opacity(row.chain), now + 0.25
    if row.alpha <= 0.01 then
      if not cover.known then event('another mod hides the game\'s stratagem list (e.g. HD2 HUD+\'s stratagem panel): icons hidden') end
      cover.known, cover.since = true, nil
    else
      cover.since = cover.since or now
      if cover.known and now - cover.since >= 0.5 then
        cover.known = false
        event('the game\'s stratagem list is showing: icons shown')
      end
    end
  end
  local rl, rb, rw, rh, list_right = rect_of(row.chain)
  local alpha = cover.known and 0 or (rw_.alpha or 1) * (lw_.alpha or 1) * row.alpha
  alpha = floor(math.max(0, math.min(1, alpha)) * 100 + 0.5) / 100
  -- redrawn when something moved by a tenth of a pixel, faded, or the shells changed
  local r = view
  local xl, xb, xw, xh, xr = floor(rl * 10 + 0.5), floor(rb * 10 + 0.5), floor(rw * 10 + 0.5), floor(rh * 10 + 0.5),
    floor(list_right * 10 + 0.5)
  if changed or not r.sig or r.l ~= xl or r.b ~= xb or r.w ~= xw or r.h ~= xh or r.r ~= xr or r.a ~= alpha then
    r.sig, r.l, r.b, r.w, r.h, r.r, r.a = true, xl, xb, xw, xh, xr, alpha
    stats.redraws = stats.redraws + 1
    draw(rl, rb, rw, rh, list_right, alpha)
    if TESTER and row.told ~= row.at then
      row.told = row.at
      event(string.format('drawn: row %.0f, %.0f size %.0f x %.0f px, list right %.0f, opacity %.2f (parents %.2f), %d shells; %s',
        rl, rb, rw, rh, list_right, alpha, row.alpha or -1, #queue.kinds, gui.state))
    end
  end
  if gui.icon_watch and gui.drawn then
    gui.icon_watch = gui.icon_watch - 1
    if gui.icon_watch <= 0 then icons_proven() end
  end
end

-- ======================================================================================================
-- The log (rewritten every 10 s when something changed, and when the game closes)
-- ======================================================================================================
local T = { n = 0, sum = 0, max = 0, over = 0, open_n = 0, open_sum = 0 }
local function write_log()
  if not LOGDIR then return end
  dirty_log = false
  local f = io.open(LOGDIR .. '\\' .. LOGNAME .. '.log', 'w')
  if not f then return end
  f:write('SEAF Artillery Loadout ', VERSION, '  (started ', session.started, ', written ', os.date('%H:%M:%S'), ')\n')
  f:write('status: ', SS.status, broken and (' - ' .. tostring(last_error)) or '', '\n')
  f:write('Bingus Shared Loader: ', V19 and 'v19 or newer' or 'older than v19 (needs v19 or newer; using the old start-up)', '\n')
  f:write('options menu: ', menu_state, '; shell icons ', enabled and 'on' or 'off', ', name fix ', fix_name and 'on' or 'off', '\n')
  f:write('name fix: ', fix.off or (not fix_name and 'off (options menu)') or (not L and 'waiting for the game addresses')
    or (not (L.rowid_r and L.rowid_r == L.rowid_w and L.rowid_r == ID_AT) and 'off (the game\'s row update changed; not found)')
    or 'ready', string.format('; names redone %d (game writes %d)', fix.done, stats.writes), '\n')
  f:write('game addresses: ', tostring(session.layout), session.scan_seconds and string.format(' (%.2f s)', session.scan_seconds) or '', '\n')
  f:write('drawing: ', gui.state, '; ', tostring(gui.icon_state or 'icons not tried yet'),
          gui.update ~= nil and ('; bitmaps ' .. (gui.update and 'moved in place' or 'replaced')) or '', '\n')
  if T.n > 0 then
    f:write(string.format('cost per frame: average %.4f ms (list open %.4f ms), highest %.3f ms, frames over 1 ms: %d\n',
      T.sum / T.n, T.open_n > 0 and T.open_sum / T.open_n or 0, T.max, T.over))
  end
  f:write(string.format('frames %d (list open %d), game reads %d (%.2f per frame, failed %d), redraws %d\n', stats.frames, stats_open,
    stats.reads, stats.frames > 0 and stats.reads / stats.frames or 0, stats.read_fails, stats.redraws))
  f:write('loaded shells (next first): ', queue.text, '\n')
  f:write('\nrecent events:\n')
  for _, e in ipairs(session.events) do f:write('  ', e, '\n') end
  f:close()
end
SS.write_log = write_log

-- ======================================================================================================
-- Hooks
-- ======================================================================================================
local game_update, game_shutdown = rawget(_G, 'update'), rawget(_G, 'shutdown')
if type(game_update) ~= 'function' then SS.status = 'off: game update function not found'; write_log(); return end
local q, per_ms = ffi.new('int64_t[1]'), nil
do
  local fq = ffi.new('int64_t[1]')
  if pcall(function() return K32.SsQueryPerformanceFrequency(fq) end) and fq[0] > 0 then per_ms = tonumber(fq[0]) / 1000 end
end
local next_log = 0
rawset(_G, 'update', function(...)
  if not broken then
    local a
    if per_ms then K32.SsQueryPerformanceCounter(q); a = q[0] end
    local ok, e = pcall(tick)
    if per_ms then
      K32.SsQueryPerformanceCounter(q)
      local ms = tonumber(q[0] - a) / per_ms
      T.n, T.sum = T.n + 1, T.sum + ms
      if open_was then T.open_n, T.open_sum = T.open_n + 1, T.open_sum + ms end
      if ms > T.max then T.max = ms end
      if ms > 1 then T.over = T.over + 1 end
    end
    if not ok then
      broken, last_error, SS.status = true, 'tick: ' .. tostring(e), 'off'
      event(last_error)
      pcall(clear_all)
      if fix.pending then pcall(fix_restore) end     -- never leave the row's id at 0
    end
  end
  local now = os.clock()
  if now >= next_log then
    next_log = now + 10
    if dirty_log then pcall(write_log) end
  end
  return game_update(...)
end)
if type(game_shutdown) == 'function' then
  rawset(_G, 'shutdown', function(...)
    pcall(icons_proven)                          -- closed normally with icons shown: they work
    pcall(write_log)
    return game_shutdown(...)
  end)
end
if V19 then
  local ok = LOADER.after_startup(function()
    ready = true
    if not menu_linked then menu_linked = link_menu() end
  end)
  if not ok then ready = true end
else
  event('Bingus Shared Loader older than v19: needs v19 or newer (starting without waiting for start-up)')
end
event('loaded')
pcall(write_log)
