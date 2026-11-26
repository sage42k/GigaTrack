# AutoTrack

**[Download AutoTrack 0.3.2](https://github.com/sage42k/AutoTrack/releases/latest/download/AutoTrack-0.3.2.zip)**

## How to track

Click the icon, or make the macro with `/autotrack macro`.

The macro is named "AutoTrack" and lands on your cursor. Drop it on your action bar for a one-key track. By hand it is `/click AutoTrackButton`. Do not add `LeftButton 1` to it, that sends a key-down click which AutoTrack ignores on purpose, so a press never casts twice. `/click HunterHelperAutoTrackButton` still works too. You can also bind a key: Options, Keybindings, AddOns, AutoTrack.

## What it does

For hunters on WoW Forever. When your target's creature type has a Track spell you know (beast, humanoid, undead, demon, elemental, giant, dragonkin) and that track is not active, a steady icon of the Track spell shows on screen. Click it to track. Hover it to read "Click to track Beast" (or whichever creature type it is). Players always count as humanoid. Nothing ever switches by itself. Other classes see nothing.

The icon hides when the right track is active, when you lose the target, when the target dies, or when you have not learned the track. When nothing needs tracking a click does nothing, and the tooltip says "Nothing to track".

## Minimap button

Left click turns the reminder on or off. Right click locks or unlocks the icon. Drag it to move it around the minimap. `/autotrack minimap` hides or shows it.

## Moving the icon

Hold Shift and drag the icon, out of combat. Or unlock it (`/autotrack unlock`, or right click the minimap button), drag it, and lock it again. `/autotrack scale 0.5-2` sizes it, new installs start at 0.75. `/autotrack test` shows it for 5 seconds. Position and size are saved.

## Install

Copy the `AutoTrack` folder into `World of Warcraft\_forever_\Interface\AddOns\`, then close the game completely and start it again. If you still have the `HunterHelper` or `HunterHelper_AutoTrack` folders, remove them, they clash with this add-on. Your old settings are carried over once if the old folder is still there for one start of the game.

## Commands

`/autotrack` shows help. `on`, `off`, `macro`, `minimap`, `unlock`, `lock`, `scale`, `test`, `report` (recent errors), `reset` (position and the error list).

## In combat

The game does not let add-ons change what a click casts during combat. If your target needs a different track mid-fight, the icon keeps showing the track a click will cast, greyed out, and the tooltip says "Can change after combat". It updates when combat ends. If the needed track is already active, the icon fades out, but a click would still cast the earlier track until combat ends. You cannot move the icon or make the macro in combat.

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/sage42k/AutoTrack/issues).

MIT licensed. By Sage42k.
