# AutoTrack

**[Download AutoTrack 0.3.1](https://github.com/sage42k/AutoTrack/releases/latest/download/AutoTrack-0.3.1.zip)**

For hunters on WoW Forever. An icon pops up on your screen when your target needs a different Track spell. Press your AutoTrack macro or key, the icon goes away. Nothing ever switches by itself.

Other classes see nothing: no chat, no commands, no icon.

## Install

Copy the `AutoTrack` folder into `World of Warcraft\_forever_\Interface\AddOns\`. Because this is a new add-on for the game, close the game completely and start it again. `/reload` is not enough for a new add-on.

If you still have the `HunterHelper` or `HunterHelper_AutoTrack` folders, remove them from your AddOns folder. You get one line at login if either is enabled. They clash with this add-on.

Your settings (on or off, locked, scale, position) are carried over the first time AutoTrack loads. This works when the old `HunterHelper_AutoTrack` folder is still there for that one start of the game, so start the game once with both before removing the old folder. If you remove it first, AutoTrack just starts with its defaults.

## What you see

When you target something whose type has a Track spell you know (beast, humanoid, undead, demon, elemental, giant, dragonkin) and that track is not active, an icon of the Track spell pulses gently in the middle of your screen. Players always count as humanoid. Hover it to read: "Not tracking your target. Press your AutoTrack macro."

The icon hides the moment the right track is active, when you lose the target, when the target dies, or when you have not learned the track. If your game has a reduced motion setting on, it does not pulse.

## The macro

Make a macro and put it on your bar:

```
/click AutoTrackButton
```

Or bind a key: Options, Keybindings, AddOns, AutoTrack, "Track my target's type". One press casts the track once.

The macro `/click HunterHelperAutoTrackButton` still works, it is the same button under its old name. Use `/click AutoTrackButton` from now on.

## Moving the icon

It starts locked in the centre of the screen.

- `/autotrack unlock` shows the icon with a green border and "drag me", so you can drag it where you want it.
- `/autotrack lock` fixes it again.
- `/autotrack scale 1.5` sizes it, from 0.5 to 2.
- `/autotrack test` shows the icon for 5 seconds.

Position and size are saved.

## Commands

- `/autotrack` shows help
- `/autotrack on` and `/autotrack off` turn the reminder icon on or off. The macro keeps working.
- `/autotrack unlock`, `lock`, `scale 0.5-2`, `test`
- `/autotrack report` lists recent errors, if there were any
- `/autotrack reset` puts the icon back in the centre and clears the error list

## The in-combat limit

The game does not let add-ons change what a key casts during combat. So if you switch to a different creature type in the middle of a fight, the key keeps the previous track until combat ends. The icon still shows what is needed, and the key is brought up to date the moment combat ends.

## Saved data

`AutoTrackDB`: on or off, locked, scale, position, and a small log of the last 20 errors.

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/sage42k/AutoTrack/issues).

MIT licensed. By Sage42k.
