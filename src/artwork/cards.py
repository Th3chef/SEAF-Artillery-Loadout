"""SEAF Artillery Loadout release art: thumbnail (1254x1254), the Arsenal icon (512x512, the thumbnail scaled down),
gallery photo (1920x1080), header (1300x372), the GitHub social preview (1280x640) and the AyakaMods cover (1600x1000:
the site's mod cards crop the cover to a 200 px high box from about 1.2:1 to 2:1 wide, so the title and the row sit in
the middle 1190x800).

The centerpiece is the stratagem list's SEAF Artillery row as the mod shows it in game: the row with the next shell's
name, and the loaded shells to its right in firing order, the next one on a yellow bar, drawn with the mod's own shell
icons (build.py's shell_icon) at the mod's own proportions. The scene behind comes from hero.py (a flat illustration);
the title, version badge and text are HTML rendered with Playwright Chromium (Anton + Barlow Condensed in fonts/, SIL
Open Font License, from @fontsource).
python cards.py <out dir> [version badge, e.g. 1.0]"""
import base64, io, os, sys
from PIL import Image
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import hero
import build

FONTS = {'Anton': 'fonts/anton-latin-400-normal.woff2',
         'Barlow Condensed': 'fonts/barlow-condensed-latin-600-normal.woff2',
         'Barlow Condensed B': 'fonts/barlow-condensed-latin-800-normal.woff2'}

TAGLINE = 'Know what the guns have loaded'
FEATURES = ['EVERY SHELL TYPE', 'FIRING ORDER', 'NEXT SHELL MARKED', 'HD2 HUD+ READY']   # (1.1: + the HD2 HUD+ add-on)
# the loaded shells shown, next first (the game names the next one in the row: "SEAF ARTILLERY: EXPLOSIVE")
LOADED = ['explosive', 'high_yield', 'napalm', 'static_field', 'mini_nuke']      # the artillery holds 5 shells
ICON_H, STEP, GAP = 0.86, 0.46, 0.18      # the mod's own layout (lua: icon height and spacing, gap after the list)


def b64(path_or_img):
    if isinstance(path_or_img, str):
        return base64.b64encode(open(os.path.join(HERE, path_or_img), 'rb').read()).decode()
    buf = io.BytesIO(); path_or_img.save(buf, 'PNG'); return base64.b64encode(buf.getvalue()).decode()


def font_css():
    out = []
    for name, f in FONTS.items():
        out.append("@font-face{font-family:'%s';src:url(data:font/woff2;base64,%s) format('woff2');}" % (name, b64(f)))
    return '\n'.join(out)


SHELL_PNG = {}


def shell_png(kid):
    if kid not in SHELL_PNG:
        tip, band = {k: (t, b) for k, t, b in build.SHELLS}[kid]
        SHELL_PNG[kid] = b64(build.shell_icon(tip, band, kid == 'unknown', size=256))
    return SHELL_PNG[kid]


# the stratagem's own icon: an original glyph (a shell coming down onto a burst) in a framed square
GLYPH = """<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <rect x="3" y="3" width="94" height="94" fill="#1d1f1c" stroke="#e9c62a" stroke-width="5"/>
  <g fill="#f2f0e6">
    <path d="M50 14 L58 26 L58 52 L42 52 L42 26 Z"/>
    <rect x="40" y="54" width="20" height="6"/>
    <path d="M50 66 L56 74 L66 70 L62 79 L72 84 L60 86 L50 92 L40 86 L28 84 L38 79 L34 70 L44 74 Z"/>
  </g></svg>"""


def arrow(d):
    rot = {'up': 0, 'right': 90, 'down': 180, 'left': 270}[d]
    return ('<svg class="arr" viewBox="0 0 20 20" style="transform:rotate(%ddeg)"><path d="M10 2 L18 11 L13 11 L13 18 '
            'L7 18 L7 11 L2 11 Z" fill="#e8e6dc"/></svg>' % rot)


def hud_row(h, name='SEAF ARTILLERY: EXPLOSIVE', shells=LOADED, ghost=True):
    """The SEAF Artillery row at row height h px, with the shell icons to its right (as in game). Returns html, width."""
    text_w = 3.9 * h
    row_w = h * 1.08 + text_w
    size = h * ICON_H
    icons = []
    x0 = row_w + h * GAP
    for i, kid in enumerate(shells):
        icons.append('<img src="data:image/png;base64,%s" style="position:absolute;left:%.1fpx;top:%.1fpx;width:%.1fpx;'
                     'height:%.1fpx;opacity:%s">' % (shell_png(kid), x0 + i * size * STEP, (h - size) / 2, size, size,
                                                    '1' if i == 0 else '0.82'))
    bar = ('<div style="position:absolute;left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;background:#ffe710;'
           'box-shadow:0 0 %.0fpx rgba(255,231,16,.6)"></div>' % (x0 + size * 0.18, (h - size) / 2 + size * 0.97,
                                                                  size * 0.64, size * 0.05, size * 0.08))
    width = x0 + (len(shells) - 1) * size * STEP + size
    ghost_rows = ''
    if ghost:      # the neighbors in the list, dimmed
        for dy in (-1.12, 1.12):
            ghost_rows += ('<div style="position:absolute;left:0;top:%.1fpx;width:%.1fpx;height:%.1fpx;background:'
                           'linear-gradient(90deg,rgba(14,16,18,.62),rgba(14,16,18,.28));opacity:.55"><div style="position:'
                           'absolute;left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;border:%.1fpx solid rgba(220,220,210,.45)">'
                           '</div><div style="position:absolute;left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;'
                           'background:rgba(220,220,210,.28)"></div></div>'
                           % (dy * h, row_w, h, h * 0.1, h * 0.1, h * 0.8, h * 0.8, h * 0.03, h * 1.08, h * 0.24,
                              text_w * 0.55, h * 0.16))
    row = ('<div style="position:absolute;left:0;top:0;width:%.1fpx;height:%.1fpx;background:linear-gradient(90deg,'
           'rgba(14,16,18,.88),rgba(14,16,18,.55));border-left:%.1fpx solid #ffe710">'
           '<div style="position:absolute;left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx">%s</div>'
           '<div class="sname" style="position:absolute;left:%.1fpx;top:%.1fpx;font-size:%.1fpx">%s</div>'
           '<div style="position:absolute;left:%.1fpx;top:%.1fpx;display:flex;gap:%.1fpx;height:%.1fpx">%s</div></div>'
           % (row_w, h, h * 0.035, h * 0.1, h * 0.1, h * 0.8, h * 0.8, GLYPH, h * 1.08, h * 0.1, h * 0.3, name,
              h * 1.08, h * 0.56, h * 0.06, h * 0.26, ''.join(arrow(x) for x in ('right', 'up', 'up', 'down'))))
    html = ('<div style="position:relative;width:%.1fpx;height:%.1fpx">%s%s%s%s</div>'
            % (width, h, ghost_rows, row, bar, ''.join(icons)))
    return html, width


CSS = """
* { margin:0; padding:0; box-sizing:border-box; }
body { width:%(W)dpx; height:%(H)dpx; overflow:hidden; background:#000; position:relative; }
.bg { position:absolute; inset:0; background:url(data:image/png;base64,%(bg)s) no-repeat; background-size:100%% 100%%; }
.title { font-family:'Anton'; color:#ffe710; letter-spacing:0.02em; line-height:0.95; text-transform:uppercase;
  text-shadow: 0 0.04em 0 #000, 0 0 0.12em rgba(0,0,0,.9), 0 0 0.35em rgba(0,0,0,.6); }
.badge { display:inline-block; font-family:'Barlow Condensed B'; background:#ffe710; color:#111; padding:0.04em 0.32em 0.02em;
  border:0.06em solid #111; box-shadow:0 0.08em 0.25em rgba(0,0,0,.6); letter-spacing:0.03em; }
.feat { font-family:'Barlow Condensed B'; color:#111; display:flex; flex-wrap:wrap; gap:0.35em; }
.feat span { background:rgba(255,231,16,.95); padding:0.06em 0.4em 0.02em; border:0.05em solid #111; letter-spacing:0.04em;
  box-shadow:0 0.06em 0.2em rgba(0,0,0,.55); }
.band { display:inline-block; padding:0.3em 0.68em 0.26em; background:linear-gradient(rgba(8,10,14,.6),rgba(8,10,14,.48));
  border-top:0.08em solid #ffe710; border-bottom:0.08em solid #ffe710; box-shadow:0 6px 24px rgba(0,0,0,.55);
  font-family:'Barlow Condensed B'; letter-spacing:0.12em; text-transform:uppercase; color:#eadfc8; text-shadow:0 2px 3px #000;
  white-space:nowrap; }
.plate { position:absolute; background:linear-gradient(rgba(8,10,14,.84),rgba(8,10,14,.74)); border:3px solid #ffe710;
  box-shadow:0 8px 30px rgba(0,0,0,.6); }
.sname { font-family:'Barlow Condensed B'; color:#f2f0e6; letter-spacing:0.04em; white-space:nowrap; text-shadow:0 2px 3px #000; }
.arr { height:100%%; width:auto; filter:drop-shadow(0 1px 1px #000); }
.hud { position:absolute; filter:drop-shadow(0 10px 26px rgba(0,0,0,.7)); }
"""


def render(page, W, H, bg, body):
    html = '<html><head><style>%s\n%s</style></head><body><div class="bg"></div>%s</body></html>' % (
        font_css(), CSS % {'W': W, 'H': H, 'bg': b64(bg)}, body)
    page.set_viewport_size({'width': W, 'height': H})
    page.set_content(html)
    page.wait_for_timeout(300)
    return page.screenshot(type='png')


def feats(size):
    return '<div class="feat" style="font-size:%dpx">%s</div>' % (size, ''.join('<span>%s</span>' % f for f in FEATURES))


def placed(h, left, top, W=None, ghost=True):
    """the HUD row at row height h; left=None centers it in a W wide picture"""
    html, w = hud_row(h, ghost=ghost)
    if left is None: left = (W - w) / 2
    return '<div class="hud" style="left:%.0fpx;top:%.0fpx">%s</div>' % (left, top, html)


def main():
    out = sys.argv[1]
    ver = sys.argv[2] if len(sys.argv) > 2 else '1.0'
    os.makedirs(out, exist_ok=True)
    jobs = []
    # square thumbnail: the title at the top, the row in the middle, the gun behind, the tagline at the bottom
    W = H = 1254
    bg = hero.hero(W, H, 760, 1010, 420, seed=7)
    jobs.append(('thumbnail.png', W, H, bg, """
      <div style="position:absolute;left:0;right:0;top:66px;text-align:center">
        <div class="title" style="font-size:148px;white-space:nowrap">SEAF Artillery</div>
        <div style="display:flex;justify-content:center;align-items:flex-start;gap:26px;margin-top:6px">
          <div class="title" style="font-size:148px;white-space:nowrap">Loadout</div>
          <span class="badge" style="font-size:52px;margin-top:10px">v%(v)s</span></div>
      </div>
      %(row)s
      <div style="position:absolute;left:0;right:0;bottom:74px;text-align:center">
        <span class="band" style="font-size:50px">%(t)s</span>
      </div>""" % {'v': ver, 't': TAGLINE, 'row': placed(122, None, 560, W)}))
    # gallery photo 16:9: the title plate at the top left, the row across the middle, the gun on the right
    W, H = 1920, 1080
    bg = hero.hero(W, H, 1440, 900, 470, seed=11)
    jobs.append(('gallery_1920x1080.png', W, H, bg, """
      <div class="plate" style="left:70px;top:84px;width:1080px;padding:36px 40px 38px">
        <div style="display:flex;align-items:flex-start;gap:24px"><div class="title" style="font-size:104px;white-space:nowrap">SEAF Artillery Loadout</div></div>
        <div style="margin-top:22px;display:flex;align-items:center;gap:26px"><span class="badge" style="font-size:44px">v%(v)s</span>
          <span class="band" style="font-size:34px">%(t)s</span></div>
        <div style="margin-top:28px">%(f)s</div>
      </div>
      %(row)s""" % {'v': ver, 't': TAGLINE, 'f': feats(32), 'row': placed(128, 110, 620)}))
    # GitHub social preview 2:1 (40 px clear at the edges)
    W, H = 1280, 640
    bg = hero.hero(W, H, 980, 560, 300, seed=5)
    jobs.append(('GitHub-Social-1280x640.png', W, H, bg, """
      <div class="plate" style="left:48px;top:48px;padding:24px 30px 26px">
        <div class="title" style="font-size:72px;white-space:nowrap">SEAF Artillery Loadout</div>
        <div style="margin-top:16px;display:flex;align-items:center;gap:18px"><span class="badge" style="font-size:32px">v%(v)s</span>
          <span class="band" style="font-size:22px">%(t)s</span></div>
        <div style="margin-top:18px">%(f)s</div>
      </div>
      %(row)s""" % {'v': ver, 't': TAGLINE, 'f': feats(22), 'row': placed(84, 60, 410)}))
    # header 1300x372: the title on the left, the row under it, the gun on the right
    W, H = 1300, 372
    bg = hero.hero(W, H, 1140, 330, 190, seed=9)
    jobs.append(('header_1300x372.png', W, H, bg, """
      <div style="position:absolute;left:44px;top:40px;display:flex;align-items:flex-start;gap:20px">
        <div class="title" style="font-size:80px;white-space:nowrap">SEAF Artillery Loadout</div>
        <span class="badge" style="font-size:32px;margin-top:6px">v%(v)s</span></div>
      %(row)s""" % {'v': ver, 'row': placed(70, 44, 190, ghost=False)}))
    # AyakaMods cover 1.6:1: everything that matters inside the middle 1190x800 (the mod cards crop it to 1.2:1 .. 2:1)
    W, H = 1600, 1000
    bg = hero.hero(W, H, 1180, 900, 380, seed=13)
    jobs.append(('AyakaMods-Cover-1600x1000.png', W, H, bg, """
      <div style="position:absolute;left:0;right:0;top:170px;display:flex;justify-content:center;align-items:flex-start;gap:22px">
        <div class="title" style="font-size:104px;white-space:nowrap">SEAF Artillery Loadout</div>
        <span class="badge" style="font-size:40px;margin-top:8px">v%(v)s</span></div>
      %(row)s""" % {'v': ver, 'row': placed(112, None, 470, W)}))
    with sync_playwright() as p:
        b = p.chromium.launch()
        page = b.new_page()
        for name, W, H, bg, body in jobs:
            png = render(page, W, H, bg, body)
            open(os.path.join(out, name), 'wb').write(png)
            print(name)
        b.close()
    # the Arsenal icon in the mod zip: the thumbnail at 512 (Arsenal shows it small)
    Image.open(os.path.join(out, 'thumbnail.png')).convert('RGB').resize((512, 512), Image.LANCZOS).save(
        os.path.join(out, 'icon.png'), optimize=True)
    print('icon.png')


if __name__ == '__main__':
    main()
