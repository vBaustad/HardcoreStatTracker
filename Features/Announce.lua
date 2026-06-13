local ADDON, HC = ...

local Comma, FmtTime, FmtDiff, FmtShort, FmtSec, FmtPlayed = HC.Comma, HC.FmtTime, HC.FmtDiff, HC.FmtShort, HC.FmtSec, HC.FmtPlayed
-- ---------------------------------------------------------------------------
-- New-record announcements (after combat). Each entry: the HC.db field that holds
-- the record, whether lower is better, a settings label, and a message builder.
-- ---------------------------------------------------------------------------
HC.ANNOUNCE = {
    closestCall  = { field = "lowestPct", lower = true, label = "Closest Call (new low %)",
        msg = function()
            local p = math.floor(HC.db.lowestPct)
            if HC.db.lowestSource then return ("survived at %d%% HP vs %s - my closest call yet"):format(p, HC.db.lowestSource) end
            return ("survived at %d%% HP - my closest call yet"):format(p)
        end },
    nearestDeath = { field = "closestSeconds", lower = true, label = "Nearest Death (seconds)",
        msg = function() return ("came within %s of dying"):format(FmtSec(HC.db.closestSeconds)) end },
    biggestHit   = { field = "biggestHit", label = "Biggest Hit Taken",
        msg = function()
            local n = Comma(HC.db.biggestHit)
            if HC.db.biggestHitSource then return ("survived a %s hit from %s"):format(n, HC.db.biggestHitSource) end
            return ("survived a record %s hit"):format(n)
        end },
    highestCrit  = { field = "highestCrit", label = "Highest Crit",
        msg = function()
            local n = Comma(HC.db.highestCrit)
            if HC.db.highestCritSpell then return ("biggest crit yet: %s (%s)"):format(n, HC.db.highestCritSpell) end
            return ("biggest crit yet: %s"):format(n)
        end },
    biggestMelee = { field = "biggestMelee", label = "Biggest Melee Hit",
        msg = function() return ("biggest melee hit yet: %s"):format(Comma(HC.db.biggestMelee)) end },
    biggestRanged = { field = "biggestRanged", label = "Biggest Ranged Hit",
        msg = function() return ("biggest ranged hit yet: %s"):format(Comma(HC.db.biggestRanged)) end },
    biggestSpell = { field = "biggestSpell", label = "Biggest Spell Hit",
        msg = function() return ("biggest spell hit yet: %s"):format(Comma(HC.db.biggestSpell)) end },
    biggestHeal  = { field = "biggestHeal", label = "Biggest Heal",
        msg = function() return ("biggest heal yet: %s"):format(Comma(HC.db.biggestHeal)) end },
    playersSaved = { field = "playersSaved", label = "Player Saved",
        msg = function() return "saved a teammate from near-certain death" end },
    toughestFoe  = { field = "biggestLevelDiff", label = "Toughest Foe",
        msg = function()
            local d = HC.db.biggestLevelDiff
            if HC.db.biggestLevelDiffMob then return ("beat %s, %d levels above me"):format(HC.db.biggestLevelDiffMob, d) end
            return ("beat a foe %d levels above me"):format(d)
        end },
    highestFall  = { field = "highestFallPct", label = "Highest Fall",
        msg = function()
            if HC.db.highestFallPct then return ("survived a fall that took %d%% of my HP"):format(math.floor(HC.db.highestFallPct)) end
            return ("survived a %s-damage fall"):format(Comma(HC.db.highestFall))
        end },

    longestFight = { field = "longestFight", label = "Longest Fight",
        msg = function() return ("longest fight yet: %s"):format(FmtTime(HC.db.longestFight)) end },
    mostDmgFight = { field = "mostDmgFight", label = "Most Dmg in One Fight",
        msg = function() return ("took a record %s in a single fight"):format(Comma(HC.db.mostDmgFight)) end },
    untouched    = { field = "untouched", label = "Untouched Streak",
        msg = function() return ("%s in combat without taking damage"):format(FmtTime(HC.db.untouched)) end },
    mostFoes     = { field = "mostFoes", label = "Most Foes at Once",
        msg = function() return ("survived %d enemies at once"):format(HC.db.mostFoes) end },
}

-- Guild clutch-survival lines, picked at random so it never repeats word-for-word. %d = HP%.
local CLUTCH_LINES = {
    "survived a fight at %d%% HP",
    "made it out of a fight at %d%% HP",
    "down to %d%% HP, but survived the fight",
}
-- Guild clutch hype is intentionally rare and not user-tunable.
local CLUTCH_PCT      = 5    -- only survivals at/under this HP% reach guild
local CLUTCH_COOLDOWN = 300  -- and at most once every 5 minutes
-- Priority order when the per-fight cap trims the list (most impressive first).
HC.ANNOUNCE_ORDER = {
    "closestCall", "nearestDeath", "toughestFoe", "biggestHit", "highestCrit",
    "mostFoes", "highestFall", "untouched", "biggestMelee", "biggestRanged",
    "biggestSpell", "playersSaved", "biggestHeal", "longestFight", "mostDmgFight",
}

-- Two streams, queued at combat end and sent a few seconds LATER (so a chain-pull
-- holds the brag, and a death in the meantime cancels it entirely):
--   * records  -> party (or /say solo), never raid, never guild
--   * clutch   -> guild only: "survived a fight at X% HP", rare by design
-- Each queue entry is { msg = ..., chan = "PARTY"/"SAY"/"GUILD" }.
local ANNOUNCE_DELAY = 4
local pendingAnnounce = {}
local lastGuildBrag   = 0   -- time() of the last guild line, for the cooldown

-- Wipe anything pending (called on death so a "I survived!" line never posts).
function HC:ClearAnnounce()
    wipe(pendingAnnounce)
end

function HC:FlushAnnounce()
    if #pendingAnnounce == 0 then return end
    if InCombatLockdown() then return end       -- next combat end reschedules us
    if UnitIsDeadOrGhost("player") then          -- no bragging from the grave
        wipe(pendingAnnounce)
        return
    end
    local an = HC.db.announce
    for _, e in ipairs(pendingAnnounce) do
        if e.chan == "GUILD" then
            if IsInGuild() and (time() - lastGuildBrag) >= CLUTCH_COOLDOWN then
                HC.SayMessage(e.msg, "GUILD", false)
                lastGuildBrag = time()
            end
        else
            HC.SayMessage(e.msg, e.chan, false)
        end
    end
    wipe(pendingAnnounce)
end

-- Records stream: new all-time bests this fight -> your group (party/say).
function HC:CheckAnnounce()
    local an = HC.db.announce
    if not (an and an.enabled and an.records) or IsInRaid() or not HC.state.combatSnapshot then return end
    local primary = (IsInGroup() and not IsInRaid()) and "PARTY" or "SAY"
    local cap, count = an.max or 2, 0
    for _, key in ipairs(HC.ANNOUNCE_ORDER) do
        if count >= cap then break end
        if an.stats[key] then
            local def = HC.ANNOUNCE[key]
            local cur, old = HC.db[def.field], HC.state.combatSnapshot[def.field]
            local improved
            if def.lower then
                improved = cur ~= nil and (old == nil or cur < old)
            else
                improved = (cur or 0) > (old or 0)
            end
            if key == "toughestFoe" and (HC.db.biggestLevelDiff or 0) <= 0 then improved = false end
            if improved then
                pendingAnnounce[#pendingAnnounce + 1] = { msg = def.msg(), chan = primary }
                count = count + 1
            end
        end
    end
end

-- Clutch stream: survived a real fight at/under the threshold -> guild hype.
-- The actual cooldown + IsInGuild check happen at send time (FlushAnnounce).
function HC:QueueClutch(lowPct)
    local an = HC.db.announce
    if not (an and an.enabled and an.clutch) then return end
    if IsInRaid() or not IsInGuild() then return end
    if not lowPct or lowPct > CLUTCH_PCT then return end
    local tmpl = CLUTCH_LINES[math.random(#CLUTCH_LINES)]
    pendingAnnounce[#pendingAnnounce + 1] = {
        msg  = tmpl:format(math.max(1, math.floor(lowPct))),
        chan = "GUILD",
    }
end

-- Fire the queued brags a few seconds after combat (kept here so the announce
-- queue stays fully owned by this module).
function HC:ScheduleAnnounceFlush()
    if #pendingAnnounce > 0 then
        C_Timer.After(ANNOUNCE_DELAY, function() HC:FlushAnnounce() end)
    end
end
