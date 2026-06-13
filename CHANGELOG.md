# Changelog

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
