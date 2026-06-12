# HC Stats

**A trophy case for your hardcore character.** HC Stats quietly records your closest calls, biggest hits, toughest kills, and the rest of your run's defining moments, and shows them in a compact on-screen panel and a detailed full window. Built for **WoW Classic Era / Hardcore (1.15.x)**.

## Features

- **Survival records** — Closest Call (lowest HP% + the raw number), Nearest Death (how many seconds from dying you were, based on incoming DPS), Biggest Hit Taken, Highest Fall, Clutch Saves, Untouched Streak, Most Foes at Once, Panic Moments.
- **Combat records** — Highest Crit, Biggest Melee/Ranged Hit, Killing Blows, Longest Fight, Most Damage in One Fight, Toughest Foe (highest level above you that you took on).
- **Pet & group** — current pet, pet deaths (with a log), and party-member deaths you witnessed.
- **Adventure** — quests completed, zones explored, total damage taken, time alive.
- **Mak'gora (account-wide)** — duels won and lost, persisting across all your characters.
- **Mob tooltips** — hover a mob and see "Has hit you for up to X" if it's hurt you before.
- **Famous Last Words** — optional: when you drop low, broadcast a cocky/ironic line to chat (built-in surprise pool + your own messages) and/or flash a low-health warning. Independent thresholds for the chat line and the alert.
- **Record announcements** — optional: after a fight you survive, brag about new personal bests in party chat (or /say solo, never raid; optional guild), with a per-fight cap so it stays rare.
- **Two views** — a customizable mini panel (pick exactly which stats show; pets default to pet classes only) and a designed two-column full window with icons, a color-coded danger bar, and context.
- **Adjustable** — text size, panel scale, draggable frames, full per-stat visibility control.

## Installation

1. Download and unzip into `World of Warcraft/_classic_era_/Interface/AddOns/`.
2. Make sure the folder is named `HCStats` and contains the `.toc`.
3. `/reload` or restart the game.

## Usage

- The mini panel appears on screen — drag it anywhere.
- Click the `[+]` button (or `/hcstats full`) for the full window with every stat and its context.
- `/hcstats` opens settings; `/hcstats config` jumps straight there.

## Slash commands

- `/hcstats` — toggle the mini panel
- `/hcstats full` — open the full window
- `/hcstats config` — open settings
- `/hcstats reset` — clear this character's records (account-wide Mak'gora is kept)
- `/hcstats makgora won|lost` — manually record a Mak'gora result
- `/hcstats makgora debug` — print the raw Mak'gora system message (to refine auto-detection)

## Notes

- Stats are **per-character** (each new hardcore character starts fresh) except **Mak'gora**, which is account-wide.
- Text matching for Famous Last Words and a few records is tuned for an **English (enUS)** client.
- Auto chat to `/say` uses the next keypress (a hardware-event requirement), so it fires the moment you press anything after dropping low.

## License

MIT — see [LICENSE](LICENSE).
