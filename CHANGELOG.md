# Changelog

## 0.1.1

- Automatic mode now switches tracking in combat too. C_Minimap.SetTracking has no combat restriction, so there is no reason to wait for the fight to end. The 3 second confirmation check works in combat as well.
- If the client ever blocks SetTracking in combat (ADDON_ACTION_BLOCKED or ADDON_ACTION_FORBIDDEN naming AutoTrack), AutoTrack remembers that, holds the switch until combat ends, and stays in automatic mode. It says so once in chat. `/autotrack retry` forgets it.
- Keybind mode is unchanged: its button spell is still only changed out of combat.

## 0.1.0

- First release. Hunters only: when you target a creature, minimap tracking switches to the matching hunter track (beasts, humanoids, undead, demons, elementals, giants, dragonkin).
- Maps by creature type ID, with English names as a second chance. Only switches to a track the hunter has learned, skips when it is already on, and never runs in combat lockdown (it applies after combat if the target is still valid). One switch per second at most.
- Reads the creature type through a secret value guard and does nothing if it is secret.
- Waits for MINIMAP_UPDATE_TRACKING to confirm a switch. With no confirmation within 3 seconds, or on ADDON_ACTION_BLOCKED or ADDON_ACTION_FORBIDDEN naming AutoTrack, it tells you once and switches to a keybind button (Options, Keybindings, AutoTrack (Hunter)). The button fires once per press (key up) and its spell is only changed out of combat.
- Addon list icon: Ability_Tracking.
- `/autotrack on|off|status|scope attackable|any|default <type|none>|retry`. Account wide `AutoTrackDB`.
