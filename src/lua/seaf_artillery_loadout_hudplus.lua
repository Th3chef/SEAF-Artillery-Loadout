local HD2_HUD_ADDON = "mods/chef/seaf_artillery_loadout_hudplus"
-- SEAF Artillery Loadout: the HD2 HUD+ add-on. HD2 HUD+ finds this resource by its first line and merges the part it
-- returns: one screen that puts the loaded shells next to the SEAF Artillery row of HUD+'s own stratagem panel.
-- The shells themselves come from the SEAF Artillery Loadout addon (Bingus Shared Loader), which already reads them
-- (patch-proof); this part only finds HUD+'s row and draws. Without that addon, or with nothing loaded, it shows nothing.
-- HUD+ only takes a part made for its exact build (pin), so a new HUD+ version skips this until it is rebuilt.
local VERSION = '1.1.0'

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

-- HUD+'s memory reader: span(address, size) -> bytes, read.bytes.u32(bytes, offset), pointer_in(bytes, offset)
local function u32(read, bytes, at) return read.bytes.u32(bytes, at) end
local function u64(read, bytes, at)
  local lo, hi = read.bytes.u32(bytes, at), read.bytes.u32(bytes, at + 4)
  if lo == nil or hi == nil then return nil end
  return hi * 4294967296 + lo
end

-- the SEAF row of the stratagem list whose rows hang under widget x: i first (the game list's own row), then all 16
local function row_of(read, x, i, lay, parent_at, want)
  local function at(k)
    local r = x + lay.rowbase + k * lay.stride
    local p = read:span(r + parent_at, 8)
    if p == nil or read:pointer_in(p, 0) ~= x then return nil end
    local id = read:span(r + lay.id, 4)
    if id == nil or u32(read, id, 0) ~= want then return nil end
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
local function find_list(read, buf, ctx, n, lay, i, want)
  local t0 = os.clock()
  local set = ctx + n.stride - 0x18
  local head = read:span(set, 0x14)
  if head == nil then return nil, 'the world context could not be read' end
  local off, cap, empty, flags = u64(read, head, 0), u32(read, head, 8), u32(read, head, 12), u32(read, head, 16)
  if not off or not cap or cap == 0 or cap > 1024 then return nil, 'the world context has no roots' end
  local data = (floor(flags / 4) % 2 == 1) and (set - off) or off
  local keys = read:span(data, cap * 8)
  if keys == nil then return nil, 'the world context roots could not be read' end
  local stack, seen = {}, 0
  for k = 0, cap - 1 do
    local w = u64(read, keys, k * 8)
    if w and w ~= empty and w > 0x10000 then
      local c = read:span(w + n.context, 8)
      if c and read:pointer_in(c, 0) == ctx then stack[#stack + 1] = w end
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
    local first = read:span(w + lay.rowbase + n.parent, 8)
    if first and read:pointer_in(first, 0) == w then
      local r = row_of(read, w, i, lay, n.parent, want)
      if r then
        buf.walk = string.format('%d roots, %d widgets, %.2f ms', roots, seen, (os.clock() - t0) * 1000)
        return w
      end
    end
    local links = read:span(w + link, 16)
    if links then
      local sibling, child = read:pointer_in(links, 8), read:pointer_in(links, 0)
      if sibling then stack[#stack + 1] = sibling end
      if child then stack[#stack + 1] = child end
    end
  end
  buf.walk = string.format('%d roots, %d widgets, %.2f ms', roots, seen, (os.clock() - t0) * 1000)
  return nil, seen >= WALK_LIMIT and 'HUD+ list not found (search limit)' or 'HUD+ list not found'
end

local function view(read, buf, v, n)
  local S = rawget(_G, 'ChefSeafArtilleryLoadout')
  local H = S and rawget(S, 'hudplus')
  if type(H) ~= 'table' then tell(buf, 'waiting for SEAF Artillery Loadout'); return nil end
  if not H.on then tell(buf, 'off (options menu)'); return nil end
  local kinds = H.kinds
  if #kinds == 0 then tell(buf, 'no shells loaded'); return nil end
  local lay = H.layout
  if type(v.slot) ~= 'number' or type(lay) ~= 'table' then tell(buf, 'waiting for the game list'); return nil end
  -- the list found before is checked every frame (3 reads); while it doesn't show the row, the list is searched for
  -- (4 times at most each opening, 3 frames apart: HUD+'s rows fill in on its first tick, a frame after the list
  -- opens; with HUD+'s panel off there is nothing to find). (Test 1 waited half a second between searches; Tests 2-5
  -- checked the known list for 20 frames first, but HUD+ rebuilds its panel elsewhere each opening.)
  if buf.opening ~= H.opening then buf.opening, buf.tries, buf.next_try = H.opening, 0, 0 end
  buf.frame = (buf.frame or 0) + 1
  local x, r, k = buf.list, nil, nil
  local want = H.row_id or SEAF              -- (spoof builds: the row the addon picked instead)
  if x then r, k = row_of(read, x, H.index, lay, n.parent, want) end
  if not r then
    if buf.tries >= 4 or buf.frame < buf.next_try then return nil end
    buf.tries, buf.next_try = buf.tries + 1, buf.frame + 3
    local found, why = find_list(read, buf, v.slot, n, lay, H.index, want)
    if not found then
      if buf.tries >= 4 then tell(buf, why, buf.walk) end
      return nil
    end
    r, k = row_of(read, found, H.index, lay, n.parent, want)
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
  run = function(read, judge, tokens, buf, v, n)
    if v.listing ~= true then return nil end
    local ok, out = pcall(view, read, buf, v, n)
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

return {
  -- HD2 HUD+ 0.2.2 (DDRK1NG): the exe and game.dll SHA-256 its build is pinned to
  pin = { exe = 'f5fee03dcfdb2e553a4752c283590950ac13316b376d8196aa556ff0400d5f06',
          game = '2e2c3b7c2500646dadd5f2b4c6e0504dbb7e7896139f64cddc0d1813c718f51e' },
  -- no options of its own (the SEAF Artillery Loadout toggles cover it): HUD+'s own menu text as title and strings
  title = 1207430374, strings = '94a17a3a1257fc23',
  version = VERSION,
  compute = { chef_seaf_loadout = computer },
  sources = sources,
  screens = { { id = 'chef.seaf_artillery_loadout', parent = 'chef_seaf.row', transient = 'stratagem.showing',
                rows = rows } },
}
