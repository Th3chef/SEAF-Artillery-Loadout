-- HD2-Addon: mods/chef/seaf_artillery_loadout
-- SEAF Artillery Loadout for Helldivers 2 (Bingus Shared Loader v19+ addon).
-- Once the SEAF Artillery objective is done, the shells still loaded in the artillery are shown as icons, in firing
-- order, right of the SEAF Artillery stratagem while the stratagem list is open; the next shell is marked.
-- It also has the game redo the row's "SEAF ARTILLERY: <shell>" name when the next shell changes: the game only sets
-- that name when the row gets a new stratagem, so after a shot it can keep naming a shell that was already fired.
-- That is its only direct write to game memory (one value in the HUD's own row, which the game sets back on its next
-- update). (2.0.0) With HD2 HUD+'s stratagem panel, the icons go on HUD+'s panel as the game's own UI widgets, made
-- in this addon's own memory and attached with the game's own UI calls (see "HD2 HUD+'s stratagem panel" below).
-- Everything else is read only. It finds the game's addresses and calls again by itself after a game update.
local VERSION = '2.0.0'
local TEST_BUILD = false      -- numbered test builds: the log goes to Logs\test
local TESTER = false          -- the release's Tester build: more detail in the log
local SPOOF = false           -- spoof test builds: made-up shells on the list's first row (no SEAF Artillery needed)

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
-- (2.0.0) the game's start-up loop over its UI contexts (from the second one; its pointer to them, their size, how many)
local UI_LOOP = '488b2d????????bb01000000488dbd????????90803f0074??8bc34869c8????????4803cde8????????ffc34881c7????????83fb??72'
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
  -- ((1.0.1 review) the distance between the rows, from the same 16-row loop's two pointer steps (both must agree, and
  -- the match must sit just after rowbase's); not found: the known one, and a row only counts when it is the only one
  -- with the SEAF id)
  rowstride = { { p = '440a3f488dbf????????4981c6????????4983ec0175', at = 6, also = 13 } },
  -- the name fix (optional): where the game's row update keeps the row's stratagem id, read as the old id and then
  -- overwritten with the new one (the name is only redone when they differ); both offsets must agree
  rowid_r = { { p = '418b87????????4b8d0c764c8b55??4803c98945??418b94ca????????418997????????', at = 3 } },
  rowid_w = { { p = '418b87????????4b8d0c764c8b55??4803c98945??418b94ca????????418997????????', at = 32 } },
  -- (2.0.0) the game's UI calls and contexts, for the icons on HD2 HUD+'s stratagem panel (optional: without them that
  -- panel gets no icons; everything else works). The UI contexts: a pointer to the array (the start-up loop over the
  -- contexts and the context pop both read it; they must agree), the size of one context and how many there are (the
  -- loop's own numbers), and where the context stack's top is kept (context push, twice).
  ui_ctx = { { p = UI_LOOP, at = 3, rip = true }, { p = '488b05????????ff88????????c3', at = 3, rip = true },
    { p = '48895c2410574883ec200f2805????????33ff4c8b05????????', at = 22, rip = true } },
  ui_stride = { { p = UI_LOOP, at = 15, also = 30 } },
  ui_slots = { { p = UI_LOOP, at = 53, u8 = true } },
  ui_top = { { p = '4c6381????????418d40018981????????41889408????????c3', at = 3, also = 13 } },
  -- the context stack (push writes the new slot there, just before the top) and each context's roots (a small set
  -- near its end: the game's root_build puts a new root there, right after reading the root's context at +0xF8)
  ui_stack = { { p = '4c6381????????418d40018981????????41889408????????c3', at = 21 } },
  ui_roots = { { p = 'e8????????488b8bf8000000488bd34881c1????????e8', at = 18 } },
  -- the calls themselves: where each function starts (here = the match is the function). The patterns keep the
  -- widget offsets the calls rely on (first child +0xE0, next sibling +0xE8, parent +0xF0, layer +0xBC; root_build's
  -- context +0xF8), so a game that moved them is not matched. widget_shown_set has an identical twin (same body, same calls): either is the same function.
  ui_push = { { p = '4c6381????????418d40018981????????41889408????????c3', here = true } },
  ui_pop = { { p = '488b05????????ff88????????c3', here = true } },
  w_init = { { p = '48895c2410574883ec200f2805????????33ff4c8b05????????', here = true } },
  w_pinit = { { p = '40534883ec20ba03000000488bd9e8????????', here = true } },
  w_pset = { { p = '48895c2410574883ec30498bd8488bf9450fb6c1', here = true } },
  w_size = { { p = '48895c241848896c24204889542410565741574883ec20f30f10410c', here = true } },
  w_anchor = { { p = '4883ec28f30f10412c4c8bc94889542430', here = true } },
  w_pivot = { { p = '4883ec28f30f10413c4c8bc94889542430', here = true } },
  w_pos = { { p = '48895c241848896c24204889542410565741574883ec20f30f104104', here = true } },
  w_layer = { { p = '4883ec284c8bc9663991bc0000007507', here = true } },
  w_shown = { { p = '4883ec28448b014c8bd1418bc0458bc883e0ef4183c91084d2440f44c8448909453bc174668b91b80000004183c9208bc24489090fbae80b8981b80000003bc27449f7d223d081e2ff2fffff7417488b89e00000004885c9740b41b001e8????????458b0a418bc1c1e802a801751c498b8af00000004183c90445890a4885c9',
               here = true, twins = 0x5d } },
  w_opacity = { { p = '40574883ec20f30f104144488bf90f2ec1', here = true } },
  -- (w_attach: the whole child insert, so first child +0xE0, next sibling +0xE8 and parent +0xF0 are all checked)
  w_attach = { { p = '40534883ec204c8bca488bd9488b91e00000004885d274??33c9488bc2493bd174??4c3bc876??488bc8488b80e80000004885c075??4885c975??498991e80000004c898be0000000eb??493bc974??488b81e8000000493bc174??498981e80000004c8989e8000000eb??4c8989e0000000418b91b80000008bc20fbae80d498999f0000000',
                here = true } },
  w_detach = { { p = '40534883ec20488bd9488b89f0000000', here = true } },
}
local HX_ITEMS = { 'ui_ctx', 'ui_stride', 'ui_slots', 'ui_top', 'ui_stack', 'ui_roots', 'ui_push', 'ui_pop', 'w_init', 'w_pinit', 'w_pset',
  'w_size', 'w_anchor', 'w_pivot', 'w_pos', 'w_layer', 'w_shown', 'w_opacity', 'w_attach', 'w_detach' }
local OPTIONAL = { rowid_r = ' (name fix off)', rowid_w = ' (name fix off)', rowstride = ' (rows checked by their SEAF id)' }
for _, k in ipairs(HX_ITEMS) do OPTIONAL[k] = ' (no icons on HD2 HUD+\'s panel)' end
local P_ORDER = { 'rack', 'proj', 'hud', 'hud_a', 'hud_b', 'hud_c', 'open', 'rowbase', 'rowstride', 'rowid_r', 'rowid_w' }
for _, k in ipairs(HX_ITEMS) do P_ORDER[#P_ORDER + 1] = k end
-- what the September 2026 game build has (game.dll 6ab3b43f, checked against its runtime dump); a cross-check: the
-- log says what moved
local KNOWN = { rack = 0x3326710, proj = 0x37c7670, hud = 0x346d538, hud_a = 0x24e340, hud_b = 0x146dc0,
  hud_c = 0x1040, open = 0x38769, rowbase = 0x110, rowstride = 0x3760, rowid_r = 0x374c, rowid_w = 0x374c,
  ui_ctx = 0x347ce90, ui_stride = 0x3698, ui_slots = 13, ui_top = 0x2c5bc, ui_stack = 0x2c5b9, ui_roots = 0x3680, ui_push = 0x12ef4b0, ui_pop = 0x12ef4d0,
  w_init = 0x1446840, w_pinit = 0x143eab0, w_pset = 0x1450230, w_size = 0x1447160, w_anchor = 0x144f160,
  w_pivot = 0x144f0d0, w_pos = 0x14476a0, w_layer = 0x14491f0, w_shown = 0x144cfb0, w_opacity = 0x1448ad0,
  w_attach = 0x144c5c0, w_detach = 0x144e6c0 }
local KNOWN_BUILD = '6ab3b43f-04744000-0210fa93'   -- that build's game.dll (time stamp, image size, code size)
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
-- ((1.0.1 review) the cache keeps where each item's pattern matched (pattern number:offset in the code), so a
-- cached layout is only used after those bytes were read again and still match their patterns and give the same values)
local function cache_save(key, found, at)
  if not CACHE then return end
  local f = io.open(CACHE, 'w'); if not f then return end
  local t = {}
  for _, k in ipairs(P_ORDER) do t[#t + 1] = string.format('%s=%d,m_%s=%q', k, found[k] or -1, k, at[k] or '') end
  f:write(string.format('{key=%q,%s}', key, table.concat(t, ','))); f:close()
end

-- an item's value at match o of text (rva: the game address of text's first byte); nil when its two places disagree
local function value_at(text, o, p, rva)
  if p.here then return rva + o end                      -- (2.0.0) the match is the function itself
  if p.u8 then return text:byte(o + p.at + 1) end        -- (2.0.0) a one-byte number
  local v = p.rip and (rva + o + p.at + 4 + si32(text, o + p.at)) or su32(text, o + p.at)
  if p.also and su32(text, o + p.also) ~= v then return nil end
  return v
end
local function matches_at(text, segs)
  for j = 1, #segs do
    local seg = segs[j]
    if text:sub(seg[1] + 1, seg[1] + #seg[2]) ~= seg[2] then return false end
  end
  return true
end
local function cache_check(G, c)        -- the cached layout, each match read again from the game's code; nil: rescan
  local found, at = {}, {}
  for _, k in ipairs(P_ORDER) do
    local v, m = c[k], c['m_' .. k]
    if type(v) ~= 'number' or type(m) ~= 'string' or (v ~= -1) ~= (m ~= '') then return nil end
    for pi, o in m:gmatch('(%d+):(%d+)') do
      local p = P[k][tonumber(pi)]
      if not p then return nil end
      o = tonumber(o)
      local segs, _, n = compile(p.p)
      if o + n > G.code.size or not fetch(G.base + G.code.rva + o, n) then return nil end
      local text = bstr(0, n)
      if not matches_at(text, segs) or value_at(text, 0, p, G.code.rva + o) ~= v then return nil end
    end
    found[k], at[k] = v, m
  end
  return found, at
end
-- plausibility (on the scan and on the cache): the offsets inside the HUD are small, the open flag sits after the
-- list; the row stride's match is the row loop's (just after rowbase's) and the row id fits in a row. An optional item
-- that fails is dropped (-1) with a note; returns false when the layout can't be used at all.
local function near(m1, m2)
  for _, a in m1:gmatch('(%d+):(%d+)') do
    for _, b in m2:gmatch('(%d+):(%d+)') do
      local d = tonumber(b) - tonumber(a)
      if d > 0 and d < 0x80 then return true end
    end
  end
  return false
end
local function plausible(found, at, notes)
  if found.hud_a + found.hud_b > 0x1000000 or found.open < found.hud_c or found.rowbase > 0x1000 then return false end
  local st = found.rowstride
  if st ~= -1 and (st < 0x100 or st > 0x10000 or not near(at.rowbase, at.rowstride)) then
    found.rowstride, at.rowstride = -1, ''
    notes[#notes + 1] = string.format('rowstride %x not plausible%s', st, OPTIONAL.rowstride)
  end
  local id = found.rowid_r
  if id ~= -1 and (id < 8 or id + 4 > (found.rowstride ~= -1 and found.rowstride or KNOWN.rowstride)) then
    found.rowid_r, at.rowid_r = -1, ''
    notes[#notes + 1] = string.format('rowid_r %x not plausible%s', id, OPTIONAL.rowid_r)
  end
  -- (2.0.0) the UI items: all or none (HD2 HUD+'s panel needs every one); a context between 4 and 64 KiB, at most 32
  -- of them, the stack's top inside the context array's tail
  local bad, any, missing = nil, false, false
  for _, k in ipairs(HX_ITEMS) do
    if found[k] == -1 then missing = true else any = true end
  end
  if missing then bad = any and '' or nil      -- (the scan's own list says which one): the others are dropped too
  elseif (found.ui_stride < 0x1000 or found.ui_stride > 0x10000 or found.ui_slots < 1 or found.ui_slots > 32
      or found.ui_top < found.ui_stride * found.ui_slots or found.ui_top > found.ui_stride * found.ui_slots + 0x1000
      or found.ui_stack >= found.ui_top or found.ui_stack < found.ui_top - 64
      or found.ui_roots < 0x100 or found.ui_roots + 0x14 > found.ui_stride) then
    bad = string.format('UI contexts not plausible (%x x %d, top %x, stack %x, roots %x)', found.ui_stride,
      found.ui_slots, found.ui_top, found.ui_stack, found.ui_roots)
  end
  if bad then
    for _, k in ipairs(HX_ITEMS) do
      if found[k] ~= -1 then found[k], at[k] = -1, '' end
    end
    if bad ~= '' and not notes.hx then notes.hx = true; notes[#notes + 1] = bad .. OPTIONAL.ui_ctx end
  end
  return true
end

local L
local function resolve()
  local t0 = os.clock()
  local gmod = K32.SsGetModuleHandleA('game.dll')
  if gmod == nil then error('game.dll not loaded', 0) end
  local G = module_info(gmod)
  assert(G.code, 'no code section')
  local key = string.format('%08x-%08x-%08x', G.stamp, G.image, G.code.size)
  local found, at, how
  local c = cache_load()
  if c and c.key == key then
    found, at = cache_check(G, c)
    local notes = {}
    if found and plausible(found, at, notes) and #notes == 0 then
      how = 'cached for this game build (checked)'
    else
      found, how = nil, ' (the cache was out of date: scanned again)'
    end
  end
  if not found then
    local text = code_text(G)
    local why, moved = {}, {}
    found, at = {}, {}
    for _, name in ipairs(P_ORDER) do
      local val, disagree, where = nil, false, {}
      for pi, p in ipairs(P[name]) do
        local hits = find_all(text, p.p)
        -- (2.0.0) a function the compiler made twice (identical, calling the same function): the first one is used
        if p.twins and #hits > 1 then
          local function target(o) return o + p.twins + 5 + si32(text, o + p.twins + 1) end
          local same = true
          for j = 2, #hits do if target(hits[j]) ~= target(hits[1]) then same = false end end
          if same then hits = { hits[1] } end
        end
        for _, o in ipairs(hits) do
          local v = value_at(text, o, p, G.code.rva)
          if v == nil or (val and val ~= v) then disagree = true end
          val = val or v
          where[#where + 1] = pi .. ':' .. o
        end
      end
      if OPTIONAL[name] and (not val or disagree) then
        found[name], at[name] = -1, ''
        moved[#moved + 1] = name .. (disagree and ' disagrees' or ' not found') .. OPTIONAL[name]
      elseif not val then why[#why + 1] = name .. ' not found'
      elseif disagree then why[#why + 1] = name .. ': its places disagree'
      else
        found[name], at[name] = val, table.concat(where, ',')
        if KNOWN[name] ~= val then moved[#moved + 1] = string.format('%s %x -> %x', name, KNOWN[name], val) end
      end
    end
    text = nil
    collectgarbage()
    if #why > 0 then error(table.concat(why, '; '), 0) end
    if not plausible(found, at, moved) then error('layout not plausible', 0) end
    cache_save(key, found, at)
    how = 'found in the game code (' .. (key == KNOWN_BUILD and 'the September 2026 game build' or 'a new game build')
      .. (#moved == 0 and '; all as known)' or ('; moved: ' .. table.concat(moved, ', ') .. ')')) .. (how or '')
  end
  local A = {}
  for k, v in pairs(found) do if v ~= -1 then A[k] = v end end
  for _, k in ipairs({ 'rack', 'proj', 'hud' }) do A[k] = G.base + A[k] end
  for _, k in ipairs(HX_ITEMS) do
    if A[k] and (k:sub(1, 2) == 'w_' or k == 'ui_ctx' or k == 'ui_push' or k == 'ui_pop') then A[k] = G.base + A[k] end
  end
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
local BAR_TEXTURE             -- (1.1.0) the next shell's yellow bar on HD2 HUD+'s panel (set by the build)
--@@ICONS@@
SS.textures = {}
for _, k in ipairs(KINDS) do SS.textures[k.id] = k.texture end

local openings = 0            -- times the list opened (spoof builds move their shells on by one each time)
local SEAF_STRATAGEM = 28
local ROW_ID = SEAF_STRATAGEM   -- the stratagem id of the row the icons go on (spoof builds: the list's first row)

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

-- spoof builds: 5 shells (the most the artillery holds) from a cycle of every shell type, moving on by one each time
-- the list opens (the next one fired, a new type loaded at the back): over 6 openings each type is next once
local SPOOF_LOAD = { 'high_yield', 'mini_nuke', 'napalm', 'static_field', 'smoke', 'explosive' }
local SPOOF_HELD = 5
local function spoof_queue()
  local n, shift = #SPOOF_LOAD, math.max(0, openings - 1)
  local kinds, names, same = {}, {}, true
  for i = 1, SPOOF_HELD do
    kinds[i] = KIND[SPOOF_LOAD[(i - 1 + shift) % n + 1]]
    names[i] = kinds[i].name
    if kinds[i] ~= queue.kinds[i] then same = false end
  end
  if same and #queue.kinds == SPOOF_HELD then return false end
  queue.kinds = kinds
  event('SPOOF loaded shells (next first): ' .. table.concat(names, ', '))
  return true
end

local function read_queue()
  if SPOOF then return spoof_queue() end
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
-- ((1.0.1 review) the stride and the id's place come from the game code at start-up (resolve); the known ones are the
-- fallback. Without a stride from the code, a row only counts when it is the only one with the SEAF id.)
local ROWS, ROW_STRIDE, ID_AT, ROW_ONE = 16, KNOWN.rowstride, KNOWN.rowid_r, true
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
-- ((1.0.1 review) the overlay world is checked on every frame that calls a GUI function (a redraw or a clear), not only
-- once a second: a mission load can destroy it in between. GUIs whose world is gone are forgotten, never touched.)
-- The world is checked (and taken when there is none yet); false: no overlay world now.
local function gui_ready()
  gui.checked = stats.frames
  local target, live = overlay_world()
  if gui.world and not live then gui.world, gui.list, view.sig = nil, {}, nil end
  if not gui.world then
    if not target then gui.state = 'no overlay world'; return false end
    gui.world, gui.state, view.sig = target, 'screen GUIs in the overlay world', nil
  end
  return true
end
-- our GUIs emptied (the list closed, nothing to show, the mission is over): only if their world still exists
local function release_gui()
  if A and gui.world and next(gui.list) then
    local _, live = overlay_world()
    if not live then gui.world, gui.list = nil, {}; return end
  end
  clear_all()
end

-- ======================================================================================================
-- Every frame. List closed: two reads (the HUD manager pointer and the list's open flag). List open: also the SEAF row
-- and the list (two reads), the shells four times a second; drawing only when something moved or changed.
-- ======================================================================================================
local ready = not V19
local broken, last_error = false, nil
local hud, open_was = nil, false
local row = { at = nil, chain = nil, looked = -1, checked = 0, hud = nil }
local scanned_now = false     -- this frame ran the start-up scan (left out of the per-frame cost)
local floor = math.floor
-- another mod hiding the game's list (HD2 HUD+'s stratagem panel sets the list's group to opacity 0, a few frames after
-- the list opens): once seen (or when HD2 HUD+ is installed), each opening starts hidden and the icons only show once
-- the list's parents have stayed visible for half a second; the parents are read every frame right after opening
local HUDPLUS = 'mods/hd2_hud/hd2_hud_plus'
local cover = { known = nil, since = nil, fast_until = 0 }
local next_queue = 0
local stats_open = 0

local function find_seaf_row(first)   -- a row's stratagem id at ID_AT (its slot just before it)
  if SPOOF then                         -- the first row with a stratagem in it
    for i = 0, ROWS - 1 do
      local at = first + i * ROW_STRIDE
      if fetch(at + ID_AT, 4) and b32(0) > 0 and b32(0) < 0x10000 then
        ROW_ID = b32(0)
        return at, i
      end
    end
    return nil
  end
  local found, n = nil, 0
  for i = 0, ROWS - 1 do
    local at = first + i * ROW_STRIDE
    if fetch(at + ID_AT, 4) and b32(0) == SEAF_STRATAGEM then
      if not ROW_ONE then return at, i end
      n = n + 1
      found = found or i
    end
  end
  if n == 1 then return first + found * ROW_STRIDE, found end
  if n > 1 and not row.many then
    row.many = true
    event(string.format('%d rows have the SEAF Artillery id (the row stride is not from the game code): none used', n))
  end
  return nil
end

-- ======================================================================================================
-- (2.0.0) HD2 HUD+'s stratagem panel. HUD+ hides the game's stratagem list and shows its own copy: the game's own
-- stratagem panel, made by HUD+ in its own memory and filled by the game's own code (row ids included), in HUD+'s UI
-- context. The icons go on that panel's SEAF Artillery row as the game's own UI widgets: a frame holding the bar and
-- 5 pictures, made and attached with the game's own UI calls (found in the game code at start-up), the same way
-- HUD+ puts its own widgets on the game's rows. They then move, slide and fade with HUD+'s panel by themselves.
-- Nothing of HUD+ itself is used (no add-on, no HUD+ code or numbers), so a HUD+ update can't break this unless HUD+
-- stops using the game's stratagem panel. Safety: every game call is made only after reading (with the safe reader)
-- that what it touches is what it should be; our widgets live in our own memory, which is never freed; the frame
-- is re-attached when HUD+ rebuilds its rows; a marker file skips this once if a game ever closed while trying it.
-- ======================================================================================================
local hx_hide, hx_closed, hx_opened, hx_step, hx_line, hx_proven   -- (the panel's own locals stay inside this block)
do
local HX = { state = nil, detail = nil, off = nil, list = nil, row = nil, idx = nil, slot = nil, check = 0,
  tries = 0, turn = 0, lost = 0, skip = nil, base = nil, made = 0, attached = 0, found = 0, fshown = false, bshown = false,
  tex = {}, shown = {}, watch = nil, seen = false, ids = {} }
local HX_MAX = 5              -- icons: the artillery holds 5 shells at most
local HX_SPAN = 0x400         -- memory per widget (the game's frame needs 272 bytes, a picture 352: room to grow)
local HX_TRIES = 40           -- searches each opening at most (one context each, every frame)
local HX_WALK = 1000          -- widgets looked at, at most, in one context (HUD+'s has had 16 to 62)
local W_CHILD, W_NEXT, W_PARENT, W_CTX, W_LAYER = 0xe0, 0xe8, 0xf0, 0xf8, 0xbc   -- (in the call patterns too)
local COLOR_MATERIAL = '9448536c2d6ae780'   -- the game's picture material (one of its UI materials each widget
                                            -- gets its own copy of; 1.1.0 Test 3), shows a texture in its colors
local ICON, STEP, GAP = 58, 27, 12          -- row units (the row is 68 high): as on HD2 HUD+'s panel since 1.1.0
local HXCHECK = LOGDIR and (LOGDIR .. '\\' .. LOGNAME .. '.hudcheck') or nil

local function hx_note(state, detail)
  if state == HX.state and detail == HX.detail then return end
  HX.state, HX.detail = state, detail
  event('HD2 HUD+ panel: ' .. state .. (detail and (' (' .. detail .. ')') or ''))
end
function hx_line()
  local st = HX.off and ('off: ' .. HX.off) or HX.state
  if not st then return cover.hudplus and 'not needed yet (HUD+\'s stratagem list not opened)' or 'HD2 HUD+ not seen' end
  return st .. (HX.detail and (' (' .. HX.detail .. ')') or '')
    .. string.format('; found %d times, made %d, attached %d', HX.found, HX.made, HX.attached)
    .. (HX.most and string.format('; most widgets looked at in a frame %d', HX.most) or '')
end

-- our own memory (read and written directly: it's ours)
local PU64 = ffi.typeof('uint64_t *')
local function own_u32(at) return tonumber(cast(PU32, at)[0]) end
local function own_ptr(at)
  local v = tonumber(cast(PU64, at)[0])
  if v < 65536 or v >= 140737488355328 then return nil end
  return v
end
local function own_zero(at) cast(PU64, at)[0] = 0 end
local HXMEM                   -- kept for the whole session, never freed: the game keeps pointers into it
local HXW
local function hx_memory()
  if HXW then return HXW end
  HXMEM = ffi.new('uint8_t[?]', HX_SPAN * (2 + HX_MAX) + 16)
  local base = tonumber(ffi.cast('uintptr_t', HXMEM))
  base = base + (16 - base % 16) % 16
  -- children are kept in address order and drawn in it: the bar first, then icon 5 .. icon 1 (the next shell on top)
  HXW = { frame = base, bar = base + HX_SPAN, icon = {} }
  for j = 1, HX_MAX do HXW.icon[j] = base + HX_SPAN * (2 + HX_MAX - j) end
  return HXW
end

-- the game's UI calls (function pointers into game.dll, found by their code at start-up)
local HXF
local PAIR = ffi.new('union { float f[2]; uint64_t u; }')
local function hx_calls()
  if HXF ~= nil then return HXF end
  HXF = false
  if not (L.ui_ctx and L.w_detach) then return false end
  local ok = pcall(function()
    local c = ffi.cast
    HXF = {
      push = c('void (*)(uint64_t, uint8_t)', L.ui_push), pop = c('void (*)(void)', L.ui_pop),
      init = c('void (*)(uint64_t, int32_t)', L.w_init), pinit = c('void (*)(uint64_t)', L.w_pinit),
      pset = c('void (*)(uint64_t, uint64_t, uint64_t, uint8_t)', L.w_pset),
      size = c('void (*)(uint64_t, uint64_t)', L.w_size), anchor = c('void (*)(uint64_t, uint64_t)', L.w_anchor),
      pivot = c('void (*)(uint64_t, uint64_t)', L.w_pivot), pos = c('void (*)(uint64_t, uint64_t)', L.w_pos),
      layer = c('void (*)(uint64_t, int16_t)', L.w_layer), shown = c('void (*)(uint64_t, uint8_t)', L.w_shown),
      opacity = c('void (*)(uint64_t, float)', L.w_opacity),
      attach = c('void (*)(uint64_t, uint64_t)', L.w_attach), detach = c('void (*)(uint64_t)', L.w_detach),
    }
  end)
  if not ok then HXF = false end
  return HXF
end
local function pair(fn, at, x, y) PAIR.f[0], PAIR.f[1] = x, y; fn(at, PAIR.u) end
local function hx_id(hex)     -- a resource id (16 hex digits) as the game's uint64
  local v = HX.ids[hex]
  if v == nil then
    v = ffi.new('uint64_t', tonumber(hex:sub(1, 8), 16)) * 4294967296 + tonumber(hex:sub(9, 16), 16)
    HX.ids[hex] = v
  end
  return v
end
local function hx_loaded(kind, hex)
  local App, IDS = SR and rawget(SR, 'Application'), SR and rawget(SR, 'IdString64')
  if type(App) ~= 'table' or type(IDS) ~= 'table' then return false end
  local ok, id = pcall(IDS.from_hex, hex)
  if not ok then return false end
  local okc, yes = pcall(App.can_get, kind, id)
  return okc and yes == true
end

-- foreign memory, read safely
local function bu64(o) return b32(o) + b32(o + 4) * 4294967296 end
local function i32_at(addr)
  if not fetch(addr, 4) then return nil end
  local v = b32(0)
  return v >= 2147483648 and v - 4294967296 or v
end
local function alive(at) return fetch(at, 4) and b32(0) ~= 0 end
local function child_of(parent, w)          -- w is among parent's children
  local c = read_ptr(parent + W_CHILD)
  for _ = 1, 256 do
    if not c then return false end
    if c == w then return true end
    c = read_ptr(c + W_NEXT)
  end
  return false
end
local function slot_of(ctx)
  if not ctx or not HX.base then return nil end
  local d = ctx - HX.base
  if d < 0 or d % L.ui_stride ~= 0 or d / L.ui_stride >= L.ui_slots then return nil end
  return d / L.ui_stride
end

-- fn() run with UI context `slot` pushed, as the game and HUD+ do while making widgets: the push and the pop are
-- checked (the stack's top and its new slot); false, why when it couldn't be done
local function hx_within(slot, fn)
  local base = HX.base
  if read_ptr(L.ui_ctx) ~= base then return false, 'the UI contexts moved' end
  if not fetch(base + slot * L.ui_stride, 1) or b8(0) ~= 1 then return false, 'context not live' end
  local top_at = base + L.ui_top
  local top = i32_at(top_at)
  if not top or top < -1 or top >= L.ui_top - L.ui_stack then return false, 'context stack' end
  HXF.push(base, slot)
  if i32_at(top_at) ~= top + 1 or not fetch(base + L.ui_stack + top, 1) or b8(0) ~= slot then
    if i32_at(top_at) == top + 1 then HXF.pop() end
    return false, 'context push'
  end
  local ok, err = pcall(fn)
  if read_ptr(L.ui_ctx) == base and i32_at(top_at) == top + 1 then HXF.pop() end
  if i32_at(top_at) ~= top then return false, 'context pop' end
  if not ok then return false, tostring(err) end
  return true
end

-- the roots of context ctx: a small set near its end (the game's own: data, or its distance back with flag 4;
-- capacity; empty mark; flags), each root a widget of that context
local found_roots = {}
local function hx_roots(ctx)
  local set, out = ctx + L.ui_roots, found_roots
  if not fetch(set, 0x14) then return 0 end
  local off, cap, empty, flags = bu64(0), b32(8), b32(12), b32(16)
  if cap == 0 or cap > 1024 then return 0 end
  local data = bit.band(flags, 4) ~= 0 and (set - off) or off
  if not fetch(data, cap * 8) then return 0 end
  local n = 0
  for k = 0, cap - 1 do
    local w = bu64(k * 8)
    if w ~= empty and w >= 65536 and w < 140737488355328 then n = n + 1; out[n] = w end
  end
  local m = 0
  for i = 1, n do
    local w = out[i]; out[i] = nil
    if read_ptr(w + W_CTX) == ctx then m = m + 1; out[m] = w end
  end
  return m
end
-- (Test 2) a widget is on screen: it and every widget above it shown, their opacities not (nearly) 0
local function hx_visible(w)
  local a = 1
  for _ = 1, 32 do
    if not fetch(w, W_CTX) or bit.band(b32(0), 0x10) == 0 then return false end
    a = a * (bf32(OPACITY) or 0)
    local q = bptr(W_PARENT)
    if not q then return a > 0.01 end
    w = q
  end
  return false
end
-- (Test 2) the game's own list's row ids (the player's stratagems), read on search frames: HUD+'s panel shows the same
-- player's list. (Test 1 found other copies of the game's stratagem panel first, in contexts 6 and 7.)
local want = {}
local function hx_want(game_list)
  local base = game_list + L.rowbase + ID_AT
  for k = 0, ROWS - 1 do want[k] = fetch(base + k * ROW_STRIDE, 4) and b32(0) or 0 end
end
local told = {}                                    -- (TESTER) why a context's list wasn't taken, once each opening
local function hx_tell(slot, why)
  local key = slot .. why                         -- (each reason once per context and opening)
  if TESTER and not told[key] then told[key] = true; event(string.format('HD2 HUD+ panel: context %d: %s', slot, why)) end
end
-- the stratagem list in context `slot` showing the player's list, on screen: a widget whose first row (inside it)
-- hangs under it, its row ids the game list's, our row (by its id) on screen; a depth-first walk from the roots.
-- Returns the list, the row, its index, the widgets looked at; or nil, true when the player's list is there but
-- not on screen yet (it fades in as the list opens)
local function hx_search(slot)
  local ctx = HX.base + slot * L.ui_stride
  if not fetch(ctx, 1) or b8(0) ~= 1 then return nil end
  local stack, visited = found_roots, {}            -- (visited: a broken link loop is walked once)
  local n, seen = hx_roots(ctx), 0
  local rb, hit, at, idx, onlist = L.rowbase, nil, nil, nil, false
  while n > 0 and seen < HX_WALK do
    local w = stack[n]; stack[n] = nil; n = n - 1
    if visited[w] then goto next end
    visited[w] = true
    seen = seen + 1
    -- one read per widget ((2.0.0 review)): its links and, for a list, its first row's parent
    local child, sib, list
    if fetch(w, rb + W_PARENT + 8) then
      child, sib, list = bptr(W_CHILD), bptr(W_NEXT), bptr(rb + W_PARENT) == w
    elseif fetch(w + W_CHILD, 16) then
      child, sib = bptr(0), bptr(8)
    end
    if list then
      local same, mine, r = 0, nil, nil
      for k = 0, ROWS - 1 do
        local id = fetch(w + rb + k * ROW_STRIDE + ID_AT, 4) and b32(0) or 0
        if id ~= 0 and want[k] ~= 0 and id ~= want[k] then same = -1; break end
        if id ~= 0 and id == want[k] then same = same + 1 end
        if id == ROW_ID and not mine then mine = k end
      end
      if same <= 0 or not mine then
        hx_tell(slot, same < 0 and 'a stratagem list, not the player\'s' or 'a stratagem list without our row (yet)')
      else
        r = w + rb + mine * ROW_STRIDE
        if read_ptr(r + W_PARENT) ~= w then hx_tell(slot, 'our row does not hang under its list')
        elseif not hx_visible(r) then onlist = true; hx_tell(slot, 'the player\'s list, not on screen')
        else hit, at, idx = w, r, mine; break end
      end
    end
    if sib then n = n + 1; stack[n] = sib end
    if child then n = n + 1; stack[n] = child end
    ::next::
  end
  for k = n, 1, -1 do stack[k] = nil end
  if hit then return hit, at, idx, seen end
  return nil, onlist, nil, seen
end
-- the row is still the SEAF row of the list it was found in, and that list still hangs (through live widgets of the
-- row's context) from one of the context's roots: HUD+ drops its panel when it rebuilds it elsewhere
local function hx_row_ok()
  local r, x = HX.row, HX.list
  if not (alive(r) and read_ptr(r + W_PARENT) == x and fetch(r + ID_AT, 4) and b32(0) == ROW_ID) then return false end
  local ctx = read_ptr(r + W_CTX)
  if not ctx then return false end
  local p = x
  for _ = 1, 32 do
    if not fetch(p, W_CTX + 8) or b32(0) == 0 or bptr(W_CTX) ~= ctx then return false end
    local q = bptr(W_PARENT)
    if not q then
      local n, yes = hx_roots(ctx), false
      for k = 1, n do
        if found_roots[k] == p then yes = true end
        found_roots[k] = nil
      end
      return yes
    end
    p = q
  end
  return false
end
-- our frame hangs under the row, in the row's context
local function hx_attached()
  local F = HXW and HXW.frame
  if not F or own_u32(F) == 0 or own_ptr(F + W_PARENT) ~= HX.row then return false end
  return own_ptr(F + W_CTX) == read_ptr(HX.row + W_CTX) and child_of(HX.row, F)
end

-- the game's checks, once: the calls, our memory, the material and textures loaded, and the marker file
local function hx_ready()
  if HX.ready ~= nil then return HX.ready end
  local why
  if not hx_calls() then why = 'the game\'s UI calls were not found in its code'
  elseif not hx_loaded('material', COLOR_MATERIAL) then
    hx_note('waiting', 'the game\'s picture material is not loaded yet'); return false
  else
    local missing = {}
    for _, k in ipairs(KINDS) do if not k.texture or not hx_loaded('texture', k.texture) then missing[#missing + 1] = k.id end end
    if not BAR_TEXTURE or not hx_loaded('texture', BAR_TEXTURE) then missing[#missing + 1] = 'bar' end
    if #missing > 0 then why = 'our textures are not loaded: ' .. table.concat(missing, ', ') end
  end
  if not why and HXCHECK then
    local f = io.open(HXCHECK, 'r')
    local last = f and f:read('*a'); if f then f:close() end
    if last and last:find('^trying') then
      why = 'skipped this start: the last game closed while trying it (tried again next start)'
      f = io.open(HXCHECK, 'w'); if f then f:write('skipped once\n'); f:close() end
    else
      f = io.open(HXCHECK, 'w'); if f then f:write('trying\n'); f:close() end
      HX.watch = 60
    end
  end
  if why then HX.off = why; event('HD2 HUD+ panel: off: ' .. why); HX.ready = false; return false end
  hx_memory()
  HX.ready = true
  return true
end
function hx_proven(closing)
  -- ((2.0.0 review) a normal close proves there was no crash, shown or not)
  if HX.watch and (HX.seen or closing) and HXCHECK then
    HX.watch = nil
    local f = io.open(HXCHECK, 'w'); if f then f:write('ok\n'); f:close() end
  end
end

-- our frame's parent checks out for a game call on the frame (show/hide, detach): the frame alive, its parent alive,
-- in the frame's context and listing it, and that context live ((2.0.0 review) no row id needed: hiding must also
-- work when HUD+'s row already shows another stratagem)
local function hx_parent_ok()
  local F = HXW.frame
  local p, ctx = own_ptr(F + W_PARENT), own_ptr(F + W_CTX)
  if own_u32(F) == 0 or not p or not ctx or not slot_of(ctx) then return false end
  if not fetch(ctx, 1) or b8(0) ~= 1 then return false end
  if not fetch(p, W_CTX + 8) or b32(0) == 0 or bptr(W_CTX) ~= ctx then return false end
  return child_of(p, F)
end
-- our frame taken off whatever it hangs under: detached by the game when its parent still lists it (and checks out);
-- links cleared by us when its parent no longer has it (HUD+ rebuilt the row in place). false: left as it was
local function hx_unlink()
  local F = HXW.frame
  local p = own_ptr(F + W_PARENT)
  if not p then return true end
  if own_u32(F) ~= 0 and alive(p) and child_of(p, F) then
    if not hx_parent_ok() then return false end
    HXF.detach(F)
    if child_of(p, F) then return false end
  end
  own_zero(F + W_NEXT); own_zero(F + W_PARENT)
  return true
end
-- the frame, bar and icons made (in the row's context) and laid out
local function hx_make(layer)
  local M, f = HXW, HXF
  local F = M.frame
  f.init(F, 1)
  f.pinit(M.bar)
  for j = 1, HX_MAX do f.pinit(M.icon[j]) end
  pair(f.anchor, F, 1, 0.5); pair(f.pivot, F, 0, 0.5); pair(f.pos, F, GAP, 0)
  pair(f.size, F, ICON + STEP * (HX_MAX - 1), ICON)
  pair(f.anchor, M.bar, 0, 0); pair(f.pivot, M.bar, 0, 0.5); pair(f.pos, M.bar, ICON * 0.18, 0)
  pair(f.size, M.bar, ICON * 0.64, 3); f.layer(M.bar, layer); f.shown(M.bar, 0)
  f.attach(F, M.bar)
  for j = HX_MAX, 1, -1 do
    local at = M.icon[j]
    pair(f.anchor, at, 0, 0.5); pair(f.pivot, at, 0, 0.5); pair(f.pos, at, (j - 1) * STEP, 0)
    pair(f.size, at, ICON, ICON); f.layer(at, layer); f.opacity(at, j == 1 and 1 or 0.82); f.shown(at, 0)
    f.attach(F, at)
  end
end
local function hx_attach()
  local R, F = HX.row, HXW.frame
  local ctx = read_ptr(R + W_CTX)
  local slot = slot_of(ctx)
  if not slot then hx_note('not shown', 'the row\'s UI context is not one of the game\'s'); return false end
  if not hx_unlink() then hx_note('not shown', 'our frame could not be taken off its old row'); return false end
  local fresh = own_u32(F) == 0 or own_ptr(F + W_CTX) ~= ctx
  -- the layer: one above the highest among the row's widgets (its card and texts, at any depth), so the icons are
  -- drawn on top of the row ((Test 2) Test 1 looked only at the row's direct children: 0 on HUD+'s rows)
  local layer, stack, k = 0, { read_ptr(R + W_CHILD) }, 0
  while #stack > 0 and k < 256 do
    local c = stack[#stack]; stack[#stack] = nil; k = k + 1
    if c and fetch(c + W_LAYER, W_NEXT + 8 - W_LAYER) then
      local v = BUF[0] + BUF[1] * 256
      if v < 32768 and v > layer then layer = v end
      local sib, child = bptr(W_NEXT - W_LAYER), bptr(W_CHILD - W_LAYER)
      if sib then stack[#stack + 1] = sib end
      if child then stack[#stack + 1] = child end
    end
  end
  layer = math.min(layer + 1, 32767)
  if fresh then
    -- ((2.0.0 review) the caches go before the calls: picture_init clears a picture's texture, and the make may have
    -- run even when the context pop check fails; nil = not known, set again)
    HX.fshown, HX.bshown, HX.btex = nil, nil, nil
    for j = 1, HX_MAX do HX.tex[j], HX.shown[j] = nil, nil end
  end
  local ok, why = hx_within(slot, function()
    if fresh then hx_make(layer) end
    HXF.attach(R, F)
  end)
  if fresh and ok then
    HX.made = HX.made + 1
    if TESTER then event(string.format('HD2 HUD+ panel: icons made in UI context %d (layer %d)', slot, layer)) end
  end
  if not ok or not hx_attached() then
    hx_note('not shown', why or 'our frame did not attach')
    return false
  end
  HX.attached = HX.attached + 1
  return true
end
-- the textures and what's shown, set only where they changed
local function hx_show()
  local M, f, kinds = HXW, HXF, queue.kinds
  local mat = hx_id(COLOR_MATERIAL)
  for j = 1, HX_MAX do
    local k = kinds[j]
    local tex = k and k.texture
    if tex and tex ~= HX.tex[j] then f.pset(M.icon[j], mat, hx_id(tex), 0); HX.tex[j] = tex end
    if (tex ~= nil) ~= HX.shown[j] then f.shown(M.icon[j], tex and 1 or 0); HX.shown[j] = tex ~= nil end
  end
  local bar = #kinds > 0
  if bar and not HX.btex then f.pset(M.bar, mat, hx_id(BAR_TEXTURE), 0); HX.btex = true end
  if bar ~= HX.bshown then f.shown(M.bar, bar and 1 or 0); HX.bshown = bar end
  if HX.fshown ~= true then f.shown(M.frame, 1); HX.fshown = true end
end
-- hidden (the icons turned off, no shells): only when the call is safe (the frame hangs nowhere, or its parent
-- checks out); otherwise tried again up to four times a second ((2.0.0 review) Test 2 marked it hidden either way)
function hx_hide()
  if HX.fshown == false or not HXF or not HXW then return end
  local now = os.clock()
  if now < (HX.hide_next or 0) then return end
  HX.hide_next = now + 0.25
  local F = HXW.frame
  if own_u32(F) == 0 then HX.fshown = false; return end      -- not alive: not drawn, made again before showing
  if not own_ptr(F + W_PARENT) or hx_parent_ok() then HXF.shown(F, 0); HX.fshown = false end
end
-- the list closed (or the addon stops): our frame taken off HUD+'s row, so it never hangs under memory nobody checks
-- ((2.0.0 review)); hidden instead when that can't be done now
function hx_closed()
  HX.check = 0
  if not HXF or not HXW then return end
  if own_ptr(HXW.frame + W_PARENT) and not hx_unlink() then hx_hide() end
end
-- each opening ((2.0.0 review) whatever the shells and the options, so an opening that gets its shells late still
-- searches)
function hx_opened(game_list)
  if HX.off then return end
  local missed = HX.max ~= nil and HX.tries > 0 and not HX.row
  HX.max = missed and 12 or HX_TRIES              -- fewer searches after an opening that found nothing
  HX.tries, HX.turn, HX.check, HX.lost = 0, 0, 0, 0
  for k in pairs(told) do told[k] = nil end
  HX.base = read_ptr(L.ui_ctx)
  HX.skip = slot_of(read_ptr(game_list + W_CTX))     -- the game's own list: not HUD+'s
end

-- every frame while the list is open with shells loaded and the icons on
function hx_step(now, changed, game_list)
  if HX.off then return end
  -- the marker file: 'ok' once the icons have been up on HUD+'s panel for 60 frames
  if HX.watch and HX.seen and HX.fshown and HX.row then
    HX.watch = HX.watch - 1
    if HX.watch <= 0 then hx_proven() end
  end
  local due = changed or now >= HX.check
  if HX.row and due then
    HX.check = now + 0.25
    if not hx_row_ok() then
      -- the row moved, or HUD+ rebuilt its panel: off the old row now, then searched for again (a few times each
      -- opening at most)
      HX.row = nil
      if HXF and HXW and not hx_unlink() then hx_hide() end
      if HX.lost < 3 then HX.lost, HX.tries = HX.lost + 1, 0 end
      if TESTER then event('HD2 HUD+ panel: the row or panel changed; looking again') end
    end
  end
  if not HX.row then
    if not (cover.hudplus and cover.known) or not HX.base or HX.tries >= (HX.max or HX_TRIES) then return end
    if SPOOF and not row.at then return end          -- (spoof: our row is the game list's first, found there first)
    HX.tries = HX.tries + 1
    -- one context a frame: the one HUD+'s panel was in last time every other frame, the others in turn between
    local slot = HX.slot
    if not slot or HX.tries % 2 == 0 then
      for _ = 1, L.ui_slots do        -- (a context that isn't live costs no frame)
        HX.turn = HX.turn % L.ui_slots + 1
        slot = HX.turn - 1
        if slot ~= HX.skip and slot ~= HX.slot and fetch(HX.base + slot * L.ui_stride, 1) and b8(0) == 1 then break end
      end
    end
    if slot == HX.skip then return end
    hx_want(game_list)
    local x, at, i, seen = hx_search(slot)
    if TESTER and seen > (HX.most or 0) then HX.most = seen end
    if not x then
      if at then HX.slot = slot end            -- the player's list, not on screen yet: tried every other frame
      if HX.tries >= (HX.max or HX_TRIES) then hx_note('HUD+\'s panel not found', 'is its stratagem panel option off?') end
      return
    end
    if not hx_ready() then HX.tries = HX_TRIES; return end
    HX.found = HX.found + 1
    if TESTER or HX.found == 1 then                 -- (the first find; every one in Tester builds)
      event(string.format('HD2 HUD+ panel: found in UI context %d (row %d; %d widgets looked at, try %d)', slot, i, seen, HX.tries))
    end
    HX.list, HX.row, HX.idx, HX.slot, HX.check = x, at, i, slot, now + 0.25
    due = true
  end
  if not due or not hx_ready() then return end
  if not hx_attached() and not hx_attach() then HX.row = nil; return end
  hx_show()
  hx_note('showing', 'row ' .. tostring(HX.idx))
  HX.seen = true
end
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
  -- the HUD is gone or replaced (a new mission): nothing to put back, the row's memory isn't the HUD's any more
  if open == nil or hud ~= fix.hud then fix.pending, fix.kind = nil, nil; return end
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
    scanned_now = true
    local ok, res = pcall(resolve)
    if not ok then broken, last_error, SS.status = true, 'could not find the game addresses: ' .. tostring(res), 'off'; event(last_error); return end
    L = res
    ROW_STRIDE, ROW_ONE = L.rowstride or KNOWN.rowstride, not L.rowstride
    ID_AT = L.rowid_r and L.rowid_r == L.rowid_w and L.rowid_r or KNOWN.rowid_r
    event('game addresses: ' .. session.layout .. string.format(' (%.2f s)', session.scan_seconds))
  end
  -- both off in the options menu: the addresses are still found at start-up (no hitch when turned on), nothing else
  if not enabled and not fix_name then
    hx_hide()
    if fix.pending then fix_restore() end
    if open_was then
      release_gui(); open_was = false; view.sig = nil; row.at, row.looked, row.told = nil, -1, nil
    end
    SS.status = 'off (options menu)'
    return
  end
  -- ((1.0.1 review) the HUD manager pointer is read every frame (one 8-byte read; it was kept for a second): a new
  -- mission frees the old HUD, and the name fix could write through the old pointer into freed memory. A new pointer
  -- drops the row and the drawing found in the old HUD.)
  local h = read_ptr(L.hud)
  if h ~= hud then
    if TESTER and hud and h then event('the HUD manager changed (a new mission): the row is looked for again') end
    hud = h
    if view.sig then release_gui(); view.sig = nil end
    row.at, row.looked, row.told, row.hud = nil, -1, nil, nil
  end
  local parent = hud and hud + L.hud_a + L.hud_b
  local open = parent and fetch(parent + L.open, 1) and b8(0) or nil
  fix_settle(now, open and open == 1)
  if open ~= 1 then
    if open_was then
      hx_closed()
      release_gui()                              -- ((1.0.1 review) both ways: the world is checked first)
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
    openings = openings + 1
    hx_opened(parent + L.hud_c)
    cover.fast_until, cover.since, row.alpha = now + 0.6, nil, nil
    if cover.known == nil then
      local ok, found = pcall(function() return SR.Application.can_get('lua', HUDPLUS) end)
      cover.known = ok and found == true
      cover.hudplus = cover.known
      if cover.known then event('HD2 HUD+ is installed: the icons wait until the game\'s list is really showing') end
    end
  end
  -- the icons need the engine's GUI functions and the overlay world (the name fix doesn't)
  local icons_on = enabled and api_ok()
  if icons_on and (opened or now >= gui.next_check) then          -- (once a second even while there's no world)
    gui.next_check = now + 1
    gui_ready()
  end
  -- ((1.0.1 review) no overlay world: no icons on any frame until a check finds one, not just on the check frame)
  if not gui.world then icons_on = false end
  -- the loaded shells: when the list opens and four times a second while it's open
  local changed = false
  if opened or now >= next_queue then
    next_queue = now + 0.25
    changed = read_queue()
  end
  if #queue.kinds == 0 or not enabled then hx_hide() end
  if #queue.kinds == 0 then
    if view.sig then release_gui(); view.sig = nil end
    fix.kind = nil                               -- a new mission starts the name fix afresh
    return
  end
  -- (2.0.0) HD2 HUD+'s stratagem panel (its own copy of the list, which it shows instead of the game's)
  if enabled then hx_step(now, changed, parent + L.hud_c) end
  -- the row still shows SEAF Artillery (checked when the shells change and once a second)
  if row.at and fix.pending ~= row.at and (changed or now >= row.checked) then
    row.checked = now + 1
    if not fetch(row.at + ID_AT, 4) or b32(0) ~= ROW_ID then
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
        row.at, row.chain, row.checked, row.alpha, row.wr, row.wl, row.hud = at, chain, now + 1, nil, {}, {}, hud
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
    if view.sig then release_gui(); view.sig = nil end
    return
  end
  -- the name fix: once each time the next shell changes (and once per mission), while the list is open
  local front = queue.kinds[1]
  if fix_name and not SPOOF and not fix.off and L.rowid_r and L.rowid_r == L.rowid_w
     and not fix.pending and front ~= fix.kind and row.hud == hud then
    -- ((1.0.1 review) the HUD manager read again right before the write: the row must still be in the current HUD)
    if read_ptr(L.hud) == hud and fetch(row.at + ID_AT - 4, 8) and b32(4) == SEAF_STRATAGEM then
      local slot = b32(0)
      if write_u32(row.at + ID_AT, 0) then
        fix.kind, fix.pending, fix.hud, fix.slot, fix.until_, fix.done = front, row.at, hud, slot, now + 0.5, fix.done + 1
        row.checked = now + 1                    -- our own row check waits for the game to put the id back
        event('name fix: had the game redo the row\'s name (next shell: ' .. front.name .. ')')
      end
    end
  end
  if not icons_on then
    if view.sig then release_gui(); view.sig = nil end
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
    -- ((1.0.1 review) the overlay world checked before drawing (unless this frame's check already did): gone means
    -- nothing drawn until a check finds the next one)
    if gui.checked ~= stats.frames and not gui_ready() then return end
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
    or (not (L.rowid_r and L.rowid_r == L.rowid_w) and 'off (the game\'s row update changed; not found)')
    or 'ready', string.format('; names redone %d (game writes %d)', fix.done, stats.writes), '\n')
  f:write('HD2 HUD+ panel: ', hx_line(), '\n')
  f:write('game addresses: ', tostring(session.layout), session.scan_seconds and string.format(' (%.2f s)', session.scan_seconds) or '', '\n')
  f:write('drawing: ', gui.state, '; ', tostring(gui.icon_state or 'icons not tried yet'),
          gui.update ~= nil and ('; bitmaps ' .. (gui.update and 'moved in place' or 'replaced')) or '', '\n')
  if T.n > 0 then
    f:write(string.format('cost per frame (not the start-up scan): average %.4f ms (list open %.4f ms), highest %.3f ms, frames over 1 ms: %d\n',
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
      if scanned_now then
        scanned_now = false                      -- ((1.0.1 review) the start-up scan has its own time in the log; its
      else                                       -- frame no longer counts as the highest frame cost)
        local ms = tonumber(q[0] - a) / per_ms
        T.n, T.sum = T.n + 1, T.sum + ms
        if open_was then T.open_n, T.open_sum = T.open_n + 1, T.open_sum + ms end
        if ms > T.max then T.max = ms end
        if ms > 1 then T.over = T.over + 1 end
      end
    end
    if not ok then
      broken, last_error, SS.status = true, 'tick: ' .. tostring(e), 'off'
      pcall(hx_closed)                           -- (2.0.0) HD2 HUD+'s panel never keeps an old list
      event(last_error)
      pcall(release_gui)                         -- ((1.0.1 review) the world checked first here too)
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
    pcall(hx_proven, true)
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
if SPOOF then event('SPOOF test build: made-up shells (every type) on the stratagem list\'s first row; the name fix is off') end
pcall(write_log)
