local HD2_HUD_ADDON = "mods/chef/seaf_artillery_loadout_hudplus"
-- SEAF Artillery Loadout: the HD2 HUD+ add-on. HD2 HUD+ finds this resource by its first line and merges the part it
-- returns: one screen that puts the loaded shells next to the SEAF Artillery row of HUD+'s own stratagem panel.
-- The shells themselves come from the SEAF Artillery Loadout addon (Bingus Shared Loader), which already reads them
-- (patch-proof); this part only finds HUD+'s row and draws. Without that addon, or with nothing loaded, it shows nothing.
-- (1.1.1) Made to keep working across HD2 HUD+ versions:
--  * Memory is read through the SEAF Artillery Loadout addon (ReadProcessMemory: a bad address fails cleanly), never
--    through HUD+'s own reader, whose calls change between versions (0.2.4 dropped span/pointer_in) and which, from
--    0.2.4 on, reads memory directly (a bad address would crash the game).
--  * HUD+ takes a part only when its pin (the game build HUD+ was made for) matches its own. Rather than a fixed pin,
--    this part checks that the HUD+ build that loads it still has everything it uses (the sources, numbers and
--    features below) and then takes that build's pin. If something is missing it is refused cleanly (HUD+ itself is
--    unaffected) and the log says what. Without Lua's debug library it falls back to the pin of the HUD+ build it was
--    tested on.
local VERSION = '1.1.1'

local MAX = 5                 -- icons shown: the artillery holds 5 shells at most
local SEAF = 28               -- the SEAF Artillery stratagem's id in a list row
local WALK_LIMIT = 4000       -- widgets looked at, at most, when looking for HUD+'s list
local floor = math.floor
-- The icons' material: the game's picture_material (its comms pictures) shows a texture in its own colors; HUD+'s
-- flat_ammo_icon_material draws it as a white glyph (Test 1). picture_set puts the texture in slot 3aa8b87e of the
-- widget's material, and the game gives each widget its own copy only for its 14 built-in UI materials (the list at
-- game.dll 0x21cf7e0, which has both of these): Test 2's yellow_logo isn't one, so all the icons shared one copy and
-- showed the last shell set. Used once the game has it loaded; HUD+'s glyph material otherwise.
local COLOR_MATERIAL, GLYPH_MATERIAL = '9448536c2d6ae780', '358512d85e35b47d'
local function material_of(buf, opening)
  -- ((1.1.0 review) checked once each time the list opens, not every frame while it isn't loaded)
  if buf.material == COLOR_MATERIAL or (buf.material and buf.material_at == opening) then return buf.material end
  buf.material_at = opening
  local SR = rawget(_G, 'stingray')
  local App, ID = SR and rawget(SR, 'Application'), SR and rawget(SR, 'IdString64')
  local ok, id = pcall(function() return ID.from_hex(COLOR_MATERIAL) end)
  local okc, yes = false, false
  if ok then okc, yes = pcall(App.can_get, 'material', id) end
  buf.material = (okc and yes == true) and COLOR_MATERIAL or GLYPH_MATERIAL
  return buf.material
end

-- what this part tells the SEAF Artillery Loadout addon (its log): state changes and the list search
local function tell(buf, state, detail)
  if buf.state == state and detail == nil then return end
  buf.state = state
  local S = rawget(_G, 'ChefSeafArtilleryLoadout')
  local note = S and rawget(S, 'hudplus_note')
  if type(note) == 'function' then pcall(note, state, detail) end
end

-- Memory: the SEAF Artillery Loadout addon's safe reader (ReadProcessMemory on the game's own process: a bad address
-- returns nil instead of crashing). mem.bytes(address, size) -> a string, decoded here; mem.ptr(address) and
-- mem.u32(address) read one value without making a string ((1.1.1 review) the row check every frame uses these).
local byte = string.byte
local function u32(s, at) local a, b, c, d = byte(s, at + 1, at + 4); return a + b * 256 + c * 65536 + d * 16777216 end
local function u64(s, at) return u32(s, at + 4) * 4294967296 + u32(s, at) end
local function ptr_in(s, at)
  local p = u64(s, at)
  if p < 0x10000 or p >= 0x800000000000 then return nil end
  return p
end

-- the SEAF row of the stratagem list whose rows hang under widget x: i first (the game list's own row), then all 16
local function row_of(mem, x, i, lay, parent_at, want)
  local function at(k)
    local r = x + lay.rowbase + k * lay.stride
    if mem.ptr(r + parent_at) ~= x or mem.u32(r + lay.id) ~= want then return nil end
    return r
  end
  if i ~= nil then
    local r = at(i)
    if r then return r, i end
  end
  for k = 0, 15 do
    local r = at(k)
    if r then return r, k end
  end
  return nil
end

-- HUD+'s stratagem list: the widget whose first row's parent is itself, somewhere under the roots of HUD+'s world
-- context (UI context slot 10: its own GUI). The roots are kept in a small set at the end of the context:
-- {u64 data (or its distance back, flag 4), u32 capacity, u32 empty mark, u32 flags}. Widgets: first child at
-- parent link -0x10, next sibling at -8 (the game's widget_attach), alive while their first u32 isn't 0.
local function find_list(mem, buf, ctx, n, lay, i, want)
  local t0 = os.clock()
  local set = ctx + n.stride - 0x18
  local head = mem.bytes(set, 0x14)
  if head == nil then return nil, 'the world context could not be read' end
  local off, cap, empty, flags = u64(head, 0), u32(head, 8), u32(head, 12), u32(head, 16)
  if cap == 0 or cap > 1024 then return nil, 'the world context has no roots' end
  local data = (floor(flags / 4) % 2 == 1) and (set - off) or off
  local keys = mem.bytes(data, cap * 8)
  if keys == nil then return nil, 'the world context roots could not be read' end
  local stack, seen = {}, 0
  for k = 0, cap - 1 do
    local w = u64(keys, k * 8)
    if w ~= empty and w > 0x10000 then
      if mem.ptr(w + n.context) == ctx then stack[#stack + 1] = w end
    end
  end
  local roots = #stack
  if roots == 0 then
    return nil, string.format('no roots in HUD+\'s world context (capacity %d, flags %d, empty %d)', cap, flags, empty)
  end
  local link = n.parent - 0x10
  while #stack > 0 and seen < WALK_LIMIT do
    local w = stack[#stack]
    stack[#stack] = nil
    seen = seen + 1
    if mem.ptr(w + lay.rowbase + n.parent) == w then
      local r = row_of(mem, w, i, lay, n.parent, want)
      if r then
        buf.walk = string.format('%d roots, %d widgets, %.2f ms', roots, seen, (os.clock() - t0) * 1000)
        return w
      end
    end
    local links = mem.bytes(w + link, 16)
    if links then
      local sibling, child = ptr_in(links, 8), ptr_in(links, 0)
      if sibling then stack[#stack + 1] = sibling end
      if child then stack[#stack + 1] = child end
    end
  end
  buf.walk = string.format('%d roots, %d widgets, %.2f ms', roots, seen, (os.clock() - t0) * 1000)
  return nil, seen >= WALK_LIMIT and 'HUD+ list not found (search limit)' or 'HUD+ list not found'
end

local function view(buf, v, n)
  local S = rawget(_G, 'ChefSeafArtilleryLoadout')
  local H = S and rawget(S, 'hudplus')
  local mem = type(H) == 'table' and H.mem
  if type(mem) ~= 'table' or type(mem.bytes) ~= 'function' or type(mem.ptr) ~= 'function' or type(mem.u32) ~= 'function' then
    tell(buf, 'waiting for SEAF Artillery Loadout'); return nil
  end
  if not H.on then tell(buf, 'off (options menu)'); return nil end
  local kinds = H.kinds
  if #kinds == 0 then tell(buf, 'no shells loaded'); return nil end
  local lay = H.layout
  if type(v.slot) ~= 'number' or type(lay) ~= 'table' then tell(buf, 'waiting for the game list'); return nil end
  -- the list found before is checked every frame (2 reads); while it doesn't show the row, the list is searched for
  -- (4 times at most each opening, 3 frames apart: HUD+'s rows fill in on its first tick, a frame after the list
  -- opens; with HUD+'s panel off there is nothing to find). (Test 1 waited half a second between searches; Tests 2-5
  -- checked the known list for 20 frames first, but HUD+ rebuilds its panel elsewhere each opening.)
  if buf.opening ~= H.opening then buf.opening, buf.tries, buf.next_try = H.opening, 0, 0 end
  buf.frame = (buf.frame or 0) + 1
  local x, r, k = buf.list, nil, nil
  local want = H.row_id or SEAF              -- (spoof builds: the row the addon picked instead)
  if x then r, k = row_of(mem, x, H.index, lay, n.parent, want) end
  if not r then
    if buf.tries >= 4 or buf.frame < buf.next_try then return nil end
    buf.tries, buf.next_try = buf.tries + 1, buf.frame + 3
    local found, why = find_list(mem, buf, v.slot, n, lay, H.index, want)
    if not found then
      if buf.tries >= 4 then tell(buf, why, buf.walk) end
      return nil
    end
    r, k = row_of(mem, found, H.index, lay, n.parent, want)
    if not r then return nil end
    -- ((1.1.0 review) the first find is logged; later ones (HUD+ rebuilt its panel elsewhere) only counted, for the
    -- log's HD2 HUD+ line)
    if not buf.list then tell(buf, 'found HUD+ list', buf.walk .. string.format('; try %d', buf.tries))
    elseif found ~= buf.list then H.moves = (H.moves or 0) + 1 end
    buf.list = found
  end
  local out = buf.out
  if not out then out = {}; buf.out = out end
  out.row = r
  local tex = H.textures
  for j = 1, MAX do
    local kind = kinds[j]
    out[j] = kind and tex[kind] or nil
  end
  out.bar = H.bar
  out.material = material_of(buf, H.opening)
  if buf.state ~= 'showing' then
    tell(buf, 'showing', string.format('row %d; %s', k, out.material == COLOR_MATERIAL and 'in color' or 'HUD+ glyphs'))
  end
  return out
end

local computer = {
  gather = function() return {} end,           -- (HUD+ requires both; only run is used)
  -- (1.1.1) HUD+'s own reader (the first argument) isn't used: see the top
  run = function(_, _, _, buf, v, n)
    if v.listing ~= true then return nil end
    local ok, out = pcall(view, buf, v, n)
    if not ok then tell(buf, 'error', tostring(out)); return nil end
    return out
  end,
}

local sources = {
  ['chef_seaf.view'] = {
    form = 'chef_seaf_loadout', module = 'game', requires = { 'stratagem.listing', 'world.slot' },
    chef_seaf_loadout = {
      calls = {}, optional = {},
      entry = { parent = 'widget_parent', context = 'widget_gui_context', stride = 'gui_context_stride' },
      values = { listing = 'stratagem.listing', slot = 'world.slot' },
    },
  },
  ['chef_seaf.row'] = { from = 'chef_seaf.view', part = 'row' },
  ['chef_seaf.bar'] = { from = 'chef_seaf.view', part = 'bar' },
  ['chef_seaf.material'] = { from = 'chef_seaf.view', part = 'material' },
}
for j = 1, MAX do sources['chef_seaf.icon' .. j] = { from = 'chef_seaf.view', part = j } end

-- the screen: a frame just right of HUD+'s SEAF Artillery row (row units: the row is 68 high), the icons overlapping
-- like a row of shells, the next one first and on a yellow bar
local ICON, STEP, GAP = 58, 27, 12
local rows = {
  { id = 'seaf', kind = 'frame', source = 'chef_seaf.row', anchor = { 1, 0.5 }, pivot = { 0, 0.5 },
    position = { GAP, 0 }, size = { ICON + STEP * (MAX - 1), ICON } },
  { id = 'bar', kind = 'image', parent = 'seaf', source = 'chef_seaf.bar', material_source = 'chef_seaf.material',
    layer = 'stratagem_row_card_layer', anchor = { 0, 0 }, pivot = { 0, 0.5 },
    position = { ICON * 0.18, 0 }, size = { ICON * 0.64, 3 } },
}
for j = MAX, 1, -1 do        -- the next shell last, so it's drawn over the others
  rows[#rows + 1] = { id = 'icon' .. j, kind = 'image', parent = 'seaf', source = 'chef_seaf.icon' .. j,
    material_source = 'chef_seaf.material', layer = 'stratagem_row_card_layer', anchor = { 0, 0.5 },
    pivot = { 0, 0.5 }, position = { (j - 1) * STEP, 0 }, size = { ICON, ICON }, opacity = j == 1 and 1 or 0.82 }
end

-- (1.1.1) HUD+'s pin, taken from the HUD+ build that loads this part (see the top). What this part uses of HUD+:
local NEEDS = {
  sources = { 'stratagem.listing', 'stratagem.showing', 'world.slot' },
  numbers = { 'widget_parent', 'widget_gui_context', 'gui_context_stride', 'stratagem_row_card_layer' },
}
-- the HUD+ build it was tested on (HD2 HUD+ 0.2.2 and 0.2.4 (DDRK1NG) share it): its exe and game.dll SHA-256
local TESTED = { exe = 'f5fee03dcfdb2e553a4752c283590950ac13316b376d8196aa556ff0400d5f06',
                 game = '2e2c3b7c2500646dadd5f2b4c6e0504dbb7e7896139f64cddc0d1813c718f51e' }

-- HUD+'s build table (its game data, sources and screens) while it merges this part: a table in the calling frames
-- with a pin of two strings, sources, numbers and screens (found by its shape, not its name)
local function host(getlocal)
  for level = 2, 24 do
    for i = 1, 64 do
      local name, value = getlocal(level, i)
      if name == nil then break end
      if type(value) == 'table' and type(rawget(value, 'sources')) == 'table' and type(rawget(value, 'numbers')) == 'table'
          and type(rawget(value, 'screens')) == 'table' then
        local pin = rawget(value, 'pin')
        if type(pin) == 'table' and type(rawget(pin, 'exe')) == 'string' and type(rawget(pin, 'game')) == 'string' then
          return value
        end
      end
    end
  end
end

-- what this HUD+ build lacks of what the part uses (an empty list: everything is there)
local function lacking(b)
  local out = {}
  for _, name in ipairs(NEEDS.sources) do if b.sources[name] == nil then out[#out + 1] = 'source ' .. name end end
  for _, name in ipairs(NEEDS.numbers) do if b.numbers[name] == nil then out[#out + 1] = 'number ' .. name end end
  -- the features the screen uses, as HUD+'s own screens use them: a screen on a source's widget that goes when another
  -- source does (parent, transient), frame and image rows, computed sources and their parts
  local stage, kinds = false, {}
  for _, screen in ipairs(b.screens) do
    if type(screen) == 'table' then
      if screen.parent ~= nil and screen.transient ~= nil then stage = true end
      if type(screen.rows) == 'table' then
        for _, row in ipairs(screen.rows) do if type(row) == 'table' and row.kind ~= nil then kinds[row.kind] = true end end
      end
    end
  end
  if not stage then out[#out + 1] = 'screens on a row of its own panel' end
  for _, kind in ipairs({ 'frame', 'image' }) do if not kinds[kind] then out[#out + 1] = kind .. ' rows' end end
  local computed, parts = false, false
  for _, src in pairs(b.sources) do
    if type(src) == 'table' then
      local spec = type(src.form) == 'string' and src[src.form]
      if type(spec) == 'table' and type(spec.values) == 'table' and type(spec.entry) == 'table' then computed = true end
      if src.from ~= nil and src.part ~= nil then parts = true end
    end
  end
  if not computed then out[#out + 1] = 'computed sources' end
  if not parts then out[#out + 1] = 'source parts' end
  return out
end

-- how HUD+ took this part, for the SEAF Artillery Loadout addon's log
local taken = { how = nil }
rawset(_G, 'ChefSeafArtilleryLoadoutHudPlus', taken)
local chosen
local function pin_of(key)
  if chosen == nil then
    chosen = TESTED
    local dbg = rawget(_G, 'debug')
    local getlocal = type(dbg) == 'table' and rawget(dbg, 'getlocal') or nil
    if type(getlocal) ~= 'function' then
      taken.how = 'no debug library: only the HUD+ build it was tested on'
    else
      local ok, b = pcall(host, getlocal)
      if not ok or b == nil then
        taken.how = 'HUD+ build not seen: only the HUD+ build it was tested on'
      else
        local miss = lacking(b)
        if #miss > 0 then
          chosen = false
          taken.how = 'refused: this HD2 HUD+ build lacks ' .. table.concat(miss, ', ')
        else
          chosen = { exe = b.pin.exe, game = b.pin.game }
          taken.how = (chosen.exe == TESTED.exe and chosen.game == TESTED.game) and 'the HUD+ build it was tested on'
            or 'a newer HUD+ build: it has everything this uses'
        end
      end
    end
  end
  return chosen and chosen[key] or nil
end
local PIN = setmetatable({}, { __index = function(_, key) if key == 'exe' or key == 'game' then return pin_of(key) end end })

return {
  pin = PIN,
  -- no options of its own (the SEAF Artillery Loadout toggles cover it): HUD+'s own menu text as title and strings
  title = 1207430374, strings = '94a17a3a1257fc23',
  version = VERSION,
  compute = { chef_seaf_loadout = computer },
  sources = sources,
  screens = { { id = 'chef.seaf_artillery_loadout', parent = 'chef_seaf.row', transient = 'stratagem.showing',
                rows = rows } },
}
