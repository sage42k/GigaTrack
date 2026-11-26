# Changelog

## 0.3.1

- Now ships as plain "AutoTrack": folder `AutoTrack`, title "AutoTrack", `AutoTrack.toc`. It replaces the earlier AutoTrack 0.1.x and the 0.3.0 build that shipped as `HunterHelper_AutoTrack`. No HunterHelper wording is left in anything you see in game.
- New button `AutoTrackButton`: use `/click AutoTrackButton` from now on. `HunterHelperAutoTrackButton` is kept as an alias so the macro already handed out keeps working. Both follow the same rules: same spell, attributes changed only out of combat, brought up to date when combat ends.
- Saved variable is now `AutoTrackDB`. On first load the values from `HunterHelper_AutoTrackDB` (on or off, locked, scale, position) are copied in, once. AutoTrack 0.1.x data in `AutoTrackDB` keeps `enabled`; `scope`, `default` and `version` are dropped, new defaults are added. Running it again changes nothing. The old variable is only readable while the old folder is still installed, see the README.
- The key binding is now under "AutoTrack" in the Keybindings screen. The old on or off key of 0.1.x is gone.
- The login warning no longer fires for AutoTrack itself. It appears only when `HunterHelper` or `HunterHelper_AutoTrack` is loaded, and asks you to remove those folders.

## 0.3.0

- New add-on, written from scratch and much simpler than AutoTrack 0.1.2 and HunterHelper's AutoTrack module. It never switches tracking itself. It shows a reminder icon and gives you one button to press.
- Icon: shows the Track spell the target needs, while that track is not active. Pulses gently, and does not pulse if the game's reduced motion setting is on. Centred by default, locked. `/autotrack unlock` draws a border and a "drag me" label while it can be moved.
- Button: secure, type spell. Its spell is only changed out of combat; a change wanted in combat is applied when combat ends.
- Players are always Track Humanoids. Creatures use the creature type ID. Secret values mean "unknown" and show nothing.
- Every handler is wrapped so one error cannot stop the next event. The last 20 errors are kept in the saved variables, shown by `/autotrack report`, and never printed on their own.
- A light re-check every half second corrects the icon if an event was missed.
- Commands: `/autotrack`, `on`, `off`, `unlock`, `lock`, `scale`, `test`, `report`, `reset`.
- Hunters only.

## Earlier: AutoTrack 0.1.x

The 0.1.x line switched tracking by itself and is replaced by this add-on.
