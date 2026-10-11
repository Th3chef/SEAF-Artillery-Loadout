# Changelog

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
