# AutoTrack

**Hunters: target something, and your tracking follows.**

Stop opening the tracking menu. Target a wolf and AutoTrack turns on Track Beasts. Target a ghoul and it switches to Track Undead. That is the whole idea, and it stays out of your way otherwise.

Made for **WoW Forever** (game version 1.60.1).

## Download

**[Download AutoTrack 0.1.0](https://github.com/sage42k/AutoTrack/releases/latest/download/AutoTrack-0.1.0.zip)**

## Install

1. Close the game.
2. Unzip the download. You get a folder called `AutoTrack`.
3. Move that folder into your add-ons folder:
   `World of Warcraft\_forever_\Interface\AddOns\`
4. Start the game and make sure AutoTrack is ticked on the AddOns screen at character select.

That is it. On a hunter it starts working the first time you target something.

## What it switches to

| You target a... | AutoTrack turns on |
|---|---|
| Beast | Track Beasts |
| Humanoid | Track Humanoids |
| Undead | Track Undead |
| Demon | Track Demons |
| Elemental | Track Elementals |
| Giant | Track Giants |
| Dragonkin | Track Dragonkin |

- It only uses tracks your hunter has learned.
- If the right track is already on, it does nothing.
- If you target something mid fight, it waits until combat ends.
- On any class other than hunter it does nothing at all: no messages, no saved data.

## If it asks you for a key

Some game versions only let tracking change on a real key press. If AutoTrack detects that, it tells you once in chat and switches to key mode:

1. Open **Options**, **Keybindings**, then **AutoTrack (Hunter)**.
2. Bind a key to **AutoTrack: track my target's type**.
3. Target something and press your key. It turns on the matching track.

## Commands

| Command | What it does |
|---|---|
| `/autotrack on` / `/autotrack off` | Turn it on or off |
| `/autotrack status` | Show what it is doing |
| `/autotrack scope any` | Also switch for creatures you cannot attack (default: only attackable ones) |
| `/autotrack default beasts` | Track to use for creatures with no hunter track, like critters (default: leave it alone) |
| `/autotrack retry` | Leave key mode and try automatic switching again |

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/sage42k/AutoTrack/issues).

MIT licensed. By Sage42k.
