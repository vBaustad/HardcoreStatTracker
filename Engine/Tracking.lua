local ADDON, HC = ...

local Comma, FmtTime, FmtDiff, FmtShort, FmtSec, FmtPlayed = HC.Comma, HC.FmtTime, HC.FmtDiff, HC.FmtShort, HC.FmtSec, HC.FmtPlayed
local PANIC_THRESHOLD = HC.PANIC_THRESHOLD

-- transient (not saved) live-combat state
HC.state.inCombat     = false
HC.state.combatStart  = 0
HC.state.curFightDmg  = 0
local wasBelow     = false
local lastHitBy    = nil   -- most recent thing that damaged the player
local lwSayArmed   = false -- chat "last words" re-arm flag
local lwSayFire    = -999
local lwAlertArmed = false -- screen/sound alert re-arm flag
local lwAlertFire  = -999

-- per-fight trackers (reset each combat)
local fightAttackers = {}  -- set of enemy GUIDs that hit you this fight
local fightFoeCount  = 0
local fightWentLow   = false
local untouchedStart = nil -- GetTime() of last hit taken (or combat start)
HC.state.combatSnapshot = nil -- record values at combat start, for new-record announces
local CLUTCH_THRESHOLD = 10 -- % HP that makes surviving a fight a "clutch save"
-- pet tracking: petGUID is the last *living* pet, kept so a UNIT_DIED line can
-- be matched even though UNIT_PET may fire in the same instant.
local petGUID = nil
local petName = nil
function HC.UpdatePet()
    if UnitExists("pet") and UnitGUID("pet") then
        petGUID = UnitGUID("pet")
        petName = UnitName("pet")
    end
    if HC.UpdateDisplay then HC:UpdateDisplay() end
end

-- Map of current groupmates' GUIDs -> names, so a UNIT_DIED can be attributed.
local partyGUIDs = {}
function HC.RefreshGroup()
    wipe(partyGUIDs)
    if not IsInGroup() then return end
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, 40 do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local g = UnitGUID(unit)
            if g then partyGUIDs[g] = UnitName(unit) end
        end
    end
end

-- Best-effort Mak'gora win/loss detection from the system message. The exact
-- wording isn't documented here, so this matches loosely and there's a manual
-- fallback (/hst makgora won|lost) plus a capture mode (/hst makgora debug).
function HC.OnSystemMsg(msg)
    if not HC.adb or not msg then return end
    local l = msg:lower()
    if not l:find("gora") then return end  -- mak'gora / makgora
    if HC.adb.makgoraDebug then
        print("|cffff4444Hardcore Stat Tracker|r |cff888888[makgora]|r " .. msg)
    end
    local me = (UnitName("player") or ""):lower()
    local lost = l:find("you have lost") or l:find("you were defeated") or l:find("you have fallen")
        or l:find("defeated " .. me) or l:find("slain " .. me)
    local won  = not lost and (l:find("you have won") or l:find("you won")
        or l:find("you are victorious") or (l:find(me .. " has won")))
    if won then
        HC.adb.makgoraWon = HC.adb.makgoraWon + 1
        print("|cffff4444Hardcore Stat Tracker|r: Mak'gora win recorded! (" .. HC.adb.makgoraWon .. " total)")
        HC:UpdateDisplay()
    elseif lost then
        HC.adb.makgoraLost = HC.adb.makgoraLost + 1
        print("|cffff4444Hardcore Stat Tracker|r: Mak'gora loss recorded. (" .. HC.adb.makgoraLost .. " total)")
        HC:UpdateDisplay()
    end
end

-- Count a zone the first time it's entered.
function HC.VisitZone()
    if not HC.db then return end
    local z = GetRealZoneText() or GetZoneText()
    if z and z ~= "" and not HC.db.zonesVisited[z] then
        HC.db.zonesVisited[z] = true
        HC.db.zones = (HC.db.zones or 0) + 1
        HC:UpdateDisplay()
    end
end

-- /played tracking: authoritative snapshot + live session offset
HC.state.playedBase      = nil  -- total played seconds at last server snapshot
HC.state.playedLevelBase = nil  -- played-this-level seconds at last snapshot
HC.state.playedBaseTime  = nil  -- GetTime() when that snapshot was taken

function HC.LiveAlive()
    if HC.state.playedBase then return HC.state.playedBase + (GetTime() - HC.state.playedBaseTime) end
    return HC.db and HC.db.playedTotal or nil
end
function HC.LiveLevelTime()
    if HC.state.playedLevelBase then return HC.state.playedLevelBase + (GetTime() - HC.state.playedBaseTime) end
    return nil
end

-- rolling window of incoming damage, for "time to death" estimates
local dmgEvents  = {}
local DMG_WINDOW = 3       -- seconds
local function PushIncoming(amount)
    dmgEvents[#dmgEvents + 1] = { t = GetTime(), amt = amount }
end
local function RecentDPS()
    local now, sum, i = GetTime(), 0, 1
    while i <= #dmgEvents do
        local ev = dmgEvents[i]
        if now - ev.t > DMG_WINDOW then
            table.remove(dmgEvents, i)
        else
            sum = sum + ev.amt
            i = i + 1
        end
    end
    return sum / DMG_WINDOW
end
function HC.OnHealth()
    local hp  = UnitHealth("player")
    local max = UnitHealthMax("player")
    if not max or max == 0 or hp <= 0 then return end
    local pct = hp / max * 100

    if not HC.db.lowestPct or pct < HC.db.lowestPct then
        HC.db.lowestPct    = pct
        HC.db.lowestHP     = hp
        HC.db.lowestMax    = max
        HC.db.lowestLevel  = UnitLevel("player")
        HC.db.lowestZone   = GetZoneText()
        HC.db.lowestSource = lastHitBy or (HC.state.inCombat and (UnitName("target")) or nil)
        HC:ComicEvent("closestCall")
        HC:UpdateDisplay()
    end

    -- Time-to-death: current HP divided by recent incoming damage rate.
    local dps = RecentDPS()
    if dps > 0 then
        local ttd = hp / dps
        if not HC.db.closestSeconds or ttd < HC.db.closestSeconds then
            HC.db.closestSeconds   = ttd
            HC.db.closestSecHP     = hp
            HC.db.closestSecLevel  = UnitLevel("player")
            HC.db.closestSecZone   = GetZoneText()
            HC.db.closestSecSource = lastHitBy
            HC:ComicEvent("nearestDeath")
            HC:UpdateDisplay()
        end
    end

    if pct <= PANIC_THRESHOLD then
        if not wasBelow then
            wasBelow = true
            HC.db.panicMoments = HC.db.panicMoments + 1
            HC:UpdateDisplay()
        end
    else
        wasBelow = false
    end

    -- Mark this fight as a "clutch" if you dipped below the clutch threshold.
    if HC.state.inCombat and pct <= CLUTCH_THRESHOLD then fightWentLow = true end

    -- Famous last words (chat) and the attention alert fire on independent
    -- thresholds. Each: once per dip, re-arm above threshold +5, short cooldown.
    local lw = HC.db.lastWords
    if lw and lw.enabled then
        if lw.say then
            local th = lw.sayThreshold or 15
            if pct <= th and not lwSayArmed then
                lwSayArmed = true
                if GetTime() - lwSayFire > 10 then
                    lwSayFire = GetTime()
                    local msg = HC:RandomLastWord()
                    if msg then HC.SayMessage(msg, lw.channel or "SAY", false) end
                end
            elseif pct > th + 5 then
                lwSayArmed = false
            end
        end
        if lw.alertSelf then
            local th = lw.alertThreshold or 30
            if pct <= th and not lwAlertArmed then
                lwAlertArmed = true
                if GetTime() - lwAlertFire > 5 then
                    lwAlertFire = GetTime()
                    HC:DangerAlert()
                end
            elseif pct > th + 5 then
                lwAlertArmed = false
            end
        end
    end
end

-- When a damaged enemy is your current target, record how far above you it is.
local function SampleTargetLevel(enemyGUID, enemyName)
    if not enemyGUID then return false end
    if not (UnitExists("target") and UnitGUID("target") == enemyGUID
            and UnitCanAttack("player", "target")) then
        return false
    end
    local lvl = UnitLevel("target")
    if not lvl or lvl <= 0 then return false end -- -1 = ?? (unknowable)
    local diff = lvl - UnitLevel("player")
    if not HC.db.biggestLevelDiff or diff > HC.db.biggestLevelDiff then
        HC.db.biggestLevelDiff        = diff
        HC.db.biggestLevelDiffMob     = enemyName or UnitName("target")
        HC.db.biggestLevelDiffMyLevel = UnitLevel("player")
        HC.db.biggestLevelDiffZone    = GetZoneText()
        return true
    end
    return false
end

-- Append to a death log, keeping it bounded (only the recent tail is shown).
local LOG_CAP = 25
local function PushLog(log, entry)
    log[#log + 1] = entry
    while #log > LOG_CAP do table.remove(log, 1) end
end

function HC.OnCombatLog()
    if not HC.db then return end  -- events can fire before PLAYER_LOGIN initializes us

    -- Capture the header as plain locals: CLEU fires for everything in combat-log
    -- range, so this hot path must not allocate (no table per event).
    local _, sub, _, srcGUID, srcName, srcFlags, _, dstGUID, dstName, dstFlags =
        CombatLogGetCurrentEventInfo()

    if sub == "PARTY_KILL" then
        if srcGUID == HC.state.playerGUID then
            HC.db.killingBlows = HC.db.killingBlows + 1
            HC:UpdateDisplay()
        end
        return
    end

    if sub == "UNIT_DIED" then
        if petGUID and dstGUID == petGUID then
            HC.db.petDeaths = HC.db.petDeaths + 1
            PushLog(HC.db.petDeathLog, {
                name = petName or dstName or "Pet",
                level = UnitLevel("player"), zone = GetZoneText(),
            })
            petGUID = nil
            HC:UpdateDisplay()
        elseif partyGUIDs[dstGUID] then
            HC.db.partyDeaths = (HC.db.partyDeaths or 0) + 1
            PushLog(HC.db.partyDeathLog, {
                name = partyGUIDs[dstGUID] or dstName or "?",
                level = UnitLevel("player"), zone = GetZoneText(),
            })
            partyGUIDs[dstGUID] = nil   -- don't recount; re-added on next roster update
            HC:UpdateDisplay()
        end
        return
    end

    if sub == "ENVIRONMENTAL_DAMAGE" then
        if dstGUID ~= HC.state.playerGUID then return end
        local envType, amt = select(12, CombatLogGetCurrentEventInfo())  -- envType(12), amount(13)
        if amt and amt > 0 then
            PushIncoming(amt)
            HC.db.dmgTaken = (HC.db.dmgTaken or 0) + amt
            lastHitBy = envType
            if envType == "Falling" and (not HC.db.highestFall or amt > HC.db.highestFall) then
                HC.db.highestFall      = amt
                HC.db.highestFallLevel = UnitLevel("player")
                HC.db.highestFallZone  = GetZoneText()
                HC:ComicEvent("highestFall")
                HC:UpdateDisplay()
            end
        end
        return
    end

    -- Only events involving the player matter past this point.
    if srcGUID ~= HC.state.playerGUID and dstGUID ~= HC.state.playerGUID then return end

    -- Buffs you put on OTHER players (Fortitude, Battle Shout hitting the
    -- party, etc.). One count per application per target.
    if sub == "SPELL_AURA_APPLIED" then
        if srcGUID == HC.state.playerGUID and dstGUID ~= HC.state.playerGUID and dstFlags
                and bit.band(dstFlags, COMBATLOG_OBJECT_TYPE_PLAYER or 0x400) > 0 then
            local _, _, _, auraType = select(12, CombatLogGetCurrentEventInfo())  -- auraType(15)
            if auraType == "BUFF" then
                HC.db.buffsGiven = (HC.db.buffsGiven or 0) + 1
                HC:UpdateDisplay()
            end
        end
        return
    end

    -- Field offsets differ between swing and spell/range damage events.
    local amount, critical, spellName
    if sub == "SWING_DAMAGE" then
        -- amount(12) ... critical(18)
        local a, _, _, _, _, _, crit = select(12, CombatLogGetCurrentEventInfo())
        amount, critical, spellName = a, crit, "Melee"
    elseif sub == "SPELL_DAMAGE" or sub == "RANGE_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" then
        -- spellName(13), amount(15) ... critical(21)
        local sName, _, a, _, _, _, _, _, crit = select(13, CombatLogGetCurrentEventInfo())
        amount, critical, spellName = a, crit, sName
    else
        return
    end
    if not amount or amount <= 0 then return end

    local changed = false

    if srcGUID == HC.state.playerGUID and critical and amount > HC.db.highestCrit then
        HC.db.highestCrit       = amount
        HC.db.highestCritSpell  = spellName
        HC.db.highestCritTarget = dstName
        changed = true
        HC:ComicEvent("highestCrit")
    end

    -- Weapon auto-attacks: SWING = melee weapon, RANGE = ranged weapon.
    if srcGUID == HC.state.playerGUID then
        if sub == "SWING_DAMAGE" and amount > HC.db.biggestMelee then
            HC.db.biggestMelee, HC.db.biggestMeleeTarget = amount, dstName
            changed = true
            HC:ComicEvent("biggestMelee")
        elseif sub == "RANGE_DAMAGE" and amount > HC.db.biggestRanged then
            HC.db.biggestRanged, HC.db.biggestRangedTarget = amount, dstName
            changed = true
            HC:ComicEvent("biggestRanged")
        end
    end

    if dstGUID == HC.state.playerGUID then
        lastHitBy   = srcName
        HC.state.curFightDmg = HC.state.curFightDmg + amount
        PushIncoming(amount)
        HC.db.dmgTaken = (HC.db.dmgTaken or 0) + amount

        -- Per-mob damage history (NPC sources only), keyed by name. Account-wide,
        -- so a new character inherits the "this thing hurt me before" warnings.
        if srcName and srcFlags and HC.adb
                and bit.band(srcFlags, COMBATLOG_OBJECT_TYPE_NPC or 0x800) > 0 then
            local rec = HC.adb.mobDamage[srcName]
            if not rec then rec = { hit = 0, crit = 0, count = 0 }; HC.adb.mobDamage[srcName] = rec end
            rec.count = rec.count + 1
            rec.seen  = time()
            if amount > rec.hit then
                rec.hit = amount
                rec.atLevel = UnitLevel("player")  -- context: what level took this hit
            end
            if critical and amount > rec.crit then rec.crit = amount end
            -- Note the mob's level when it happens to be our target.
            if UnitExists("target") and UnitGUID("target") == srcGUID then
                local l = UnitLevel("target")
                if l and l > 0 then rec.lvl = l end
            end
        end

        if srcGUID and not fightAttackers[srcGUID] then
            fightAttackers[srcGUID] = true
            fightFoeCount = fightFoeCount + 1
            if fightFoeCount > HC.db.mostFoes then
                HC.db.mostFoes = fightFoeCount
                HC:ComicEvent("mostFoes")
            end
        end
        if HC.state.inCombat and untouchedStart then  -- a hit ends the current no-hit streak
            local stretch = GetTime() - untouchedStart
            if stretch > HC.db.untouched then
                HC.db.untouched = stretch
                HC:StampRecord("untouched")
            end
            untouchedStart = GetTime()
        end

        if amount > HC.db.biggestHit then
            HC.db.biggestHit       = amount
            HC.db.biggestHitSource = srcName
            HC.db.biggestHitSpell  = spellName
            HC.db.biggestHitLevel  = UnitLevel("player")
            HC.db.biggestHitZone   = GetZoneText()
            changed = true
            HC:ComicEvent("biggestHit")
        end
    end

    -- Toughest foe: sample the level of whichever side isn't the player.
    local enemyGUID, enemyName
    if srcGUID == HC.state.playerGUID then
        enemyGUID, enemyName = dstGUID, dstName
    elseif dstGUID == HC.state.playerGUID then
        enemyGUID, enemyName = srcGUID, srcName
    end
    if SampleTargetLevel(enemyGUID, enemyName) then
        changed = true
        HC:ComicEvent("toughestFoe")
    end

    if changed then HC:UpdateDisplay() end
end

function HC.OnCombatStart()
    HC.state.inCombat    = true
    HC.state.combatStart = GetTime()
    HC.state.curFightDmg = 0
    wipe(fightAttackers)
    fightFoeCount  = 0
    fightWentLow   = false
    untouchedStart = GetTime()
    -- Snapshot record fields so combat end can detect new bests set this fight.
    HC.state.combatSnapshot = {}
    for _, def in pairs(HC.ANNOUNCE) do HC.state.combatSnapshot[def.field] = HC.db[def.field] end
    HC:UpdateDisplay()
end

function HC.OnCombatEnd()
    if HC.state.inCombat then
        local dur = GetTime() - HC.state.combatStart
        HC.db.fights = HC.db.fights + 1
        if dur > HC.db.longestFight then
            HC.db.longestFight     = dur
            HC.db.longestFightZone = GetZoneText()
            HC:StampRecord("longestFight")
        end
        if HC.state.curFightDmg > HC.db.mostDmgFight then
            HC.db.mostDmgFight     = HC.state.curFightDmg
            HC.db.mostDmgFightZone = GetZoneText()
            HC:StampRecord("mostDmgFight")
        end
        -- Untouched streak: the final stretch from last hit to combat end.
        if untouchedStart then
            local stretch = GetTime() - untouchedStart
            if stretch > HC.db.untouched then
                HC.db.untouched = stretch
                HC:StampRecord("untouched")
            end
        end
        -- Clutch save: dropped low but lived through the fight.
        if fightWentLow and (UnitHealth("player") or 0) > 0 then
            HC.db.clutchSaves = HC.db.clutchSaves + 1
            HC:ComicEvent("clutchSaves")
        end
        if (UnitHealth("player") or 0) > 0 then HC:CheckAnnounce() end  -- only if you lived
    end
    untouchedStart = nil
    fightWentLow   = false
    HC.state.inCombat = false
    -- Queued brags (this fight's, or held over from a chain-pull) go out after
    -- a short breather - and only if we're still out of combat by then.
    HC:ScheduleAnnounceFlush()
    HC:UpdateDisplay()
end
