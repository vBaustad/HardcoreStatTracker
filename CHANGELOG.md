# Changelog

## 1.9.0

### Season of Discovery & non-Hardcore support
- HST now adapts to the game version. On **Season of Discovery** and other non-Hardcore
  realms it hides the permadeath-only bits and leans into combat:
  - **Famous Last Words**, the **Memorial**, and death recording are skipped.
  - The survival / death-proximity stats (Closest Call, Nearest Death, Panic Moments,
    Untouched Streak, Clutch Saves, Safety Tools, Drowned, Pet/Party Deaths) are hidden and
    no longer tracked - they don't mean much when you respawn (and Closest Call / Nearest
    Death used to get stuck at 0 after a death).
  - **"Time Alive"** is shown as **"Time Played."**
- Hardcore is recognised from the realm ruleset **or** a running Hardcore addon, so
  community-Hardcore players keep the full feature set.

### Fixes
- In **full-width bar** mode (with screen-adjust on), the top-center displays now sit *below*
  the bar instead of overlapping it - the centered event bar (e.g. Season of Discovery's
  Ashenvale progress) and the battleground / objective score display.
- **Players Saved** no longer keeps a list of names - just the running count.
- **Minimap button** sits cleanly on the ring at the right size, with a hover glow, and
  scales with the minimap instead of drifting off the edge when it's resized.

## 1.8.0

### New stats
- **Best Loot** - the best blue or epic item you've looted from an open-world kill
  or chest, with where you found it. Dungeon/raid loot, quest rewards, crafted items,
  and anything below rare quality don't count - it's a self-found "best find."
- **Safety Tools Used** - how many hardcore panic buttons you've burned: Limited
  Invulnerability / Free Action / Living Action potions, Flask of Petrification, and
  target dummies.
- **Items Crafted** - lifetime count of things you've crafted at a profession.
- **Top Profession** - your highest profession skill right now, across all professions.
- All four are off by default - turn them on from the Mini Panel settings page
  (Survival, Profession, and Wealth sections). The full window always lists them.

### Mini panel
- The **full-width bar** can now be a custom width and nudged left/right - handy if you
  stream an ultrawide game but capture a narrower window. Set a width, then center it.
- New **Stats: Left / Center / Right** option for which way the stats fill the bar
  (start at the left and grow right, start at the right and grow left, or stay centered).

### Full window
- The close button is now a themed **X** that matches the rest of the window, and
  **What's New** moved up next to it.

### Fixes
- **Toughest Foe** now only counts enemies you actually *killed* (it used to update just
  from trading blows). Your existing record is kept.
- **Pet Deaths** now detect reliably from the death itself, so a pet dying is always
  counted - and reviving or re-summoning a pet never miscounts.

## 1.7.0

### Fixes
- **Fixed an addon conflict that could block the Looking For Group listings.** The
  settings dropdowns no longer use Blizzard's shared dropdown system, which was
  tainting the Group Finder's search.
- `/hst reset` no longer resets the minimap button (on/off + position).

### Mini panel
- New **full-width bar mode** - a Titan-style bar across the top of the screen
  instead of the stacked panel (Mini Panel -> Display -> Full-width bar). It
  auto-fits as many stats as will show, stacks neatly below TitanPanel, and has an
  optional **Adjust screen** toggle that pushes the minimap down so the bar doesn't
  cover it.
- The Mini Panel settings page is reorganized: an always-visible **Display** section
  (mode, size, opacity, in-combat timer, highlight) above compact, themed tabs for
  the stat categories.

### Onboarding
- The welcome window is now an **interactive carousel** - preview a comic splash and
  turn it on right there, with stat-icon and splash-art visuals.
- New **What's New** panel that pops once after an update, re-openable via `/hst news`
  or the full window's button.

### Chat
- Auto **record announcements are tagged `[HST]`** and reworded to read as plain
  addon reports; the guild clutch line reads as a broadcast ("...just survived a
  battle with only 4% HP left").
- The `/hst share` summary reads better (no tag - you send it yourself).

### Full window
- **Mak'gora now always shows on the Account tab** (it's account-wide), even at 0/0.

## 1.6.0

### Splashes
- New art: **WHAM!** and **CRACK!**, plus a cleaner **WOW!** (replaced the old
  watermarked one).
- **Visual art picker** — click a slot's art thumbnail in settings to choose from
  a gallery of every splash image, instead of reading a text dropdown.
- Comic splashes are now **off by default** — turn them on with "Show comic
  splashes" in the Splashes settings. The default slots are preset (POW! on crit,
  BOOM! on melee, ZAP! on ranged), so it works the moment you enable it.

### Fixes
- `/hst reset` no longer resets your splash duration or the "random art on every
  crit" toggle.

## 1.5.1

### New stats
- **Gold Spent**, **Total Damage Done**, **Jumps**, and **Biggest Ability Hit** —
  physical "yellow" abilities (Sinister Strike, Aimed Shot...) split out from
  Biggest Spell, which is now magic-only.
- **Account milestones (account-wide):** Highest Level reached, Level 60s (how
  many of your characters have hit max level), and Characters Drowned.

### Memorial
- The death memorial is now an **account-wide roll of fallen heroes** — browse the
  list, click any name to read their card, and Share it. Empty until your first
  death (and it roots for you to keep it that way). Open via the skull button on
  the full window or `/hst memorial`.

### Splashes
- New **"Random art on every crit"** mode: a random art + sound at one of your six
  positioned spots, every couple of seconds.
- Splash sounds now play on the **Sound Effects** channel (set the volume via the
  game's Sound Effects slider); the per-slot Sound dropdown replaced the global checkbox.

### Quality of life
- **Minimap button** (left-click: full window, right-click: settings, drag to move).
- **`/hst share`** posts a one-line stat summary to chat.
- Mini panel now **abbreviates big numbers** (1k / 1.5k / 1.2M), plus **Show all /
  Hide all** buttons on the Mini Panel settings.
- Full window: **Time Alive moved to the header**, tighter rows, and sections
  organized into **Combat / World / Account tabs** so it stays a sane height.

### Fixes
- Biggest Melee / Ranged / Spell / Ability records track **non-crit** hits (crits
  go to Highest Crit); DoT ticks no longer count as crits or hits.
- The integrity check is **versioned**, so adding new tracked stats never
  false-flags an existing character as edited.

## 1.5.0

A big update — new stats, a redesigned full window and settings, and an
anti-fake records-integrity check.

### New stats
- **Healing:** Biggest Heal, Total Healing (effective, overheal excluded), and
  Players Saved (a direct heal on a critically-low party member).
- **Wealth:** Gold Earned (lifetime income), Gold Looted (coin off kills/loot),
  and Bags Looted (containers looted off corpses/chests — vendor buys don't count).
- **Biggest Spell Hit** — your largest single direct spell hit (DoT ticks excluded).
- **Pet Killing Blows** — split out from Killing Blows, tracked separately.
- **Highest Fall** now ranks by **% of your max HP** at impact (raw damage shown
  as detail), so it's meaningful across levels.

### Records integrity (anti-fake)
- The full window now shows a **Stat resets** count that survives the reset itself.
- An **integrity check** stamps the saved file on logout and verifies it on login;
  if the `SavedVariables` were edited outside the game, the character is flagged.
  Catches casual file edits — a deterrent, not unbreakable tamper-proofing.

### Interface & settings
- Redesigned full window: balanced two-column layout, icons, color-coded danger
  bar, per-stat explanation tooltips, and "new!" highlights on fresh records.
- **Quick Settings** popup (the **Display** button) with live scale and
  background-opacity sliders for both the mini panel and the full window.
- Settings regrouped into **Mini Panel** and **Full Window** sections with
  per-stat visibility by category.
- Stats you enable on the mini panel now also appear in the full window, even in
  sections it would otherwise hide for your class.
- Marching-ants highlight on a mini-panel row that just set a record.

### Announcements
- Two separate streams: new personal bests to **party / say** after a fight you
  survive (never raid, per-fight cap), and an opt-in **guild** line only for
  genuine clutch survivals (≤5% HP), rate-limited and never fired from the grave.

### Splashes
- Six configurable comic-splash slots — each with its own art, trigger stat,
  sound, position, and on/off.

### Other
- Renamed to **Hardcore Stat Tracker** (`/hst`, with `/hcstats` and `/hc`
  aliases). Old `HCStats` saved data migrates automatically.
- Stat-honesty pass: every label and tooltip now matches exactly what is tracked.
