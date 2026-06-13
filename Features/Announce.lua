local ADDON, HC = ...

local Comma, FmtTime, FmtDiff, FmtShort, FmtSec, FmtPlayed = HC.Comma, HC.FmtTime, HC.FmtDiff, HC.FmtShort, HC.FmtSec, HC.FmtPlayed
-- ---------------------------------------------------------------------------
-- New-record announcements (after combat). Each entry: the HC.db field that holds
-- the record, whether lower is better, a settings label, and a message builder.
-- ---------------------------------------------------------------------------
HC.ANNOUNCE = {
    closestCall  = { field = "lowestPct", lower = true, label = "Closest Call (new low %)",
        msg = function() return ("new closest call - survived at %d%% HP%s!"):format(
            math.floor(HC.db.lowestPct), HC.db.lowestSource and (" vs " .. HC.db.lowestSource) or "") end },
    nearestDeath = { field = "closestSeconds", lower = true, label = "Nearest Death (seconds)",
        msg = function() return ("that was close - only %s from death!"):format(FmtSec(HC.db.closestSeconds)) end },
    biggestHit   = { field = "biggestHit", label = "Biggest Hit Taken",
        msg = function() return ("just took a record hit for %s%s!"):format(Comma(HC.db.biggestHit),
            HC.db.biggestHitSource and (" from " .. HC.db.biggestHitSource) or "") end },
    highestCrit  = { field = "highestCrit", label = "Highest Crit",
        msg = function() return ("new biggest crit - %s%s!"):format(Comma(HC.db.highestCrit),
            HC.db.highestCritSpell and (" (" .. HC.db.highestCritSpell .. ")") or "") end },
    biggestMelee = { field = "biggestMelee", label = "Biggest Melee Hit",
        msg = function() return ("new biggest melee hit: %s!"):format(Comma(HC.db.biggestMelee)) end },
    biggestRanged = { field = "biggestRanged", label = "Biggest Ranged Hit",
        msg = function() return ("new biggest ranged hit: %s!"):format(Comma(HC.db.biggestRanged)) end },
    biggestSpell = { field = "biggestSpell", label = "Biggest Spell Hit",
        msg = function() return ("new biggest spell hit: %s!"):format(Comma(HC.db.biggestSpell)) end },
    biggestHeal  = { field = "biggestHeal", label = "Biggest Heal",
        msg = function() return ("new biggest heal: %s!"):format(Comma(HC.db.biggestHeal)) end },
    playersSaved = { field = "playersSaved", label = "Player Saved",
        msg = function() return "clutch heal - pulled a teammate back from the brink!" end },
    toughestFoe  = { field = "biggestLevelDiff", label = "Toughest Foe",
        msg = function() return ("just took on something %s levels above me%s!"):format(
            FmtDiff(HC.db.biggestLevelDiff), HC.db.biggestLevelDiffMob and (" (" .. HC.db.biggestLevelDiffMob .. ")") or "") end },
    highestFall  = { field = "highestFall", label = "Highest Fall",
        msg = function() return ("survived a record fall for %s damage!"):format(Comma(HC.db.highestFall)) end },
    longestFight = { field = "longestFight", label = "Longest Fight",
        msg = function() return ("new longest fight: %s!"):format(FmtTime(HC.db.longestFight)) end },
    mostDmgFight = { field = "mostDmgFight", label = "Most Dmg in One Fight",
        msg = function() return ("record damage taken in one fight: %s!"):format(Comma(HC.db.mostDmgFight)) end },
    untouched    = { field = "untouched", label = "Untouched Streak",
        msg = function() return ("untouchable - %s in combat without a scratch!"):format(FmtTime(HC.db.untouched)) end },
    mostFoes     = { field = "mostFoes", label = "Most Foes at Once",
        msg = function() return ("fought %d enemies at once and lived!"):format(HC.db.mostFoes) end },
}
-- Priority order when the per-fight cap trims the list (most impressive first).
HC.ANNOUNCE_ORDER = {
    "closestCall", "nearestDeath", "toughestFoe", "biggestHit", "highestCrit",
    "mostFoes", "highestFall", "untouched", "biggestMelee", "biggestRanged",
    "biggestSpell", "playersSaved", "biggestHeal", "longestFight", "mostDmgFight",
}

-- Channel: party (never raid), else /say. Guild is optional: alongside, or only.
-- /say queues to the next keypress via HC.SayMessage (hardware-event rule).
function HC:Announce(msgs)
    local an = HC.db.announce
    local primary   = (IsInGroup() and not IsInRaid()) and "PARTY" or "SAY"
    local toGuild   = an.guild and IsInGuild()
    local guildOnly = toGuild and an.guildOnly
    for _, m in ipairs(msgs) do
        if not guildOnly then HC.SayMessage(m, primary, false) end
        if toGuild then HC.SayMessage(m, "GUILD", false) end
    end
end

-- Compare end-of-fight records to the combat-start snapshot. New bests are
-- queued and sent a few seconds AFTER combat ends - if you chain-pull into
-- another fight, the brag waits until you're genuinely out of combat.
local ANNOUNCE_DELAY = 4
local pendingAnnounce = {}

function HC:FlushAnnounce()
    if #pendingAnnounce == 0 then return end
    if InCombatLockdown() then return end       -- next combat end reschedules us
    if UnitIsDeadOrGhost("player") then          -- no bragging from the grave
        wipe(pendingAnnounce)
        return
    end
    HC:Announce(pendingAnnounce)
    wipe(pendingAnnounce)
end

function HC:CheckAnnounce()
    local an = HC.db.announce
    if not (an and an.enabled) or IsInRaid() or not HC.state.combatSnapshot then return end
    local cap = an.max or 2
    for _, key in ipairs(HC.ANNOUNCE_ORDER) do
        if #pendingAnnounce >= cap then break end
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
                pendingAnnounce[#pendingAnnounce + 1] = def.msg()
            end
        end
    end
end

-- Fire the queued brags a few seconds after combat (kept here so the announce
-- queue stays fully owned by this module).
function HC:ScheduleAnnounceFlush()
    if #pendingAnnounce > 0 then
        C_Timer.After(ANNOUNCE_DELAY, function() HC:FlushAnnounce() end)
    end
end
