"""SEAF Artillery Loadout - build.

python build.py <out dir>              the release (SEAF-Artillery-Loadout-<ver>.zip)
python build.py <out dir> --tester     the release's Tester build (research details in the normal log, test GUID)
python build.py <out dir> --test N     numbered test build N (log in Logs\\test, test GUID)
  <out dir> is emptied first, but only when build.py made it (its marker file), never the source folder or one above it
  - 9ba626afa44a3aa3.patch_0: the addon (plain Lua, Bingus Shared Loader finds it by its first line)
  - manifest.json, icon.png; zip
"""
import json, os, shutil, struct, sys, zipfile
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_writer

VERSION = '1.1.0'
GUID_RELEASE = 'b6c4578a-d422-4328-b1a4-517cfc8df35e'
GUID_TEST = '88435314-fc5c-4a96-865d-1e233b675e5c'      # Tester and numbered test builds
LUA, TEXTURE = 0xa14e8dfa2cd117e2, 0xcd4238c6a0c69e32
ADDON = 'mods/chef/seaf_artillery_loadout'
HUDPLUS_PART = 'mods/chef/seaf_artillery_loadout_hudplus'   # (1.1.0) the HD2 HUD+ add-on
ANTON = os.path.join(HERE, 'fonts', 'anton-latin-400-normal.ttf')


def resource_hash(name):
    """The game's 64-bit resource name hash (MurmurHash64A, seed 0)."""
    data = name.encode(); mask, mix = (1 << 64) - 1, 0xC6A4A7935BD1E995
    v = len(data) * mix & mask; end = len(data) // 8 * 8
    for (w,) in struct.iter_unpack('<Q', data[:end]):
        w = w * mix & mask; w ^= w >> 47; v = (v ^ (w * mix & mask)) * mix & mask
    if data[end:]: v = (v ^ int.from_bytes(data[end:], 'little')) * mix & mask
    v ^= v >> 47; v = v * mix & mask; v ^= v >> 47
    return v


assert resource_hash('lua') == LUA and resource_hash('texture') == TEXTURE


def lua_resource(text):
    b = text.encode('utf-8')
    return struct.pack('<II', len(b), 2) + b


SIZE = 64          # icon texture side
# shell types: (id, tip color, band color or None) -- the tip colors follow the game's shells (Explosive olive,
# High-Yield orange, Mini Nuke black with a yellow band), brightened a little to read on the HUD
SHELLS = [
    ('explosive', (150, 162, 72), None),
    ('high_yield', (252, 180, 24), None),      # (1.1.0) amber yellow like the game's shell (was orange 244,132,40)
    ('mini_nuke', (34, 34, 34), (255, 214, 40)),
    ('napalm', (226, 64, 40), None),
    ('smoke', (196, 196, 196), None),
    ('static_field', (84, 172, 255), None),
    ('unknown', (120, 120, 120), None),
]


def texture_resource(size):
    """340-byte texture header: 192 bytes (0, 0, ffffffff, zeros) + DDS header + DX10 (RGBA8, one mip)."""
    head = bytearray(192); head[8:12] = b'\xff\xff\xff\xff'
    dds = b'DDS ' + struct.pack('<7I', 124, 0x100F, size, size, size * 4, 0, 1) + b'\0' * 44
    dds += struct.pack('<2I4s5I', 32, 4, b'DX10', 0, 0, 0, 0, 0)
    dds += struct.pack('<5I', 0x1000, 0, 0, 0, 0)
    dds += struct.pack('<5I', 28, 3, 0, 1, 0)
    out = bytes(head) + dds
    assert len(out) == 340, len(out)
    return out


def shell_icon(tip, band, unknown=False, size=SIZE):
    """An upright artillery shell (brass case, dark steel body, colored tip) with a dark outline, centered in a
    size x size texture, drawn at 4x and scaled down (the game's 64 px textures; the release art uses bigger ones)."""
    k = max(1, size // SIZE)                  # 1 for the game's textures: the same drawing at any size
    big = SIZE * 4 * k
    m = Image.new('L', (big, big), 0)
    parts = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    d, dm = ImageDraw.Draw(parts), ImageDraw.Draw(m)
    cx, w = big // 2, 76 * k
    l, r = cx - w // 2, cx + w // 2
    case_top, body_top, tip_top, bottom = 150 * k, 92 * k, 14 * k, 240 * k
    shapes = [
        ('rect', (l - 6 * k, bottom - 14 * k, r + 6 * k, bottom), (150, 124, 62)),  # rim
        ('rect', (l, case_top, r, bottom - 14 * k), (198, 166, 92)),                # brass case
        ('rect', (l, body_top, r, case_top), (86, 94, 78)),                         # steel body
        ('rect', (l, case_top - 10 * k, r, case_top), (64, 70, 58)),                # driving band
    ]
    for kind, box, col in shapes:
        d.rectangle(box, fill=col + (255,)); dm.rectangle(box, fill=255)
    ogive = [(l, body_top)] + [(cx - (w / 2) * (1 - (t / 20) ** 1.6), body_top - (body_top - tip_top) * t / 20) for t in range(21)] \
        + [(cx + (w / 2) * (1 - (t / 20) ** 1.6), body_top - (body_top - tip_top) * t / 20) for t in range(20, -1, -1)] + [(r, body_top)]
    d.polygon(ogive, fill=tip + (255,)); dm.polygon(ogive, fill=255)
    if band:
        d.rectangle((l, body_top - 18 * k, r, body_top), fill=band + (255,))
    # a soft highlight down the left side
    hl = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(hl).rectangle((l + 10 * k, tip_top + 30 * k, l + 22 * k, bottom - 18 * k), fill=(255, 255, 255, 60))
    hl.putalpha(Image.composite(hl.getchannel('A'), Image.new('L', (big, big), 0), m))
    parts = Image.alpha_composite(parts, hl.filter(ImageFilter.GaussianBlur(3 * k)))
    if unknown:
        font = ImageFont.truetype(ANTON, 90 * k)
        tw = ImageDraw.Draw(parts).textlength('?', font=font)
        ImageDraw.Draw(parts).text((cx - tw / 2, 120 * k), '?', font=font, fill=(255, 255, 255, 255), stroke_width=5 * k, stroke_fill=(0, 0, 0, 255))
    outline = m.filter(ImageFilter.MaxFilter(12 * k + 1)).filter(ImageFilter.GaussianBlur(1.5 * k))
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    dark = Image.new('RGBA', (big, big), (8, 8, 8, 255)); dark.putalpha(outline.point(lambda p: round(p * 0.92)))
    img = Image.alpha_composite(img, dark)
    img = Image.alpha_composite(img, parts)
    return img.resize((size, size), Image.LANCZOS)


# ((1.0.1 review) the output folder is emptied before each build, so only a folder this script made is emptied: one
# carrying its marker file, or (folders from 1.0.0 builds) one holding nothing but this script's output. Never this
# folder or one above it: "build.py ." used to delete the source.)
MARKER = '.seaf-artillery-loadout-build'


def is_output(name):
    return name in (MARKER, 'pkg', 'addon.built.lua', 'hudplus.built.lua', 'icons_preview.png') \
        or (name.startswith('SEAF-Artillery-Loadout-') and name.endswith('.zip'))


def clean_out(out):
    real, here = os.path.realpath(out), os.path.realpath(HERE)
    if real == here or here.startswith(real.rstrip(os.sep) + os.sep):
        sys.exit('build.py: refusing to use %s as the output folder: it holds the source. Give a new folder, e.g. "out".' % out)
    if not os.path.lexists(out):
        return
    if not os.path.isdir(out) or os.path.islink(out):
        sys.exit('build.py: %s is not a folder; give a new folder for the output.' % out)
    names = os.listdir(out)
    if MARKER not in names and not all(is_output(n) for n in names):
        sys.exit('build.py: refusing to empty %s: it is not a build output folder (no %s, and it holds other files). '
                 'Give a new or empty folder.' % (out, MARKER))
    shutil.rmtree(out)


def main():
    out, args = sys.argv[1], sys.argv[2:]
    tester = '--tester' in args
    test = int(args[args.index('--test') + 1]) if '--test' in args else None
    spoof = '--spoof' in args                 # a numbered test build with made-up shells (no SEAF Artillery needed)
    assert not spoof or test, '--spoof needs --test N'
    full = VERSION + (' Test %d' % test if test else ' (tester)' if tester else '') + (' Spoof' if spoof else '')
    guid = GUID_TEST if (test or tester) else GUID_RELEASE
    clean_out(out)
    pkg = os.path.join(out, 'pkg'); os.makedirs(pkg)
    open(os.path.join(out, MARKER), 'w').write('SEAF Artillery Loadout build output (build.py empties this folder on the next build)\n')
    src = open(os.path.join(HERE, 'lua', 'seaf_artillery_loadout.lua'), encoding='utf-8').read()
    for a, b in ((src[src.index("local VERSION = '"):src.index("'", src.index("local VERSION = '") + 17) + 1], "local VERSION = '%s'" % full),
                 ('local TEST_BUILD = false', 'local TEST_BUILD = %s' % ('true' if test else 'false')),
                 ('local TESTER = false', 'local TESTER = %s' % ('true' if (tester or test) else 'false')),
                 ('local SPOOF = false', 'local SPOOF = %s' % ('true' if spoof else 'false'))):
        assert src.count(a) == 1, a
        src = src.replace(a, b)
    icons_lua, textures = [], []
    sheet = Image.new('RGBA', (SIZE * 2 * len(SHELLS), SIZE * 2), (40, 40, 40, 255))
    for i, (kid, tip, band) in enumerate(SHELLS):
        img = shell_icon(tip, band, kid == 'unknown')
        tex_id = resource_hash('mods/chef/seaf_artillery_loadout/shell_' + kid)
        textures.append((tex_id, TEXTURE, texture_resource(SIZE), img.tobytes(), b'', 64))
        icons_lua.append("KIND.%s.texture, KIND.%s.rgb = '%016x', { %d, %d, %d }" % (kid, kid, tex_id, *tip))
        sheet.alpha_composite(img.resize((SIZE * 2, SIZE * 2), Image.LANCZOS), (i * SIZE * 2, 0))
    sheet.save(os.path.join(out, 'icons_preview.png'))
    # (1.1.0) the next shell's bar on HD2 HUD+'s panel: a small solid yellow texture (the game's HUD yellow)
    bar_id = resource_hash('mods/chef/seaf_artillery_loadout/next_bar')
    bar = Image.new('RGBA', (8, 8), (255, 231, 16, 255))
    textures.append((bar_id, TEXTURE, texture_resource(8), bar.tobytes(), b'', 64))
    icons_lua.append("BAR_TEXTURE = '%016x'" % bar_id)
    assert src.count('--@@ICONS@@') == 1
    src = src.replace('--@@ICONS@@', '\n'.join(icons_lua))
    for bad in ('/home/', '/mnt/', 'D:\\', 'C:\\', 'Users\\'):
        assert bad not in src, 'not sanitized: ' + bad
    open(os.path.join(out, 'addon.built.lua'), 'w', encoding='utf-8').write(src)
    # (1.1.0) the HD2 HUD+ add-on: its own Lua resource, found by HUD+ through its first line (Bingus skips it)
    part = open(os.path.join(HERE, 'lua', 'seaf_artillery_loadout_hudplus.lua'), encoding='utf-8').read()
    a = "local VERSION = '%s'" % VERSION
    assert part.count(a) == 1 and part.startswith('local HD2_HUD_ADDON = "%s"\n' % HUDPLUS_PART), 'HUD+ add-on header'
    part = part.replace(a, "local VERSION = '%s'" % full)
    for bad in ('/home/', '/mnt/', 'D:\\', 'C:\\', 'Users\\'):
        assert bad not in part, 'not sanitized: ' + bad
    open(os.path.join(out, 'hudplus.built.lua'), 'w', encoding='utf-8').write(part)
    toc, gpu, stream = patch_writer.write([(resource_hash(ADDON), LUA, lua_resource(src), b'', b'', 64),
                                           (resource_hash(HUDPLUS_PART), LUA, lua_resource(part), b'', b'', 64)] + textures,
                                          [(LUA, 64), (TEXTURE, 64)])
    patch_writer.check(toc, gpu, stream)
    base = os.path.join(pkg, '9ba626afa44a3aa3.patch_0')
    open(base, 'wb').write(toc); open(base + '.gpu_resources', 'wb').write(gpu); open(base + '.stream', 'wb').write(stream)
    art_icon = os.path.join(HERE, 'artwork', 'icon.png')
    if test:
        img = Image.open(art_icon).convert('RGB')
        d = ImageDraw.Draw(img)
        f2 = ImageFont.truetype(ANTON, 64)
        label = 'TEST %d' % test
        tw = d.textlength(label, font=f2)
        d.text(((512 - tw) / 2, 410), label, font=f2, fill=(255, 80, 60), stroke_width=4, stroke_fill=(0, 0, 0))
        img.save(os.path.join(pkg, 'icon.png'), optimize=True)
    else:
        shutil.copyfile(art_icon, os.path.join(pkg, 'icon.png'))
    desc = ('Shows what the SEAF artillery has loaded: once the SEAF Artillery objective is done, the shells still loaded '
            'appear as icons in firing order next to the SEAF Artillery stratagem while the stratagem list is open, the '
            'next one marked, on the game\'s list or on HD2 HUD+\'s stratagem panel; also has the game redo its SEAF Artillery '
            'shell name when the next shell changes (the game\'s own name can lag after a shot). Requires Bingus Shared Loader '
            'v19 or newer.')
    man = {'Version': 1, 'Guid': guid, 'Name': 'SEAF Artillery Loadout ' + full, 'Description': desc, 'IconPath': 'icon.png'}
    open(os.path.join(pkg, 'manifest.json'), 'w').write(json.dumps(man, indent=2))
    z = os.path.join(out, 'SEAF-Artillery-Loadout-%s.zip' % (VERSION + ('-Test-%d' % test if test else '-Tester' if tester else '')
                                                             + ('-Spoof' if spoof else '')))
    with zipfile.ZipFile(z, 'w', zipfile.ZIP_DEFLATED) as zf:       # fixed dates: the same source gives the same zip
        for f in sorted(os.listdir(pkg)):
            info = zipfile.ZipInfo(f, date_time=(2026, 10, 10, 0, 0, 0))
            info.compress_type, info.external_attr = zipfile.ZIP_DEFLATED, 0o644 << 16
            zf.writestr(info, open(os.path.join(pkg, f), 'rb').read())
    print(z, os.path.getsize(z))


if __name__ == '__main__':
    main()
