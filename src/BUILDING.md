# SEAF Artillery Loadout - source

A Bingus Shared Loader Lua mod: one addon, `lua/seaf_artillery_loadout.lua`, its HD2 HUD+ add-on
`lua/seaf_artillery_loadout_hudplus.lua`, and its shell icons.

    lua/seaf_artillery_loadout.lua
                    the addon (plain Lua; Bingus Shared Loader finds it by its first line). The --@@ICONS@@ line is
                    filled in by build.py with the shell icon textures' ids and colors.
    lua/seaf_artillery_loadout_hudplus.lua
                    the HD2 HUD+ add-on (plain Lua; HD2 HUD+ finds it by its first line, Bingus skips it): it draws
                    the shells the addon has read on HD2 HUD+'s stratagem panel. Tested on HD2 HUD+ 0.2.2 and 0.2.4;
                    it reads memory through the addon's safe reader and takes the pin of the HUD+ build that loads
                    it once that build has everything it uses, so a new HUD+ version needs no rebuild.
    build.py        builds the mod zip (Python 3 + Pillow):
                      python3 build.py out              -> out/SEAF-Artillery-Loadout-<ver>.zip (the release)
                      python3 build.py out --tester     -> the Tester build (extra details in the log)
                      python3 build.py out --test N     -> numbered test build N (log in Logs\test, test GUID)
                      python3 build.py out --test N --spoof
                                                        -> a numbered test build with made-up shells on the list's
                                                           first row (no SEAF Artillery needed; the name fix is off)
                    The output folder is emptied first, but only a folder build.py made (it carries the marker
                    file .seaf-artillery-loadout-build), never this folder or one above it.
                    It also draws the shell icons (64x64 textures, one per shell type, plus the next shell's
                    yellow bar for the HD2 HUD+ add-on) and writes
                    out/icons_preview.png.
    patch_writer.py writes the patch archive
    fonts/          Anton (SIL Open Font License), for the "?" on the unknown shell and the icon of numbered test builds
    artwork/        the release art:
                      hero.py         the scene, a flat illustration (Python 3 + NumPy, SciPy, Pillow)
                      cards.py        the thumbnail, gallery, header, GitHub social picture, AyakaMods cover and the
                                      Arsenal icon: the scene from hero.py, the stratagem row with the mod's own shell
                                      icons (from build.py), and the title and text as HTML rendered with Playwright
                                      Chromium (python3 cards.py <out dir> 1.1)
                      icon.png        the Arsenal icon build.py puts in the zip (the 1.1.0 art); fonts/ (SIL Open Font License)

Run them from this folder. The release build is deterministic: it rebuilds the release zip byte for byte.
