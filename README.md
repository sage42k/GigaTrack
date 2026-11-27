# GigaTrack

**[Download GigaTrack 0.4.0](https://github.com/sage42k/GigaTrack/releases/latest/download/GigaTrack-0.4.0.zip)**

Tracking for hunters, without opening the menu.

Target something. If you're not tracking its creature type, GigaTrack puts the right Track icon in the middle of your screen. Click it. Done.

## Setup

1. Drop the `GigaTrack` folder into `World of Warcraft\_forever_\Interface\AddOns`.
2. Restart the game. A `/reload` won't pick up a new add-on.
3. Optional: type `/gigatrack macro` and drop the macro on your bar for a one-key track.

## How it behaves

- Works with every track you know: beasts, humanoids, undead, demons, elementals, giants, dragonkin.
- Players always count as humanoid, forms included.
- It never changes your tracking on its own. You click, it casts.
- The icon only shows up when your tracking is wrong. The rest of the time you'll forget it's installed.

## Moving it

Shift-drag the icon. Or right-click the minimap button to unlock it, drag it, and right-click again to lock. `/gigatrack scale 0.75` sets the size, anywhere from 0.5 to 2.

## Minimap button

Left-click turns the reminder on or off. Right-click locks or unlocks the icon.

## In combat

WoW doesn't let add-ons change what a button casts mid-fight. If you switch to a different creature type in combat, the icon stays on your current track, greyed out, and catches up the moment combat ends.

## Commands

`/gigatrack` shows help. Also: `on`, `off`, `macro`, `minimap`, `unlock`, `lock`, `scale`, `test`, `report`, `reset`.

Used AutoTrack before? Keep its folder for one launch so your settings come across, then delete it.

Made by Hearth & Log Studios. MIT licensed. Bugs and ideas: https://github.com/sage42k/GigaTrack/issues
