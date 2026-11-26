# GigaTrack

**[Download GigaTrack 0.4.0](https://github.com/sage42k/GigaTrack/releases/latest/download/GigaTrack-0.4.0.zip)**

## How to track

Click the icon, or make a macro with `/gigatrack macro`, or use `/click GigaTrackButton`.

The macro is named "GigaTrack" and lands on your cursor. Drop it on your action bar for a one-key track. By hand it is `/click GigaTrackButton`. Do not add `LeftButton 1` to it, that sends a key-down click which GigaTrack ignores on purpose, so a press never casts twice. The old `/click AutoTrackButton` and `/click HunterHelperAutoTrackButton` still work, and an old macro named "AutoTrack" is updated in place by `/gigatrack macro`. You can also bind a key: Options, Keybindings, AddOns, GigaTrack.

## What it does

For hunters on WoW Forever. When your target's creature type has a Track spell you know (beast, humanoid, undead, demon, elemental, giant, dragonkin) and that track is not active, a steady icon of the Track spell shows on screen. Click it to track. Hover it to read "Click to track Beast" (or whichever creature type it is). Players always count as humanoid. Nothing ever switches by itself. Other classes see nothing.

The icon hides when the right track is active, when you lose the target, when the target dies, or when you have not learned the track. When nothing needs tracking a click does nothing, and the tooltip says "Nothing to track".

## Install

Copy the `GigaTrack` folder into `World of Warcraft\_forever_\Interface\AddOns\GigaTrack`, then close the game completely and start it again. A full restart is needed, `/reload` is not enough.

## Coming from AutoTrack

GigaTrack is AutoTrack under a new name, because another add-on already uses "AutoTrack" on CurseForge.

To carry over your icon position, scale and settings, keep the old `AutoTrack` folder for one launch. GigaTrack copies your settings across once, and keeps its icon hidden that launch so you do not see two. It prints one line to remind you. Then delete the `AutoTrack` folder. If you delete it before the first launch, you simply start with the defaults.

## Minimap button

Left click turns the reminder on or off. Right click locks or unlocks the icon. Drag it to move it around the minimap. `/gigatrack minimap` hides or shows it.

## Moving the icon

Hold Shift and drag the icon, out of combat. Or unlock it (`/gigatrack unlock`, or right click the minimap button), drag it, and lock it again. `/gigatrack scale 0.5-2` sizes it, new installs start at 0.75. `/gigatrack test` shows it for 5 seconds. Position and size are saved.

## Commands

`/gigatrack` shows help, and `/autotrack` still works as the same command. `on`, `off`, `macro`, `minimap`, `unlock`, `lock`, `scale`, `test`, `report` (recent errors), `reset` (position and the error list).

## In combat

The game does not let add-ons change what a click casts during combat. If your target needs a different track mid-fight, the icon keeps showing the track a click will cast, greyed out, and the tooltip says "Can change after combat". It updates when combat ends. If the needed track is already active, the icon fades out, but a click would still cast the earlier track until combat ends. You cannot move the icon or make the macro in combat.

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/sage42k/GigaTrack/issues).

MIT licensed. By Sage42k.
