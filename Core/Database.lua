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
    panicMoments   = 0,
    fights         = 0,
    biggestMelee   = 0,    biggestMeleeTarget = nil,
    biggestRanged  = 0,    biggestRangedTarget = nil,
    petDeaths      = 0,
    partyDeaths    = 0,
    mostFoes       = 0,
    clutchSaves    = 0,
    untouched      = 0,
    dmgTaken       = 0,
    quests         = 0,
    zones          = 0,
    buffsGiven     = 0,
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
    combatTimer = true,  -- live "In Combat" line on the mini panel
    fullAlpha  = 0.97,   -- full-window background opacity
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
    if not HardcoreStatTrackerDB.zonesVisited then HardcoreStatTrackerDB.zonesVisited = {} end
    if not HardcoreStatTrackerDB.recordStamps then HardcoreStatTrackerDB.recordStamps = {} end  -- [statKey] = time() of last record

    -- One-time smart defaults for the mini view: keep it to a tight core, and
    -- only show pet stats for pet classes. Existing user toggles are preserved.
    if (HardcoreStatTrackerDB.showVersion or 0) < 1 then
        local _, class = UnitClass("player")
        local petClass = (class == "HUNTER" or class == "WARLOCK")
        local hiddenByDefault = {
            "biggestMelee", "biggestRanged", "highestFall", "longestFight", "mostDmgFight",
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

    if not HardcoreStatTrackerDB.lastWords then HardcoreStatTrackerDB.lastWords = {} end
    local lw = HardcoreStatTrackerDB.lastWords
    if lw.enabled        == nil then lw.enabled        = false end
    if lw.sayThreshold   == nil then lw.sayThreshold   = lw.threshold or 15 end
    if lw.alertThreshold == nil then lw.alertThreshold = 30 end
    if lw.channel        == nil then lw.channel        = "SAY" end
    if lw.say            == nil then lw.say            = true end
    if lw.alertSelf      == nil then lw.alertSelf      = true end
    if lw.useDefaults    == nil then lw.useDefaults    = true end
    if lw.custom         == nil then lw.custom         = {} end

    -- Comic splash config: per-splash enable, linked stat, and screen position.
    if not HardcoreStatTrackerDB.comic then
        HardcoreStatTrackerDB.comic = {
            pow  = { on = true, stat = "highestCrit",   x =  150, y = 100 },
            boom = { on = true, stat = "biggestMelee",  x = -170, y =  90 },
            zap  = { on = true, stat = "biggestRanged", x =  160, y = -60 },
        }
    end

    if not HardcoreStatTrackerDB.announce then HardcoreStatTrackerDB.announce = {} end
    local an = HardcoreStatTrackerDB.announce
    if an.enabled   == nil then an.enabled   = false end
    if an.guild     == nil then an.guild     = false end
    if an.guildOnly == nil then an.guildOnly = false end
    if an.max       == nil then an.max       = 2 end
    if an.stats   == nil then
        an.stats = { closestCall = true, toughestFoe = true, highestCrit = true, nearestDeath = true }
    end

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
