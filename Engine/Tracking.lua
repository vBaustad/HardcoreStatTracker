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
local fightAttackers = {}  -- set of enemy GUIDs currently alive that have hit you this fight
local liveFoes       = 0   -- count of those still alive (for "Most Foes at Once")
local fightWentLow   = false
local fightLowPct    = 100   -- lowest HP% reached this fight (for guild "clutch survival")
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
-- "Players saved" tracking: when a groupmate drops critically low, remember the
-- moment; a direct heal you land on them shortly after counts as a save.
local lowSince    = {}   -- [partyGUID] = GetTime() they dropped low
local SAVE_LOW    = 20   -- % HP that marks a groupmate as in danger
local SAVE_SAFE   = 50   -- % HP that re-arms them for a future save
local SAVE_WINDOW = 6    -- seconds a heal still counts as a save after they dipped
function HC.RefreshGroup()
    wipe(partyGUIDs)
    wipe(lowSince)
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

-- Watch a groupmate's health (party/raid UNIT_HEALTH) to arm/disarm "saves".
function HC.OnPartyHealth(unit)
    if not HC.db then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    local hp, max = UnitHealth(unit), UnitHealthMax(unit)
    if not max or max == 0 then return end
    local pct = hp / max * 100
    if hp > 0 and pct <= SAVE_LOW then
        lowSince[guid] = GetTime()
    elseif pct >= SAVE_SAFE then
        lowSince[guid] = nil
    end
end

-- Gold: lifetime income (every positive money change), and coin from loot only.
local lastMoney   -- session baseline (not saved); set on login
function HC.OnMoney()
    if not HC.db then return end
    local m = GetMoney()
    if lastMoney then
        if m > lastMoney then
            HC.db.goldEarned = (HC.db.goldEarned or 0) + (m - lastMoney)
            HC:UpdateDisplay()
        elseif m < lastMoney then
            HC.db.goldSpent = (HC.db.goldSpent or 0) + (lastMoney - m)
            HC:UpdateDisplay()
        end
    end
    lastMoney = m
end
function HC.OnLootMoney(msg)
    if not HC.db or not msg then return end   -- enUS loot strings: "You loot 1 Gold 2 Silver 3 Copper"
    local g = tonumber(msg:match("(%d+) Gold")) or 0
    local s = tonumber(msg:match("(%d+) Silver")) or 0
    local c = tonumber(msg:match("(%d+) Copper")) or 0
    local total = g * 10000 + s * 100 + c
    if total > 0 then
        HC.db.goldLooted = (HC.db.goldLooted or 0) + total
        HC:UpdateDisplay()
    end
end

-- Bags looted: count containers (bags, quivers, pouches) you actually loot off
-- corpses/chests - never vendor purchases, which don't fire a loot line. enUS
-- loot text: "You receive loot: [Item].' / '...[Item]xN.'.
function HC.OnLoot(msg)
    if not HC.db or not msg then return end
    local link, count = msg:match("You receive loot: (|c.-|r)x?(%d*)")
    if not link then return end
    -- LE_ITEM_CLASS_CONTAINER == 1; classID is the 6th return of GetItemInfoInstant.
    local classID = select(6, GetItemInfoInstant(link))
    if classID == 1 then
        HC.db.bagsLooted = (HC.db.bagsLooted or 0) + (tonumber(count) or 1)
        HC:UpdateDisplay()
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
-- Rolling window of incoming hits, as a fixed-capacity ring buffer of parallel
-- arrays - no per-hit table allocation and no shifting (this is a CLEU hot path).
local DMG_WINDOW = 3       -- seconds
local DMG_CAP    = 200     -- far more hits than one player can take in 3s
local dmgT, dmgA = {}, {}  -- timestamps / amounts, indexed 1..DMG_CAP (ring)
local dmgNext, dmgCount = 1, 0
local function PushIncoming(amount)
    dmgT[dmgNext] = GetTime()
    dmgA[dmgNext] = amount
    dmgNext = dmgNext % DMG_CAP + 1
    if dmgCount < DMG_CAP then dmgCount = dmgCount + 1 end
end
local function RecentDPS()
    local now, sum = GetTime(), 0
    for i = 1, dmgCount do
        if now - dmgT[i] <= DMG_WINDOW then sum = sum + dmgA[i] end
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
    if HC.state.inCombat then
        if pct <= CLUTCH_THRESHOLD then fightWentLow = true end
        if pct < fightLowPct then fightLowPct = pct end
    end

    -- Two independent low-health reactions, each: once per dip, re-arm above
    -- threshold +5, short cooldown.
    local lw = HC.db.lastWords
    if lw then
        -- Famous Last Words: cocky chat line (needs the FLW master + chat on).
        if lw.enabled and lw.say then
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
        -- Low-Health Alert: screen flash + sound, on its own switch.
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
        elseif petGUID and srcGUID == petGUID then
            HC.db.petKillingBlows = (HC.db.petKillingBlows or 0) + 1
            HC:UpdateDisplay()
        end
        return
    end

    if sub == "UNIT_DIED" then
        if fightAttackers[dstGUID] then        -- one of your attackers died: it's no longer "at once"
            fightAttackers[dstGUID] = nil
            liveFoes = liveFoes > 0 and liveFoes - 1 or 0
        end
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
            if envType == "Falling" then
                -- Rank by share of max HP - a 230 fall means very different things
                -- at 300 HP vs 5000 HP. Keep the raw amount as detail.
                local maxhp = UnitHealthMax("player") or 0
                local pct = maxhp > 0 and (amt / maxhp * 100) or 0
                if pct > (HC.db.highestFallPct or 0) then
                    HC.db.highestFallPct   = pct
                    HC.db.highestFall      = amt
                    HC.db.highestFallLevel = UnitLevel("player")
                    HC.db.highestFallZone  = GetZoneText()
                    HC:ComicEvent("highestFall")
                    HC:UpdateDisplay()
                end
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

    -- Healing you do: biggest heal, lifetime effective healing, and clutch "saves".
    if sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
        if srcGUID ~= HC.state.playerGUID then return end
        -- spellName(13), amount(15), overhealing(16)
        local healSpell, _, healAmt, overheal = select(13, CombatLogGetCurrentEventInfo())
        local eff = (healAmt or 0) - (overheal or 0)
        local changedHeal = false
        if eff > 0 then HC.db.healingDone = (HC.db.healingDone or 0) + eff; changedHeal = true end
        local direct = (sub == "SPELL_HEAL")
        if direct and (healAmt or 0) > HC.db.biggestHeal then
            HC.db.biggestHeal       = healAmt
            HC.db.biggestHealSpell  = healSpell
            HC.db.biggestHealTarget = dstName
            changedHeal = true
            HC:ComicEvent("biggestHeal")
        end
        -- A "save": a direct heal on a party member who was critically low.
        if direct and eff > 0 and dstGUID ~= HC.state.playerGUID and partyGUIDs[dstGUID]
                and lowSince[dstGUID] and (GetTime() - lowSince[dstGUID] < SAVE_WINDOW) then
            HC.db.playersSaved = (HC.db.playersSaved or 0) + 1
            PushLog(HC.db.playerSavedLog, {
                name = partyGUIDs[dstGUID] or dstName or "?",
                level = UnitLevel("player"), zone = GetZoneText(),
            })
            lowSince[dstGUID] = nil   -- count once per close call (re-arms when they recover)
            changedHeal = true
            HC:ComicEvent("playersSaved")
        end
        if changedHeal then HC:UpdateDisplay() end
        return
    end

    -- Field offsets differ between swing and spell/range damage events.
    local amount, critical, spellName, spellSchool
    if sub == "SWING_DAMAGE" then
        -- amount(12) ... critical(18)
        local a, _, _, _, _, _, crit = select(12, CombatLogGetCurrentEventInfo())
        amount, critical, spellName = a, crit, "Melee"
    elseif sub == "SPELL_DAMAGE" or sub == "RANGE_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" then
        -- spellName(13), spellSchool(14), amount(15) ... critical(21)
        local sName, sSchool, a, _, _, _, _, _, crit = select(13, CombatLogGetCurrentEventInfo())
        amount, critical, spellName, spellSchool = a, crit, sName, sSchool
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

    -- "Random art on crit" splash mode fires on EVERY crit (not just records).
    if srcGUID == HC.state.playerGUID and critical and HC.RandomCritSplash then
        HC:RandomCritSplash()
    end

    -- Biggest-hit records track NON-crit hits only; crits go to Highest Crit
    -- above, so the two never overlap. SWING = melee weapon, RANGE = ranged weapon.
    if srcGUID == HC.state.playerGUID and not critical then
        if sub == "SWING_DAMAGE" and amount > HC.db.biggestMelee then
            HC.db.biggestMelee, HC.db.biggestMeleeTarget = amount, dstName
            changed = true
            HC:ComicEvent("biggestMelee")
        elseif sub == "RANGE_DAMAGE" and amount > HC.db.biggestRanged then
            HC.db.biggestRanged, HC.db.biggestRangedTarget = amount, dstName
            changed = true
            HC:ComicEvent("biggestRanged")
        elseif sub == "SPELL_DAMAGE" then
            -- Physical-school "spells" are yellow abilities (Sinister Strike, Raptor
            -- Strike, Aimed Shot...); any other school is a real magic spell.
            if spellSchool == 1 then
                if amount > HC.db.biggestAbility then
                    HC.db.biggestAbility, HC.db.biggestAbilityName, HC.db.biggestAbilityTarget = amount, spellName, dstName
                    changed = true
                    HC:ComicEvent("biggestAbility")
                end
            elseif amount > HC.db.biggestSpell then
                HC.db.biggestSpell, HC.db.biggestSpellName, HC.db.biggestSpellTarget = amount, spellName, dstName
                changed = true
                HC:ComicEvent("biggestSpell")
            end
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
            liveFoes = liveFoes + 1   -- a foe dying decrements this (see UNIT_DIED)
            if liveFoes > HC.db.mostFoes then
                HC.db.mostFoes = liveFoes
                HC:ComicEvent("mostFoes")
            end
        end
        if HC.state.inCombat and untouchedStart then  -- a hit ends the current no-hit streak
            local stretch = GetTime() - untouchedStart
            if stretch > HC.db.untouched then
                HC.db.untouched = stretch
                HC:ComicEvent("untouched")
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
    -- Safety: never leave the mouse-grabbing splash placement frames up in a fight.
    if HC.SetSplashPlacement then HC:SetSplashPlacement(false) end
    HC.state.inCombat    = true
    HC.state.combatStart = GetTime()
    HC.state.curFightDmg = 0
    wipe(fightAttackers)
    liveFoes       = 0
    fightWentLow   = false
    fightLowPct    = 100
    untouchedStart = GetTime()
    -- Snapshot record fields so combat end can detect new bests set this fight.
    HC.state.combatSnapshot = {}
    for _, def in pairs(HC.ANNOUNCE) do HC.state.combatSnapshot[def.field] = HC.db[def.field] end
    HC:UpdateDisplay()
end

function HC.OnCombatEnd()
    if HC.state.inCombat then
        local alive = (UnitHealth("player") or 0) > 0
        local dur = GetTime() - HC.state.combatStart
        if alive then HC.db.fights = HC.db.fights + 1 end  -- "Fights Survived": not the one you died in
        if dur > HC.db.longestFight then
            HC.db.longestFight     = dur
            HC.db.longestFightZone = GetZoneText()
            HC:ComicEvent("longestFight")
        end
        if HC.state.curFightDmg > HC.db.mostDmgFight then
            HC.db.mostDmgFight     = HC.state.curFightDmg
            HC.db.mostDmgFightZone = GetZoneText()
            HC:ComicEvent("mostDmgFight")
        end
        -- Untouched streak: the final stretch from last hit to combat end.
        if untouchedStart then
            local stretch = GetTime() - untouchedStart
            if stretch > HC.db.untouched then
                HC.db.untouched = stretch
                HC:ComicEvent("untouched")
            end
        end
        -- Clutch save: dropped low but lived through the fight.
        if fightWentLow and alive then
            HC.db.clutchSaves = HC.db.clutchSaves + 1
            HC:ComicEvent("clutchSaves")
        end
        if alive then
            HC:CheckAnnounce()
            -- Clutch survival -> guild, only for a real fight you nearly lost.
            if HC.state.curFightDmg > 0 then HC:QueueClutch(fightLowPct) end
        end
    end
    untouchedStart = nil
    fightWentLow   = false
    HC.state.inCombat = false
    -- Queued brags (this fight's, or held over from a chain-pull) go out after
    -- a short breather - and only if we're still out of combat by then.
    HC:ScheduleAnnounceFlush()
    HC:UpdateDisplay()
end
