local ADDON, HC = ...

HC.state = HC.state or {}

-- ---------------------------------------------------------------------------
-- Saved-variable record defaults (records only; layout stored separately)
-- ---------------------------------------------------------------------------
local RECORD_DEFAULTS = {
    lowestPct      = nil,  lowestHP   = nil, lowestMax = nil,
    lowestLevel    = nil,  lowestZone = nil, lowestSource = nil,
    biggestHit     = 0,    biggestHitSource = nil, biggestHitSpell = nil,
    biggestHitLevel = nil, biggestHitZone = nil,
    highestCrit    = 0,    highestCritSpell = nil, highestCritTarget = nil,
    longestFight   = 0,    longestFightZone = nil,
    mostDmgFight   = 0,    mostDmgFightZone = nil,
    killingBlows   = 0,
    petKillingBlows = 0,
    panicMoments   = 0,
    fights         = 0,
    biggestMelee   = 0,    biggestMeleeTarget = nil,
    biggestRanged  = 0,    biggestRangedTarget = nil,
    biggestSpell   = 0,    biggestSpellName = nil, biggestSpellTarget = nil,
    biggestAbility = 0,    biggestAbilityName = nil, biggestAbilityTarget = nil,
    biggestHeal    = 0,    biggestHealSpell = nil, biggestHealTarget = nil,
    healingDone    = 0,
    playersSaved   = 0,
    petDeaths      = 0,
    partyDeaths    = 0,
    mostFoes       = 0,
    clutchSaves    = 0,
    untouched      = 0,
    dmgTaken       = 0,
    quests         = 0,
    zones          = 0,
    buffsGiven     = 0,
    goldEarned     = 0,    -- lifetime income (copper); every positive money change
    goldSpent      = 0,    -- lifetime spending (copper); every negative money change
    goldLooted     = 0,    -- coin picked up from loot only (copper)
    bagsLooted     = 0,    -- containers looted off corpses/chests (not bought)
    biggestLevelDiff = nil, biggestLevelDiffMob = nil,
    biggestLevelDiffMyLevel = nil, biggestLevelDiffZone = nil,
}

local LAYOUT_DEFAULTS = {
    shown      = true,
    locked     = false,
    fontSize   = 12,
    scale      = 1,
    mobTooltip = true,   -- show "has hit you for X" on mob tooltips
    comicPops  = true,   -- POW/BOOM/ZAP splash on new hit records
    comicRandom = false, -- random art on every crit (mode toggle: random vs the 6 slots)
    comicDuration = 2.0, -- seconds a splash stays on screen (incl. pop + fade)
    combatTimer = true,  -- live "In Combat" line on the mini panel
    miniHighlight = true,-- animated border on a mini row that just set a record
    fullAlpha  = 0.97,   -- full-window background opacity
    fullScale  = 1.0,    -- full-window scale (for high-res / readability)
    miniAlpha  = 0.8,    -- mini-panel background opacity
    point      = { "CENTER", "CENTER", 250, 0 },
}

HC.LAYOUT_DEFAULTS = LAYOUT_DEFAULTS

HC.PANIC_THRESHOLD = 20  -- % HP that counts as a "panic moment"

function HC.ApplyDefaults()
    -- One-time migration from the addon's old "HCStats" name. The old saved
    -- variables are still declared in the .toc, so the game loads them here;
    -- copy them over once, then clear them so they stop being written.
    if HardcoreStatTrackerDB == nil and HCStatsDB ~= nil then
        HardcoreStatTrackerDB = HCStatsDB
    end
    if HardcoreStatTrackerAccountDB == nil and HCStatsAccountDB ~= nil then
        HardcoreStatTrackerAccountDB = HCStatsAccountDB
    end
    HCStatsDB, HCStatsAccountDB = nil, nil

    HardcoreStatTrackerDB = HardcoreStatTrackerDB or {}
    for k, v in pairs(RECORD_DEFAULTS) do
        if HardcoreStatTrackerDB[k] == nil then HardcoreStatTrackerDB[k] = v end
    end
    for k, v in pairs(LAYOUT_DEFAULTS) do
        if HardcoreStatTrackerDB[k] == nil then
            HardcoreStatTrackerDB[k] = (type(v) == "table") and { unpack(v) } or v
        end
    end
    if not HardcoreStatTrackerDB.show then HardcoreStatTrackerDB.show = {} end          -- per-stat visibility
    if not HardcoreStatTrackerDB.petDeathLog then HardcoreStatTrackerDB.petDeathLog = {} end
    if not HardcoreStatTrackerDB.partyDeathLog then HardcoreStatTrackerDB.partyDeathLog = {} end
    if not HardcoreStatTrackerDB.playerSavedLog then HardcoreStatTrackerDB.playerSavedLog = {} end
    if not HardcoreStatTrackerDB.zonesVisited then HardcoreStatTrackerDB.zonesVisited = {} end
    if not HardcoreStatTrackerDB.recordStamps then HardcoreStatTrackerDB.recordStamps = {} end  -- [statKey] = time() of last record

    -- Anti-fake audit trail (see the integrity section below). resets is a plain
    -- count of full record resets; tamperCount/tamperedEver are set when the
    -- saved-stats integrity check fails. All three persist through a reset.
    if HardcoreStatTrackerDB.resets       == nil then HardcoreStatTrackerDB.resets       = 0 end
    if HardcoreStatTrackerDB.tamperCount  == nil then HardcoreStatTrackerDB.tamperCount  = 0 end
    if HardcoreStatTrackerDB.tamperedEver == nil then HardcoreStatTrackerDB.tamperedEver = false end

    -- One-time smart defaults for the mini view: keep it to a tight core, and
    -- only show pet stats for pet classes. Existing user toggles are preserved.
    if (HardcoreStatTrackerDB.showVersion or 0) < 1 then
        local _, class = UnitClass("player")
        local petClass = (class == "HUNTER" or class == "WARLOCK")
        local hiddenByDefault = {
            "biggestMelee", "biggestRanged", "biggestSpell", "highestFall", "longestFight", "mostDmgFight",
            "panic", "fights", "partyDeaths", "mostFoes", "clutchSaves", "untouched",
            "dmgTaken", "quests", "zones", "makgoraWon", "makgoraLost",
        }
        for _, k in ipairs(hiddenByDefault) do
            if HardcoreStatTrackerDB.show[k] == nil then HardcoreStatTrackerDB.show[k] = false end
        end
        if not petClass then
            if HardcoreStatTrackerDB.show.currentPet == nil then HardcoreStatTrackerDB.show.currentPet = false end
            if HardcoreStatTrackerDB.show.petDeaths == nil then HardcoreStatTrackerDB.show.petDeaths = false end
        end
        HardcoreStatTrackerDB.showVersion = 1
    end
    if (HardcoreStatTrackerDB.showVersion or 0) < 2 then
        if HardcoreStatTrackerDB.show.buffsGiven == nil then HardcoreStatTrackerDB.show.buffsGiven = false end
        HardcoreStatTrackerDB.showVersion = 2
    end
    if (HardcoreStatTrackerDB.showVersion or 0) < 3 then
        if HardcoreStatTrackerDB.show.biggestSpell == nil then HardcoreStatTrackerDB.show.biggestSpell = false end
        HardcoreStatTrackerDB.showVersion = 3
    end
    if (HardcoreStatTrackerDB.showVersion or 0) < 4 then
        -- Healing stats are off by default (only casters care); opt in per stat.
        for _, k in ipairs({ "biggestHeal", "healingDone", "playersSaved" }) do
            if HardcoreStatTrackerDB.show[k] == nil then HardcoreStatTrackerDB.show[k] = false end
        end
        HardcoreStatTrackerDB.showVersion = 4
    end
    if (HardcoreStatTrackerDB.showVersion or 0) < 5 then
        for _, k in ipairs({ "goldEarned", "goldLooted" }) do
            if HardcoreStatTrackerDB.show[k] == nil then HardcoreStatTrackerDB.show[k] = false end
        end
        HardcoreStatTrackerDB.showVersion = 5
    end
    if (HardcoreStatTrackerDB.showVersion or 0) < 6 then
        if HardcoreStatTrackerDB.show.petKillingBlows == nil then HardcoreStatTrackerDB.show.petKillingBlows = false end
        HardcoreStatTrackerDB.showVersion = 6
    end
    if (HardcoreStatTrackerDB.showVersion or 0) < 7 then
        if HardcoreStatTrackerDB.show.bagsLooted == nil then HardcoreStatTrackerDB.show.bagsLooted = false end
        HardcoreStatTrackerDB.showVersion = 7
    end
    if (HardcoreStatTrackerDB.showVersion or 0) < 8 then
        if HardcoreStatTrackerDB.show.goldSpent == nil then HardcoreStatTrackerDB.show.goldSpent = false end
        HardcoreStatTrackerDB.showVersion = 8
    end
    if (HardcoreStatTrackerDB.showVersion or 0) < 9 then
        if HardcoreStatTrackerDB.show.biggestAbility == nil then HardcoreStatTrackerDB.show.biggestAbility = false end
        HardcoreStatTrackerDB.showVersion = 9
    end

    if not HardcoreStatTrackerDB.lastWords then HardcoreStatTrackerDB.lastWords = {} end
    local lw = HardcoreStatTrackerDB.lastWords
    if lw.enabled        == nil then lw.enabled        = false end
    if lw.sayThreshold   == nil then lw.sayThreshold   = lw.threshold or 15 end
    if lw.alertThreshold == nil then lw.alertThreshold = 30 end
    if lw.channel        == nil then lw.channel        = "SAY" end
    if lw.say            == nil then lw.say            = true end
    if lw.alertSelf      == nil then lw.alertSelf      = false end
    if lw.useDefaults    == nil then lw.useDefaults    = true end
    if lw.custom         == nil then lw.custom         = {} end
    -- The low-health alert used to be gated by the Famous Last Words master, so
    -- it never fired unless that was on. Now it's independent; preserve effective
    -- state once: if FLW was off, the alert was inert -> keep it off.
    if lw.decoupledAlert == nil then
        if not lw.enabled then lw.alertSelf = false end
        lw.decoupledAlert = true
    end

    -- Comic splash slots: 6 configurable entries, each { art, stat, sound, x, y }.
    -- art = "none" disables that slot; a slot's sound plays unless it's "none".
    local SPLASH_DEFAULTS = {
        { art = "pow",  stat = "highestCrit",   sound = "pow",  x =  150, y =  100 },
        { art = "boom", stat = "biggestMelee",  sound = "bonk", x = -170, y =   90 },
        { art = "zap",  stat = "biggestRanged", sound = "pew",  x =  160, y =  -60 },
        { art = "none", stat = "biggestSpell",  sound = "none", x = -150, y =  120 },
        { art = "none", stat = "biggestHit",    sound = "none", x =    0, y =  150 },
        { art = "none", stat = "closestCall",   sound = "none", x =  150, y = -150 },
    }
    if not HardcoreStatTrackerDB.comic then
        HardcoreStatTrackerDB.comic = {}
    elseif HardcoreStatTrackerDB.comic.pow then
        -- Migrate the old pow/boom/zap dict into slots 1-3 (off -> art "none").
        local old = HardcoreStatTrackerDB.comic
        local function conv(o, defArt)
            if not o then return nil end
            return {
                art   = (o.on == false) and "none" or (o.art or defArt),
                stat  = o.stat, sound = o.sound or "none",
                x = o.x or 0, y = o.y or 0,
            }
        end
        HardcoreStatTrackerDB.comic = {
            conv(old.pow, "pow"), conv(old.boom, "boom"), conv(old.zap, "zap"),
        }
    end
    -- Ensure all 6 slots exist and have every field.
    local comic = HardcoreStatTrackerDB.comic
    for i = 1, 6 do
        local d = SPLASH_DEFAULTS[i]
        local c = comic[i]
        if not c then c = {}; comic[i] = c end
        if c.art   == nil then c.art   = d.art end
        if c.stat  == nil then c.stat  = d.stat end
        if c.sound == nil then c.sound = d.sound end
        if c.x     == nil then c.x     = d.x end
        if c.y     == nil then c.y     = d.y end
    end

    if not HardcoreStatTrackerDB.announce then HardcoreStatTrackerDB.announce = {} end
    local an = HardcoreStatTrackerDB.announce
    if an.enabled   == nil then an.enabled   = false end
    -- Records stream -> party/say only.
    if an.records   == nil then an.records   = true end
    if an.max       == nil then an.max       = 2 end
    if an.stats   == nil then
        an.stats = { closestCall = true, toughestFoe = true, highestCrit = true, nearestDeath = true }
    end
    -- Clutch survival stream -> guild only, opt-in. The 5% threshold and 5-min
    -- cooldown are fixed in code (not user-tunable), so just a toggle here.
    if an.clutch == nil then an.clutch = false end
    an.guild, an.guildOnly, an.clutchPct, an.clutchCooldown = nil, nil, nil, nil  -- retired fields

    -- Account-wide stats (persist across all characters). Mak'gora especially:
    -- a loss is the character's death, so it only makes sense account-wide.
    HardcoreStatTrackerAccountDB = HardcoreStatTrackerAccountDB or {}
    if HardcoreStatTrackerAccountDB.makgoraWon  == nil then HardcoreStatTrackerAccountDB.makgoraWon  = 0 end
    if HardcoreStatTrackerAccountDB.makgoraLost == nil then HardcoreStatTrackerAccountDB.makgoraLost = 0 end
    if HardcoreStatTrackerAccountDB.makgoraDebug == nil then HardcoreStatTrackerAccountDB.makgoraDebug = false end
    if HardcoreStatTrackerAccountDB.mobDamage == nil then HardcoreStatTrackerAccountDB.mobDamage = {} end
    HC.adb = HardcoreStatTrackerAccountDB

    -- One-time migration: mob damage history used to be per-character.
    if HardcoreStatTrackerDB.mobDamage then
        for name, rec in pairs(HardcoreStatTrackerDB.mobDamage) do
            local cur = HardcoreStatTrackerAccountDB.mobDamage[name]
            if not cur or (rec.hit or 0) > (cur.hit or 0) then
                HardcoreStatTrackerAccountDB.mobDamage[name] = rec
            end
        end
        HardcoreStatTrackerDB.mobDamage = nil
    end

    -- Keep the account-wide mob table bounded: prune least-recently-seen.
    local MOB_CAP, MOB_TRIM = 400, 300
    local n = 0
    for _ in pairs(HardcoreStatTrackerAccountDB.mobDamage) do n = n + 1 end
    if n > MOB_CAP then
        local byAge = {}
        for name, rec in pairs(HardcoreStatTrackerAccountDB.mobDamage) do
            byAge[#byAge + 1] = { name = name, seen = rec.seen or 0 }
        end
        table.sort(byAge, function(a, b) return a.seen < b.seen end)
        for i = 1, n - MOB_TRIM do
            HardcoreStatTrackerAccountDB.mobDamage[byAge[i].name] = nil
        end
    end

    HC.db = HardcoreStatTrackerDB    -- exposed for Options.lua
end

-- ---------------------------------------------------------------------------
-- Saved-stats integrity check (anti-fake)
--
-- We hash the headline record values (plus the reset/tamper counters) together
-- with a fixed salt and store the result next to the data. On login we recompute
-- and compare: if someone hand-edited the SavedVariables .lua to inflate a
-- number - or to quietly zero the reset/tamper counters - the stored hash no
-- longer matches and we flag the character.
--
-- This catches CASUAL file edits only. The salt and algorithm are visible in
-- this (plaintext) addon, so a determined editor could recompute a valid hash
-- after changing values. Treat it as a deterrent and a "did anyone touch the
-- file" signal, not as tamper-proofing. The hash is recomputed at logout/reload
-- (the only time SavedVariables are written), so it always matches a clean
-- session; a crash reverts both data and hash together, so it never false-flags.
-- ---------------------------------------------------------------------------
local INTEGRITY_SALT = "HST-v1-3f9a2c7e-stat-integrity"

-- Every value-bearing record field a faker might inflate. The three audit
-- counters are signed too, so they can't be reset in the file without tripping
-- the same check. Sorted once for a deterministic serialization order.
local PROTECTED = {
    "lowestPct", "lowestHP", "lowestMax", "lowestLevel", "lowestZone", "lowestSource",
    "closestSeconds", "closestSecHP", "closestSecLevel", "closestSecZone", "closestSecSource",
    "biggestHit", "biggestHitSource", "biggestHitSpell", "biggestHitLevel", "biggestHitZone",
    "highestFall", "highestFallPct", "highestFallLevel", "highestFallZone",
    "panicMoments", "clutchSaves", "untouched", "mostFoes", "fights", "dmgTaken",
    "longestFight", "longestFightZone", "mostDmgFight", "mostDmgFightZone",
    "biggestLevelDiff", "biggestLevelDiffMob", "biggestLevelDiffMyLevel", "biggestLevelDiffZone",
    "highestCrit", "highestCritSpell", "highestCritTarget",
    "biggestMelee", "biggestMeleeTarget", "biggestRanged", "biggestRangedTarget",
    "biggestSpell", "biggestSpellName", "biggestSpellTarget",
    "biggestAbility", "biggestAbilityName", "biggestAbilityTarget",
    "killingBlows", "petKillingBlows",
    "biggestHeal", "biggestHealSpell", "biggestHealTarget", "healingDone", "playersSaved",
    "petDeaths", "partyDeaths", "buffsGiven",
    "quests", "zones", "goldEarned", "goldSpent", "goldLooted", "bagsLooted",
    "resets", "tamperCount", "tamperedEver",
}
table.sort(PROTECTED)

function HC.ComputeIntegrity()
    local db = HardcoreStatTrackerDB
    if not db then return nil end
    local parts = {}
    for _, k in ipairs(PROTECTED) do
        parts[#parts + 1] = k .. "=" .. tostring(db[k])
    end
    return HC.Hash(INTEGRITY_SALT .. "\30" .. table.concat(parts, "\30"))
end

-- Recompute and store the stamp. Called at logout/reload and after any in-game
-- action that legitimately changes the protected values (resets), so the file
-- on disk always carries a matching hash.
function HC.StoreIntegrity()
    if not HardcoreStatTrackerDB then return end
    HardcoreStatTrackerDB.integrity = HC.ComputeIntegrity()
end

-- Returns true if a stamp exists and no longer matches the data (i.e. the file
-- was edited outside the game). Records the event. No stamp yet = first run
-- after this feature shipped: establish a baseline at the next logout, no flag.
function HC.CheckIntegrity()
    local db = HardcoreStatTrackerDB
    if not db then return false end
    if not db.integrity then return false end
    if db.integrity ~= HC.ComputeIntegrity() then
        db.tamperCount  = (db.tamperCount or 0) + 1
        db.tamperedEver = true
        return true
    end
    return false
end
