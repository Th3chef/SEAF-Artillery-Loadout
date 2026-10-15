# Changelog

## 1.1.1

- **Works with HD2 HUD+ 0.2.4:** the shells show on its stratagem panel again (with 1.1.0 they didn't on 0.2.4).
- **Ready for future HD2 HUD+ versions:** when HUD+ loads the add-on, it checks that HUD+ still has everything it uses, so a new HUD+ version needs no update of this mod. If a future one changes how its stratagem panel works, HUD+ skips the add-on cleanly and the log says why.
- **Safer:** the HUD+ add-on reads memory only through this mod's own safe reader, so a bad address can never crash the game.

## 1.1.0

- **Works with HD2 HUD+:** the shells now show on HD2 HUD+'s own stratagem panel, next to its SEAF Artillery row (a small HUD+ add-on built into the mod, for HD2 HUD+ 0.2.2).
- The High-Yield Explosive icon is now yellow, like the shell in game (it was orange).
- New art.

## 1.0.1

- The name fix checks the HUD every frame, so a new mission can never leave it writing to the previous mission's HUD.
- The icons check the game's overlay before every redraw and when the list closes (a mission load can remove it at any moment), and stay off without retrying every frame while there is none.
- The row size and the row's stratagem id place are read from the game's code instead of being fixed numbers (patch-proof).
- The cached game addresses are checked against the game's code at every start.
- The log's per-frame cost no longer counts the start-up scan.

## 1.0.0

First release.

- Once the SEAF Artillery objective is done, the shells still loaded in the artillery show as icons right of the SEAF Artillery stratagem while the stratagem list is open: in firing order, the next shell on a yellow bar, fired shells dropping off.
- A color per shell type: Explosive, High-Yield Explosive, Mini Nuke, Napalm, Smoke and Static Field (an unknown type shows as a gray "?").
- Follows the game's own list (slide-in, fade, any resolution and HUD scale); hidden while another mod hides the game's list.
- Fixes the game's `SEAF ARTILLERY: <shell>` name, which can keep naming a shell that was already fired: the game redoes it when the next shell changes.
- On/off toggles in game with Mod Options Menu (the icons and the name fix).
- Finds what it needs in the game's code by itself (patch-proof).
