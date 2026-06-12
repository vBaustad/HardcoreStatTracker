-- HCStats: a lightweight Hardcore "trophy case" of close calls and big numbers.
-- Per-character saved variables; everything is event-driven and cheap.
local ADDON, HC = ...    -- HC is the addon's shared table (used by Options.lua too)

local DB                 -- alias to HCStatsDB (set on login)
local playerGUID

-- Suppress the "Total time played" chat spam, but only for requests we make.
local awaitingPlayedMsg = false
if ChatFrame_DisplayTimePlayed then
    local orig = ChatFrame_DisplayTimePlayed
    ChatFrame_DisplayTimePlayed = function(...)
        if awaitingPlayedMsg then awaitingPlayedMsg = false; return end
        return orig(...)
    end
end

-- transient (not saved) live-combat state
local inCombat     = false
local combatStart  = 0
local curFightDmg  = 0
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
local combatSnapshot = nil -- record values at combat start, for new-record announces
local CLUTCH_THRESHOLD = 10 -- % HP that makes surviving a fight a "clutch save"

-- Built-in "famous last words" - cocky, ironic things a player casually types
-- to their party right before it all goes wrong. Kept hidden in-game for the
-- karmic surprise factor.
local DEFAULT_LASTWORDS = {
    "yeah this is easy",
    "pfft i got this",
    "watch this",
    "they barely even hit me",
    "i don't need to heal yet",
    "totally safe zone, relax",
    "let me just pull a few more",
    "no need to rest, keep going",
    "trust me i do this all the time",
    "who needs a healer anyway",
    "what's the worst that could happen",
    "one more pull then i'll be careful",
    "imagine dying to this lol",
    "these mobs are basically gray to me",
    "i never even use my potions",
    "hardcore is easy if you're not bad",
    "i'll tank it, go go go",
    "almost dinged, one more",
    "should probably go to bed after this",
    "ok last pull then i'm logging",
    "it's not even that late",
}

-- pet tracking: petGUID is the last *living* pet, kept so a UNIT_DIED line can
-- be matched even though UNIT_PET may fire in the same instant.
local petGUID = nil
local petName = nil
local function UpdatePet()
    if UnitExists("pet") and UnitGUID("pet") then
        petGUID = UnitGUID("pet")
        petName = UnitName("pet")
    end
    if HC.UpdateDisplay then HC:UpdateDisplay() end
end

-- Map of current groupmates' GUIDs -> names, so a UNIT_DIED can be attributed.
local partyGUIDs = {}
local function RefreshGroup()
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
-- fallback (/hcstats makgora won|lost) plus a capture mode (/hcstats makgora debug).
local function OnSystemMsg(msg)
    if not HC.adb or not msg then return end
    local l = msg:lower()
    if not l:find("gora") then return end  -- mak'gora / makgora
    if HC.adb.makgoraDebug then
        print("|cffff4444HC Stats|r |cff888888[makgora]|r " .. msg)
    end
    local me = (UnitName("player") or ""):lower()
    local lost = l:find("you have lost") or l:find("you were defeated") or l:find("you have fallen")
        or l:find("defeated " .. me) or l:find("slain " .. me)
    local won  = not lost and (l:find("you have won") or l:find("you won")
        or l:find("you are victorious") or (l:find(me .. " has won")))
    if won then
        HC.adb.makgoraWon = HC.adb.makgoraWon + 1
        print("|cffff4444HC Stats|r: Mak'gora win recorded! (" .. HC.adb.makgoraWon .. " total)")
        HC:UpdateDisplay()
    elseif lost then
        HC.adb.makgoraLost = HC.adb.makgoraLost + 1
        print("|cffff4444HC Stats|r: Mak'gora loss recorded. (" .. HC.adb.makgoraLost .. " total)")
        HC:UpdateDisplay()
    end
end

-- Count a zone the first time it's entered.
local function VisitZone()
    if not DB then return end
    local z = GetRealZoneText() or GetZoneText()
    if z and z ~= "" and not DB.zonesVisited[z] then
        DB.zonesVisited[z] = true
        DB.zones = (DB.zones or 0) + 1
        HC:UpdateDisplay()
    end
end

-- /played tracking: authoritative snapshot + live session offset
local playedBase      = nil  -- total played seconds at last server snapshot
local playedLevelBase = nil  -- played-this-level seconds at last snapshot
local playedBaseTime  = nil  -- GetTime() when that snapshot was taken

local function LiveAlive()
    if playedBase then return playedBase + (GetTime() - playedBaseTime) end
    return DB and DB.playedTotal or nil
end
local function LiveLevelTime()
    if playedLevelBase then return playedLevelBase + (GetTime() - playedBaseTime) end
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
    point      = { "CENTER", "CENTER", 250, 0 },
}

local PANIC_THRESHOLD = 20  -- % HP that counts as a "panic moment"

local function ApplyDefaults()
    HCStatsDB = HCStatsDB or {}
    for k, v in pairs(RECORD_DEFAULTS) do
        if HCStatsDB[k] == nil then HCStatsDB[k] = v end
    end
    for k, v in pairs(LAYOUT_DEFAULTS) do
        if HCStatsDB[k] == nil then
            HCStatsDB[k] = (type(v) == "table") and { unpack(v) } or v
        end
    end
    if not HCStatsDB.show then HCStatsDB.show = {} end          -- per-stat visibility
    if not HCStatsDB.petDeathLog then HCStatsDB.petDeathLog = {} end
    if not HCStatsDB.partyDeathLog then HCStatsDB.partyDeathLog = {} end
    if not HCStatsDB.zonesVisited then HCStatsDB.zonesVisited = {} end

    -- One-time smart defaults for the mini view: keep it to a tight core, and
    -- only show pet stats for pet classes. Existing user toggles are preserved.
    if (HCStatsDB.showVersion or 0) < 1 then
        local _, class = UnitClass("player")
        local petClass = (class == "HUNTER" or class == "WARLOCK")
        local hiddenByDefault = {
            "biggestMelee", "biggestRanged", "highestFall", "longestFight", "mostDmgFight",
            "panic", "fights", "partyDeaths", "mostFoes", "clutchSaves", "untouched",
            "dmgTaken", "quests", "zones", "makgoraWon", "makgoraLost",
        }
        for _, k in ipairs(hiddenByDefault) do
            if HCStatsDB.show[k] == nil then HCStatsDB.show[k] = false end
        end
        if not petClass then
            if HCStatsDB.show.currentPet == nil then HCStatsDB.show.currentPet = false end
            if HCStatsDB.show.petDeaths == nil then HCStatsDB.show.petDeaths = false end
        end
        HCStatsDB.showVersion = 1
    end
    if (HCStatsDB.showVersion or 0) < 2 then
        if HCStatsDB.show.buffsGiven == nil then HCStatsDB.show.buffsGiven = false end
        HCStatsDB.showVersion = 2
    end

    if not HCStatsDB.lastWords then HCStatsDB.lastWords = {} end
    local lw = HCStatsDB.lastWords
    if lw.enabled        == nil then lw.enabled        = false end
    if lw.sayThreshold   == nil then lw.sayThreshold   = lw.threshold or 15 end
    if lw.alertThreshold == nil then lw.alertThreshold = 30 end
    if lw.channel        == nil then lw.channel        = "SAY" end
    if lw.say            == nil then lw.say            = true end
    if lw.alertSelf      == nil then lw.alertSelf      = true end
    if lw.useDefaults    == nil then lw.useDefaults    = true end
    if lw.custom         == nil then lw.custom         = {} end

    -- Comic splash config: per-splash enable, linked stat, and screen position.
    if not HCStatsDB.comic then
        HCStatsDB.comic = {
            pow  = { on = true, stat = "highestCrit",   x =  150, y = 100 },
            boom = { on = true, stat = "biggestMelee",  x = -170, y =  90 },
            zap  = { on = true, stat = "biggestRanged", x =  160, y = -60 },
        }
    end

    if not HCStatsDB.announce then HCStatsDB.announce = {} end
    local an = HCStatsDB.announce
    if an.enabled   == nil then an.enabled   = false end
    if an.guild     == nil then an.guild     = false end
    if an.guildOnly == nil then an.guildOnly = false end
    if an.max       == nil then an.max       = 2 end
    if an.stats   == nil then
        an.stats = { closestCall = true, toughestFoe = true, highestCrit = true, nearestDeath = true }
    end

    -- Account-wide stats (persist across all characters). Mak'gora especially:
    -- a loss is the character's death, so it only makes sense account-wide.
    HCStatsAccountDB = HCStatsAccountDB or {}
    if HCStatsAccountDB.makgoraWon  == nil then HCStatsAccountDB.makgoraWon  = 0 end
    if HCStatsAccountDB.makgoraLost == nil then HCStatsAccountDB.makgoraLost = 0 end
    if HCStatsAccountDB.makgoraDebug == nil then HCStatsAccountDB.makgoraDebug = false end
    if HCStatsAccountDB.mobDamage == nil then HCStatsAccountDB.mobDamage = {} end
    HC.adb = HCStatsAccountDB

    -- One-time migration: mob damage history used to be per-character.
    if HCStatsDB.mobDamage then
        for name, rec in pairs(HCStatsDB.mobDamage) do
            local cur = HCStatsAccountDB.mobDamage[name]
            if not cur or (rec.hit or 0) > (cur.hit or 0) then
                HCStatsAccountDB.mobDamage[name] = rec
            end
        end
        HCStatsDB.mobDamage = nil
    end

    -- Keep the account-wide mob table bounded: prune least-recently-seen.
    local MOB_CAP, MOB_TRIM = 400, 300
    local n = 0
    for _ in pairs(HCStatsAccountDB.mobDamage) do n = n + 1 end
    if n > MOB_CAP then
        local byAge = {}
        for name, rec in pairs(HCStatsAccountDB.mobDamage) do
            byAge[#byAge + 1] = { name = name, seen = rec.seen or 0 }
        end
        table.sort(byAge, function(a, b) return a.seen < b.seen end)
        for i = 1, n - MOB_TRIM do
            HCStatsAccountDB.mobDamage[byAge[i].name] = nil
        end
    end

    DB = HCStatsDB
    HC.db = HCStatsDB    -- exposed for Options.lua
end

-- ---------------------------------------------------------------------------
-- Formatting helpers
-- ---------------------------------------------------------------------------
local function Comma(n)
    n = math.floor((n or 0) + 0.5)
    local s = tostring(n)
    local k
    repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end

local function FmtTime(s)
    s = math.floor(s or 0)
    if s >= 60 then return string.format("%dm %02ds", math.floor(s / 60), s % 60) end
    return s .. "s"
end

local function FmtDiff(d)
    return (d >= 0) and ("+" .. d) or tostring(d)
end

local function FmtShort(n)
    n = n or 0
    if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
    if n >= 1e4 then return string.format("%.1fk", n / 1e3) end
    return Comma(n)
end

local function FmtSec(s)
    return string.format("%.1fs", s)
end

local function FmtPlayed(s)
    s = math.floor(s or 0)
    local d = math.floor(s / 86400); s = s % 86400
    local h = math.floor(s / 3600);  s = s % 3600
    local m = math.floor(s / 60)
    if d > 0 then return string.format("%dd %dh %dm", d, h, m) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

-- ---------------------------------------------------------------------------
-- The display frame
-- ---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "HCStatsFrame", UIParent, "BackdropTemplate")
frame:SetSize(180, 120)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
frame:SetBackdropColor(0, 0, 0, 0.8)
frame:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)

local STDFONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local miniTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
miniTitle:SetPoint("TOPLEFT", 10, -7)
miniTitle:SetText("HC Stats")
miniTitle:SetTextColor(1, 0.27, 0.27)

local miniDivider = frame:CreateTexture(nil, "ARTWORK")
miniDivider:SetColorTexture(0.6, 0.1, 0.1, 0.7)
miniDivider:SetHeight(1)

-- Reusable mini-view rows: small icon + label (left) + value (right-aligned).
local miniRows = {}
local function CreateMiniRow()
    local r = CreateFrame("Frame", nil, frame)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.icon:SetPoint("LEFT", 0, 0)
    r.left = r:CreateFontString(nil, "OVERLAY")
    r.left:SetJustifyH("LEFT")
    r.right = r:CreateFontString(nil, "OVERLAY")
    r.right:SetPoint("RIGHT", 0, 0)
    r.right:SetJustifyH("RIGHT")
    miniRows[#miniRows + 1] = r
    return r
end
local function GetMiniRow(i) miniRows[i] = miniRows[i] or CreateMiniRow(); return miniRows[i] end

-- Plain mouse-down/up movement (no RegisterForDrag, which can swallow the
-- button-release event on some clients and leave the frame stuck to the cursor).
local function StopDrag(self)
    if not self.moving then return end
    self.moving = false
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    if point and DB then DB.point = { point, relPoint, math.floor(x), math.floor(y) } end
end
frame:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and not (DB and DB.locked) then
        self.moving = true
        self:StartMoving()
    end
end)
frame:SetScript("OnMouseUp", function(self) StopDrag(self) end)
frame:SetScript("OnHide", StopDrag)

local function RestorePosition()
    local p = DB.point or LAYOUT_DEFAULTS.point
    frame:ClearAllPoints()
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------
-- A stat is visible unless explicitly disabled in the settings page.
function HC:Visible(key) return DB and DB.show and DB.show[key] ~= false end
function HC:SetVisible(key, shown)
    if DB and DB.show then DB.show[key] = shown and true or false; HC:UpdateDisplay() end
end

-- Ordered stat definitions: key, settings-page label, and a function returning
-- the frame's right-hand value string (or nil to show a grey dash).
HC.STATS = {
    { "timeAlive",    "Time Alive",     function() local a = LiveAlive(); return a and FmtPlayed(a) end },
    { "closestCall",  "Closest Call",   function()
        if DB.lowestPct then return math.floor(DB.lowestPct) .. "% (" .. Comma(DB.lowestHP) .. ")" end end },
    { "nearestDeath", "Nearest Death",  function() return DB.closestSeconds and FmtSec(DB.closestSeconds) end },
    { "biggestHit",   "Biggest Hit Taken", function() return Comma(DB.biggestHit) end },
    { "highestCrit",  "Highest Crit",   function() return Comma(DB.highestCrit) end },
    { "biggestMelee", "Biggest Melee Hit", function() return Comma(DB.biggestMelee) end },
    { "biggestRanged","Biggest Ranged Hit", function() return Comma(DB.biggestRanged) end },
    { "toughestFoe",  "Toughest Foe",   function() return DB.biggestLevelDiff and (FmtDiff(DB.biggestLevelDiff) .. " lvl") end },
    { "highestFall",  "Highest Fall",   function() return DB.highestFall and Comma(DB.highestFall) end },
    { "longestFight", "Longest Fight",  function() return FmtTime(DB.longestFight) end },
    { "mostDmgFight", "Most Dmg / Fight", function() return Comma(DB.mostDmgFight) end },
    { "killingBlows", "Killing Blows",  function() return Comma(DB.killingBlows) end },
    { "panic",        "Panic Moments",  function() return Comma(DB.panicMoments) end },
    { "fights",       "Fights Survived", function() return Comma(DB.fights) end },
    { "currentPet",   "Current Pet",    function()
        if UnitExists("pet") and not UnitIsDead("pet") then return UnitName("pet") end end },
    { "petDeaths",    "Pet Deaths",     function() return Comma(DB.petDeaths) end },
    { "partyDeaths",  "Party Deaths",   function() return Comma(DB.partyDeaths) end },
    { "mostFoes",     "Most Foes at Once", function() return Comma(DB.mostFoes) end },
    { "clutchSaves",  "Clutch Saves",   function() return Comma(DB.clutchSaves) end },
    { "untouched",    "Untouched Streak", function() return FmtTime(DB.untouched) end },
    { "dmgTaken",     "Total Dmg Taken", function() return FmtShort(DB.dmgTaken) end },
    { "quests",       "Quests Completed", function() return Comma(DB.quests) end },
    { "zones",        "Zones Explored", function() return Comma(DB.zones) end },
    { "makgoraWon",   "Mak'gora Won",   function() return Comma(HC.adb and HC.adb.makgoraWon) end },
    { "makgoraLost",  "Mak'gora Lost",  function() return Comma(HC.adb and HC.adb.makgoraLost) end },
    { "buffsGiven",   "Buffs Given",    function() return Comma(DB.buffsGiven) end },
}

-- Icon per stat, shared by the mini view and the full window.
local ICONP = "Interface\\Icons\\"
HC.ICONS = {
    timeAlive    = ICONP .. "INV_Misc_PocketWatch_01",
    closestCall  = ICONP .. "INV_Misc_Bone_HumanSkull_01",
    nearestDeath = ICONP .. "Spell_Shadow_Twilight",
    biggestHit   = ICONP .. "INV_Shield_04",
    highestCrit  = ICONP .. "Ability_Rogue_Eviscerate",
    biggestMelee = ICONP .. "INV_Sword_04",
    biggestRanged = ICONP .. "INV_Weapon_Bow_07",
    highestFall  = ICONP .. "Spell_Magic_FeatherFall",
    longestFight = ICONP .. "Ability_DualWield",
    mostDmgFight = ICONP .. "Spell_Fire_Fireball02",
    toughestFoe  = ICONP .. "INV_Misc_Head_Dragon_01",
    killingBlows = ICONP .. "Ability_Rogue_Ambush",
    panic        = ICONP .. "Spell_Shadow_PsychicScream",
    fights       = ICONP .. "Ability_Warrior_Revenge",
    currentPet   = ICONP .. "Ability_Hunter_BeastTaming",
    petDeaths    = ICONP .. "Spell_Nature_Reincarnation",
    partyDeaths  = ICONP .. "INV_Misc_Bone_HumanSkull_02",
    mostFoes     = ICONP .. "Ability_Warrior_Challange",
    clutchSaves  = ICONP .. "Spell_Holy_Restoration",
    untouched    = ICONP .. "Ability_Rogue_Evasion",
    dmgTaken     = ICONP .. "Spell_Shadow_ShadowWordPain",
    quests       = ICONP .. "INV_Scroll_08",
    zones        = ICONP .. "INV_Misc_Map_01",
    makgoraWon   = ICONP .. "INV_Sword_27",
    makgoraLost  = ICONP .. "Ability_Rogue_FeignDeath",
    buffsGiven   = ICONP .. "Spell_Holy_WordFortitude",
}

-- What each stat means and how it's tracked (full-window hover tooltips).
HC.STAT_HELP = {
    timeAlive    = "Your total /played time on this character - for a hardcore character, that IS your time alive. Server-authoritative, ticks live. The sub-line shows time at your current level.",
    closestCall  = "The lowest health you've ever reached while alive, as a percentage and raw HP. Captured the moment it happens, along with your level, the zone, and what last hit you.",
    nearestDeath = "How close you came to dying, in seconds: your HP at that moment divided by the damage-per-second you were taking (3-second window). Lower is scarier.",
    biggestHit   = "The largest single hit you've survived, with the attacker and ability that dealt it.",
    highestCrit  = "Your biggest critical hit, and what it landed on.",
    biggestMelee = "Your biggest melee auto-attack hit. White swings only - abilities don't count.",
    biggestRanged = "Your biggest ranged auto-attack hit (bow, gun, or wand). Stays at 0 if you never fire one.",
    highestFall  = "The most fall damage you've survived in one landing.",
    longestFight = "Your longest single stretch of combat.",
    mostDmgFight = "The most total damage you've taken within one fight.",
    toughestFoe  = "The biggest level gap above you on an enemy you actually traded blows with (it must be your target while fighting). Skull-level mobs can't be measured.",
    killingBlows = "Kills where your hit was the killing blow - assists don't count.",
    panic        = "Times your health dropped to 20% or below. Counts once per dip and re-arms when you recover above 20%.",
    clutchSaves  = "Fights where you dropped to 10% or below and still won. The earned version of a panic moment.",
    untouched    = "Your longest stretch inside a single fight without taking any damage at all.",
    mostFoes     = "The most separate enemies that damaged you within a single fight.",
    fights       = "Combat sessions you've entered and walked out of alive.",
    dmgTaken     = "Every point of damage this character has ever taken, lifetime - combat, falls, everything.",
    currentPet   = "Your currently active pet.",
    petDeaths    = "Pets that died on your watch. The most recent are listed with your level and the zone.",
    partyDeaths  = "Party or raid members who died near you - witnessed through your combat log, so they must be in range.",
    buffsGiven   = "Buffs you've put on other players (Fortitude, Blessings, a Battle Shout washing over the party...). One count per application per target.",
    quests       = "Quests turned in on this character.",
    zones        = "Distinct zones you've set foot in.",
    makgoraWon   = "Mak'gora duels won - ACCOUNT-WIDE, persists across all your characters. Auto-detected from system messages; record manually with /hcstats makgora won.",
    makgoraLost  = "Mak'gora duels lost - ACCOUNT-WIDE, your fallen characters' final duels. Record manually with /hcstats makgora lost.",
}

function HC:UpdateDisplay()
    if not DB then return end
    frame:SetScale(DB.scale or 1)

    local fs     = DB.fontSize or 12
    local iconSz = fs + 4
    local rowH   = fs + 8
    local PADX   = 10
    local LX     = iconSz + 6           -- label x offset (after icon)

    if frame._fs ~= fs then
        frame._fs = fs
        miniTitle:SetFont(STDFONT, fs + 3, "")
    end
    local titleH = fs + 9
    miniDivider:ClearAllPoints()
    miniDivider:SetPoint("TOPLEFT", PADX, -titleH)
    miniDivider:SetPoint("TOPRIGHT", -PADX, -titleH)

    local y = -titleH - 4
    local idx, contentW = 0, (miniTitle:GetStringWidth() or 60) + 22

    local function addRow(icon, label, value, lr, lg, lb)
        idx = idx + 1
        local r = GetMiniRow(idx)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", PADX, y)
        r:SetHeight(rowH)
        if icon then
            r.icon:Show(); r.icon:SetTexture(icon); r.icon:SetSize(iconSz, iconSz)
        else
            r.icon:Hide()
        end
        if r._fs ~= fs then
            r._fs = fs
            r.left:SetFont(STDFONT, fs, ""); r.right:SetFont(STDFONT, fs, "")
        end
        r.left:ClearAllPoints()
        r.left:SetPoint("LEFT", icon and LX or 0, 0)
        r.left:SetText(label)
        r.left:SetTextColor(lr or 1, lg or 1, lb or 1)
        r.right:SetText(value or "")
        local w = (icon and LX or 0) + (r.left:GetStringWidth() or 0) + 16 + (r.right:GetStringWidth() or 0)
        if w > contentW then contentW = w end
        r:Show()
        y = y - rowH
    end

    for _, s in ipairs(HC.STATS) do
        if self:Visible(s[1]) then
            local v = s[3]()
            local value = v and ("|cffffd100" .. v .. "|r") or "|cff777777--|r"
            addRow(HC.ICONS[s[1]], s[2], value)
        end
    end

    if inCombat then
        addRow(HC.ICONS.longestFight, "In Combat " .. FmtTime(GetTime() - combatStart),
            "|cffff9900" .. Comma(curFightDmg) .. "|r", 1, 0.6, 0)
    end

    for j = idx + 1, #miniRows do miniRows[j]:Hide() end

    -- Size the frame to fit, then stretch each row so values right-align.
    local width = math.max(150, contentW + PADX * 2)
    frame:SetWidth(width)
    frame:SetHeight(-y + 8)
    for i = 1, idx do miniRows[i]:SetWidth(width - PADX * 2) end

    frame:SetShown(DB.shown)
    if HC.fullFrame and HC.fullFrame:IsShown() then HC:RefreshFull() end
end

-- ---------------------------------------------------------------------------
-- Keyed stat data for the full window. Each entry:
--   { label, value, notes (array), color {r,g,b}, dim (bool), barPct (number) }
-- ---------------------------------------------------------------------------
function HC:StatData()
    local d = {}
    local a, lt = LiveAlive(), LiveLevelTime()
    d.timeAlive = { label = "Time Alive", value = a and FmtPlayed(a) or "--", dim = not a,
        color = { 0.3, 1, 0.3 }, notes = (a and lt) and { "this level: " .. FmtPlayed(lt) } or nil }

    if DB.lowestPct then
        d.closestCall = { label = "Closest Call",
            value = string.format("%d%%  (%s)", math.floor(DB.lowestPct), Comma(DB.lowestHP)),
            barPct = DB.lowestPct,
            notes = { string.format("at level %s in %s%s", tostring(DB.lowestLevel or "?"),
                DB.lowestZone or "?", DB.lowestSource and (", vs " .. DB.lowestSource) or "") } }
    else d.closestCall = { label = "Closest Call", value = "--", dim = true } end

    if DB.closestSeconds then
        d.nearestDeath = { label = "Nearest Death", value = FmtSec(DB.closestSeconds),
            notes = { string.format("at %s HP, level %s in %s%s", Comma(DB.closestSecHP or 0),
                tostring(DB.closestSecLevel or "?"), DB.closestSecZone or "?",
                DB.closestSecSource and (", vs " .. DB.closestSecSource) or "") } }
    else d.nearestDeath = { label = "Nearest Death", value = "--", dim = true } end

    d.biggestHit = { label = "Biggest Hit Taken", value = Comma(DB.biggestHit),
        notes = DB.biggestHitSource and { string.format("%s (%s), level %s in %s",
            DB.biggestHitSource, DB.biggestHitSpell or "?", tostring(DB.biggestHitLevel or "?"),
            DB.biggestHitZone or "?") } }
    d.highestCrit = { label = "Highest Crit", value = Comma(DB.highestCrit),
        notes = DB.highestCritSpell and
            { string.format("%s -> %s", DB.highestCritSpell, DB.highestCritTarget or "?") } }
    d.biggestMelee  = { label = "Biggest Melee Hit",  value = Comma(DB.biggestMelee) }
    d.biggestRanged = { label = "Biggest Ranged Hit", value = Comma(DB.biggestRanged) }

    if DB.highestFall then
        d.highestFall = { label = "Highest Fall", value = Comma(DB.highestFall),
            notes = { string.format("level %s in %s", tostring(DB.highestFallLevel or "?"),
                DB.highestFallZone or "?") } }
    else d.highestFall = { label = "Highest Fall", value = "--", dim = true } end

    d.longestFight = { label = "Longest Fight",  value = FmtTime(DB.longestFight) }
    d.mostDmgFight = { label = "Most Dmg / Fight", value = Comma(DB.mostDmgFight) }

    if DB.biggestLevelDiff then
        d.toughestFoe = { label = "Toughest Foe", value = FmtDiff(DB.biggestLevelDiff) .. " lvl",
            notes = { string.format("%s, you were level %s in %s", DB.biggestLevelDiffMob or "?",
                tostring(DB.biggestLevelDiffMyLevel or "?"), DB.biggestLevelDiffZone or "?") } }
    else d.toughestFoe = { label = "Toughest Foe", value = "--", dim = true } end

    d.killingBlows = { label = "Killing Blows",  value = Comma(DB.killingBlows) }
    d.panic        = { label = "Panic Moments",  value = Comma(DB.panicMoments) }
    d.fights       = { label = "Fights Survived", value = Comma(DB.fights) }

    local petname = (UnitExists("pet") and not UnitIsDead("pet")) and UnitName("pet") or nil
    d.currentPet = { label = "Current Pet", value = petname or "none", dim = not petname,
        color = { 0.4, 0.8, 1 } }

    local pnotes, log = {}, DB.petDeathLog or {}
    for i = #log, math.max(1, #log - 4), -1 do
        local p = log[i]
        pnotes[#pnotes + 1] = string.format("%s - lvl %s, %s", p.name or "?",
            tostring(p.level or "?"), p.zone or "?")
    end
    d.petDeaths = { label = "Pet Deaths", value = Comma(DB.petDeaths),
        notes = #pnotes > 0 and pnotes or nil }

    local anotes, alog = {}, DB.partyDeathLog or {}
    for i = #alog, math.max(1, #alog - 4), -1 do
        local p = alog[i]
        anotes[#anotes + 1] = string.format("%s - lvl %s, %s", p.name or "?",
            tostring(p.level or "?"), p.zone or "?")
    end
    d.partyDeaths = { label = "Party Deaths", value = Comma(DB.partyDeaths),
        notes = #anotes > 0 and anotes or nil }

    d.mostFoes    = { label = "Most Foes at Once", value = Comma(DB.mostFoes) }
    d.clutchSaves = { label = "Clutch Saves", value = Comma(DB.clutchSaves) }
    d.untouched   = { label = "Untouched Streak", value = FmtTime(DB.untouched) }
    d.dmgTaken    = { label = "Total Damage Taken", value = FmtShort(DB.dmgTaken) }
    d.quests      = { label = "Quests Completed", value = Comma(DB.quests) }
    d.zones       = { label = "Zones Explored", value = Comma(DB.zones) }
    d.makgoraWon  = { label = "Mak'gora Won", value = Comma(HC.adb and HC.adb.makgoraWon) }
    d.makgoraLost = { label = "Mak'gora Lost", value = Comma(HC.adb and HC.adb.makgoraLost) }
    d.buffsGiven  = { label = "Buffs Given", value = Comma(DB.buffsGiven) }
    return d
end

-- ---------------------------------------------------------------------------
-- Full-stats window (shows every stat, ignoring the mini-view toggles)
-- ---------------------------------------------------------------------------
local full = CreateFrame("Frame", "HCStatsFullFrame", UIParent, "BackdropTemplate")
full:SetSize(300, 420)
full:SetFrameStrata("DIALOG")
full:SetClampedToScreen(true)
full:SetMovable(true)
full:EnableMouse(true)
full:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
full:SetBackdropColor(0, 0, 0, 0.92)
full:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)
full:Hide()
tinsert(UISpecialFrames, "HCStatsFullFrame")  -- Escape closes the window
HC.fullFrame = full

local function SaveFullPos()
    local p, _, rp, x, y = full:GetPoint()
    if p and DB then DB.fullPoint = { p, rp, math.floor(x), math.floor(y) } end
end
local function StartFullDrag() full.moving = true; full:StartMoving() end
local function StopFullDrag()
    if not full.moving then return end
    full.moving = false
    full:StopMovingOrSizing()
    SaveFullPos()
end
full:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then StartFullDrag() end end)
full:SetScript("OnMouseUp", function() StopFullDrag() end)

-- Layout: ordered sections (header rows) and stat rows with an icon each.
local FULL_W, PAD, HEADER_H, ROW_BASE = 540, 12, 50, 22
local ICON = "Interface\\Icons\\"
local FULL_LAYOUT = {
    { header = "Survival" },
    { key = "closestCall",  icon = ICON .. "INV_Misc_Bone_HumanSkull_01" },
    { key = "nearestDeath", icon = ICON .. "Spell_Shadow_Twilight" },
    { key = "biggestHit",   icon = ICON .. "INV_Shield_04" },
    { key = "highestFall",  icon = ICON .. "Spell_Magic_FeatherFall" },
    { key = "panic",        icon = ICON .. "Spell_Shadow_PsychicScream" },
    { key = "clutchSaves",  icon = ICON .. "Spell_Holy_Restoration" },
    { key = "untouched",    icon = ICON .. "Ability_Rogue_Evasion" },
    { key = "mostFoes",     icon = ICON .. "Ability_Warrior_Challange" },
    { key = "fights",       icon = ICON .. "Ability_Warrior_Revenge" },
    { key = "dmgTaken",     icon = ICON .. "Spell_Shadow_ShadowWordPain" },
    { header = "Combat" },
    { key = "highestCrit",  icon = ICON .. "Ability_Rogue_Eviscerate" },
    { key = "biggestMelee", icon = ICON .. "INV_Sword_04" },
    { key = "biggestRanged", icon = ICON .. "INV_Weapon_Bow_07" },
    { key = "killingBlows", icon = ICON .. "Ability_Rogue_Ambush" },
    { key = "longestFight", icon = ICON .. "Ability_DualWield" },
    { key = "mostDmgFight", icon = ICON .. "Spell_Fire_Fireball02" },
    { key = "toughestFoe",  icon = ICON .. "INV_Misc_Head_Dragon_01" },
    { header = "Pet" },
    { key = "currentPet",   icon = ICON .. "Ability_Hunter_BeastTaming" },
    { key = "petDeaths",    icon = ICON .. "Spell_Nature_Reincarnation" },
    { header = "Group" },
    { key = "partyDeaths",  icon = ICON .. "INV_Misc_Bone_HumanSkull_02" },
    { key = "buffsGiven",   icon = ICON .. "Spell_Holy_WordFortitude" },
    { header = "Adventure" },
    { key = "quests",       icon = ICON .. "INV_Scroll_08" },
    { key = "zones",        icon = ICON .. "INV_Misc_Map_01" },
    { header = "Mak'gora (account-wide)" },
    { key = "makgoraWon",   icon = ICON .. "INV_Sword_27" },
    { key = "makgoraLost",  icon = ICON .. "Ability_Rogue_FeignDeath" },
    { header = "Character" },
    { key = "timeAlive",    icon = ICON .. "INV_Misc_PocketWatch_01" },
}

full:SetWidth(FULL_W)

local fullTitle = full:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
fullTitle:SetPoint("TOP", 0, -10)
fullTitle:SetText("|cffff4444Hardcore Stats|r")

local fullChar = full:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fullChar:SetPoint("TOP", 0, -30)

local fullClose = CreateFrame("Button", nil, full, "UIPanelCloseButton")
fullClose:SetPoint("TOPRIGHT", 2, 2)
fullClose:SetScript("OnClick", function() full:Hide() end)

local cfgBtn = CreateFrame("Button", nil, full, "UIPanelButtonTemplate")
cfgBtn:SetSize(100, 20)
cfgBtn:SetText("Settings")
cfgBtn:SetScript("OnClick", function()
    full:Hide()                       -- get out of the way of the settings window
    if HC.OpenOptions then HC:OpenOptions() end
end)

local divider = full:CreateTexture(nil, "ARTWORK")
divider:SetColorTexture(0.6, 0.1, 0.1, 0.8)
divider:SetPoint("TOPLEFT", PAD, -46)
divider:SetPoint("TOPRIGHT", -PAD, -46)
divider:SetHeight(1)

-- Reusable row pool (icon + label + right-aligned value + optional sub-line + bar)
local fullRows = {}
local function CreateRow()
    local r = CreateFrame("Frame", nil, full)
    r:SetWidth(FULL_W - PAD * 2)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.hl = r:CreateTexture(nil, "BORDER")  -- above bg, below icon/text
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.10)
    r.hl:Hide()
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        self.hl:Show()
        local help = self._key and HC.STAT_HELP[self._key]
        if help then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self._label or "", 1, 0.82, 0)
            GameTooltip:AddLine(help, 1, 1, 1, true)  -- true = word wrap
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)
    r:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then StartFullDrag() end end)
    r:SetScript("OnMouseUp", function() StopFullDrag() end)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("TOPLEFT", 2, -3)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.left:SetJustifyH("LEFT")
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("TOPRIGHT", -4, -4)
    r.right:SetJustifyH("RIGHT")
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWidth(FULL_W - PAD * 2 - 26)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    r.bar:SetMinMaxValues(0, 100)
    r.bar:SetHeight(7)
    r.bar:SetPoint("TOPLEFT", r.icon, "RIGHT", 6, -8)
    r.bar:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.barbg = r.bar:CreateTexture(nil, "BACKGROUND")
    r.barbg:SetAllPoints()
    r.barbg:SetColorTexture(0, 0, 0, 0.6)
    fullRows[#fullRows + 1] = r
    return r
end
local function GetRow(i) fullRows[i] = fullRows[i] or CreateRow(); return fullRows[i] end

local function StyleHeader(r, name, yy, w)
    r._key, r._label = nil, nil
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", PAD, yy)
    r:SetWidth(w)
    r:SetHeight(18)
    r.icon:Hide(); r.right:SetText(""); r.sub:SetText(""); r.bar:Hide()
    r.bg:SetColorTexture(0.55, 0.12, 0.12, 0.55)
    r.left:ClearAllPoints(); r.left:SetPoint("LEFT", 6, 0)
    r.left:SetText("|cffffe080" .. name:upper() .. "|r")
    r:Show()
end

-- Lays out one stat into row r at (x, yy) with width w. Returns its height.
local function StyleStat(r, item, x, yy, w, d, shade)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", x, yy)
    r:SetWidth(w)
    local sd = d[item.key] or { label = item.key, value = "--", dim = true }
    r._key, r._label = item.key, sd.label
    r.bg:SetColorTexture(1, 1, 1, shade and 0.05 or 0.015)
    r.icon:Show(); r.icon:SetTexture(item.icon)
    r.left:ClearAllPoints(); r.left:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, -1)
    local lc = sd.color
    r.left:SetText(sd.label)
    if lc then r.left:SetTextColor(lc[1], lc[2], lc[3]) else r.left:SetTextColor(1, 1, 1) end
    r.right:SetText((sd.dim and "|cff777777" or "|cffffd100") .. sd.value .. "|r")
    r.sub:SetWidth(w - 24)

    local h = ROW_BASE
    if sd.barPct then
        r.bar:Show(); r.bar:SetValue(sd.barPct)
        local p = sd.barPct / 100                   -- HP-style: red -> yellow -> green
        local cr = (p > 0.5) and (2 * (1 - p)) or 1
        local cg = (p < 0.5) and (2 * p) or 1
        r.bar:SetStatusBarColor(cr, cg, 0.12)
        h = h + 10
    else
        r.bar:Hide()
    end

    if sd.notes and #sd.notes > 0 then
        r.sub:SetText("|cff8a8a8a" .. table.concat(sd.notes, "\n") .. "|r")
        r.sub:ClearAllPoints()
        if sd.barPct then
            r.sub:SetPoint("TOPLEFT", r.bar, "BOTTOMLEFT", 0, -2)
        else
            r.sub:SetPoint("TOPLEFT", r.left, "BOTTOMLEFT", 0, -1)
        end
        h = h + (r.sub:GetStringHeight() or (#sd.notes * 11)) + 2
    else
        r.sub:SetText("")
    end
    r:SetHeight(h)
    r:Show()
    return h
end

function HC:RefreshFull()
    if not full:IsShown() then return end

    local cname = UnitName("player") or "?"
    local className, classFile = UnitClass("player")
    local c = (RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]) or { r = 1, g = 1, b = 1 }
    fullChar:SetText(("|cff%02x%02x%02x%s|r   Level %d %s"):format(
        math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255),
        cname, UnitLevel("player"), className or ""))

    local d = HC:StatData()
    local colGap = 12
    local colW = (FULL_W - PAD * 2 - colGap) / 2
    local colX = { PAD, PAD + colW + colGap }
    local y, idx, shade = -HEADER_H, 0, false

    -- Walk the layout: each header spans full width; its rows pair into 2 columns.
    local i = 1
    while i <= #FULL_LAYOUT do
        local item = FULL_LAYOUT[i]
        if item.header then
            idx = idx + 1
            StyleHeader(GetRow(idx), item.header, y, FULL_W - PAD * 2)
            y = y - 21
            i = i + 1
            local items = {}
            while i <= #FULL_LAYOUT and not FULL_LAYOUT[i].header do
                items[#items + 1] = FULL_LAYOUT[i]; i = i + 1
            end
            for j = 1, #items, 2 do
                shade = not shade
                idx = idx + 1
                local h1 = StyleStat(GetRow(idx), items[j], colX[1], y, colW, d, shade)
                local h2 = 0
                if items[j + 1] then
                    idx = idx + 1
                    h2 = StyleStat(GetRow(idx), items[j + 1], colX[2], y, colW, d, shade)
                end
                y = y - math.max(h1, h2) - 2
            end
        else
            i = i + 1
        end
    end
    for j = idx + 1, #fullRows do fullRows[j]:Hide() end

    local footerY = y - 6
    cfgBtn:ClearAllPoints()
    cfgBtn:SetPoint("TOP", full, "TOP", 0, footerY)
    full:SetHeight(-footerY + 20 + 10)
end

function HC:ToggleFull()
    if full:IsShown() then full:Hide(); return end
    local p = DB and DB.fullPoint
    full:ClearAllPoints()
    if p then full:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else full:SetPoint("CENTER") end
    full:Show()
    HC:RefreshFull()
end

-- Keep the full window live while it's open (OnUpdate only fires when shown).
local faccum = 0
full:SetScript("OnUpdate", function(_, elapsed)
    if full.moving and not IsMouseButtonDown("LeftButton") then StopFullDrag() end
    faccum = faccum + elapsed
    if faccum < 1 then return end
    faccum = 0
    HC:RefreshFull()
end)

-- The [+] button on the mini frame opens the full window.
local plus = CreateFrame("Button", nil, frame)
plus:SetSize(16, 16)
plus:SetPoint("TOPRIGHT", -4, -4)
plus:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
plus:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
plus:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
plus:SetScript("OnClick", function() HC:ToggleFull() end)

-- Periodic refresh + bulletproof drag release.
local accum = 0
frame:SetScript("OnUpdate", function(self, elapsed)
    -- Stop moving the instant the left button is released, regardless of whether
    -- OnDragStop/OnMouseUp fire (the drag system can swallow those on some clients).
    if self.moving and not IsMouseButtonDown("LeftButton") then
        StopDrag(self)
    end

    accum = accum + elapsed
    local interval = inCombat and 0.5 or 10
    if accum < interval then return end
    accum = 0
    HC:UpdateDisplay()
end)

-- ---------------------------------------------------------------------------
-- Stat capture
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Danger alert: screen-flash vignette + sound + center warning text
-- ---------------------------------------------------------------------------
local flash = CreateFrame("Frame", nil, UIParent)
flash:SetAllPoints(UIParent)
flash:SetFrameStrata("FULLSCREEN_DIALOG")
flash:EnableMouse(false)
flash:SetToplevel(false)
flash:Hide()
local flashTex = flash:CreateTexture(nil, "BACKGROUND")
flashTex:SetAllPoints()
flashTex:SetTexture("Interface\\FullScreenTextures\\LowHealth")  -- red edge vignette, clear center
local flashAG = flash:CreateAnimationGroup()
local fa1 = flashAG:CreateAnimation("Alpha")
fa1:SetFromAlpha(0); fa1:SetToAlpha(0.35); fa1:SetDuration(0.2); fa1:SetOrder(1)
local fa2 = flashAG:CreateAnimation("Alpha")
fa2:SetFromAlpha(0.35); fa2:SetToAlpha(0); fa2:SetDuration(0.9); fa2:SetOrder(2)
flashAG:SetScript("OnFinished", function() flash:Hide() end)

-- ---------------------------------------------------------------------------
-- Comic-book splashes (POW/BOOM/ZAP). Each splash can be toggled, dragged to
-- a new position (placement mode), and linked to any record stat in settings.
-- ---------------------------------------------------------------------------

-- Record stats a splash can be linked to (key -> label for the dropdown).
HC.SPLASH_TRIGGERS = {
    { "highestCrit",   "Highest Crit" },
    { "biggestMelee",  "Biggest Melee Hit" },
    { "biggestRanged", "Biggest Ranged Hit" },
    { "biggestHit",    "Biggest Hit Taken" },
    { "closestCall",   "Closest Call (new low)" },
    { "nearestDeath",  "Nearest Death" },
    { "highestFall",   "Highest Fall" },
    { "toughestFoe",   "Toughest Foe" },
    { "mostFoes",      "Most Foes at Once" },
    { "clutchSaves",   "Clutch Save" },
}

-- Tilt direction per splash (SetRotation: positive = counter-clockwise = top
-- leans left). POW leans right, BOOM leans left, ZAP goes either way.
local COMIC_TILT = {
    pow  = { -18, -6 },
    boom = {   6, 18 },
    zap  = { -15, 15 },
}

local splashPlacement = false
local comicFrames = {}

local function StopSplashDrag(f)
    if not f.moving then return end
    f.moving = false
    f:StopMovingOrSizing()
    local cx, cy = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local conf = DB and DB.comic and DB.comic[f.which]
    if cx and ux and conf then
        conf.x = math.floor(cx - ux + 0.5)
        conf.y = math.floor(cy - uy + 0.5)
    end
end

local function GetComicFrame(which)
    local f = comicFrames[which]
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f.which = which
    f:SetSize(150, 150)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(false)
    f:Hide()
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexture("Interface\\AddOns\\HCStats\\Media\\" .. which)
    f.lastPop = -99

    f.ag = f:CreateAnimationGroup()
    local aIn = f.ag:CreateAnimation("Alpha")
    aIn:SetFromAlpha(0); aIn:SetToAlpha(1); aIn:SetDuration(0.08); aIn:SetOrder(1)
    local grow = f.ag:CreateAnimation("Scale")
    if grow.SetScaleFrom then
        grow:SetScaleFrom(0.4, 0.4); grow:SetScaleTo(1, 1)
    else
        grow:SetFromScale(0.4, 0.4); grow:SetToScale(1, 1)  -- older anim API
    end
    grow:SetOrigin("CENTER", 0, 0)
    grow:SetDuration(0.14); grow:SetOrder(1)
    local aOut = f.ag:CreateAnimation("Alpha")
    aOut:SetFromAlpha(1); aOut:SetToAlpha(0); aOut:SetDuration(0.45)
    aOut:SetStartDelay(0.9); aOut:SetOrder(2)
    f.ag:SetScript("OnFinished", function() if not splashPlacement then f:Hide() end end)

    -- Dragging, active only while placement mode is on.
    f:SetScript("OnMouseDown", function(self, btn)
        if splashPlacement and btn == "LeftButton" then
            self.moving = true
            self:StartMoving()
        end
    end)
    f:SetScript("OnMouseUp", function(self) StopSplashDrag(self) end)
    f:SetScript("OnUpdate", function(self)
        if self.moving and not IsMouseButtonDown("LeftButton") then StopSplashDrag(self) end
    end)

    comicFrames[which] = f
    return f
end

function HC:ComicPop(which)
    if not DB or DB.comicPops == false or splashPlacement then return end
    local conf = DB.comic and DB.comic[which]
    if not conf or conf.on == false then return end
    local f = GetComicFrame(which)
    local now = GetTime()
    if now - f.lastPop < 8 then return end  -- early levels set records constantly
    f.lastPop = now
    local t = COMIC_TILT[which] or COMIC_TILT.pow
    f.tex:SetRotation(math.rad(math.random(t[1], t[2])))
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER",
        conf.x + math.random(-30, 30), conf.y + math.random(-25, 25))
    f:Show()
    f.ag:Stop()
    f.ag:Play()
end

-- Called wherever a record stat improves; pops whatever splashes are linked.
function HC:ComicEvent(statKey)
    if not DB or not DB.comic then return end
    for which, conf in pairs(DB.comic) do
        if conf.stat == statKey then HC:ComicPop(which) end
    end
end

-- Placement mode: show all splashes statically and let the user drag them.
function HC:ToggleSplashPlacement()
    if not DB or not DB.comic then return end
    splashPlacement = not splashPlacement
    for which, conf in pairs(DB.comic) do
        local f = GetComicFrame(which)
        f.ag:Stop()
        if splashPlacement then
            f:EnableMouse(true)
            f:SetAlpha(1)
            f.tex:SetRotation(0)
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", conf.x, conf.y)
            f:Show()
        else
            StopSplashDrag(f)
            f:EnableMouse(false)
            f:Hide()
        end
    end
    print("|cffff4444HC Stats|r: " .. (splashPlacement
        and "drag the splashes where you want them, then toggle placement again to save."
        or "splash positions saved."))
end

-- Debug helper: zero just the three hit records (and splash cooldowns) so the
-- next hit sets a "new record" and pops the splash again.
function HC:ResetHitRecords()
    if not DB then return end
    DB.highestCrit, DB.highestCritSpell, DB.highestCritTarget = 0, nil, nil
    DB.biggestMelee, DB.biggestMeleeTarget = 0, nil
    DB.biggestRanged, DB.biggestRangedTarget = 0, nil
    for _, f in pairs(comicFrames) do f.lastPop = -99 end
    HC:UpdateDisplay()
    print("|cffff4444HC Stats|r: hit records reset (crit / melee / ranged). Next hit pops the splash.")
end

function HC:RandomLastWord()
    local lw = DB.lastWords
    local customs = {}
    for _, m in ipairs(lw.custom or {}) do
        if m and m ~= "" then customs[#customs + 1] = m end
    end
    local defaults = lw.useDefaults and DEFAULT_LASTWORDS or {}
    local haveC, haveD = #customs > 0, #defaults > 0

    if haveC and haveD then
        -- 50/50 so your own lines show as often as the whole built-in set
        if math.random(2) == 1 then return customs[math.random(#customs)] end
        return defaults[math.random(#defaults)]
    elseif haveC then
        return customs[math.random(#customs)]
    elseif haveD then
        return defaults[math.random(#defaults)]
    end
    return nil
end

function HC:DangerAlert()
    -- Custom low-health warning clip; falls back to the raid-warning sound.
    if not PlaySoundFile("Interface\\AddOns\\HCStats\\Sounds\\Frank.ogg", "Master") then
        PlaySound(8959, "Master")
    end
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        RaidNotice_AddMessage(RaidWarningFrame, "|cffff2020LOW HEALTH!|r", ChatTypeInfo["RAID_WARNING"])
    end
    flash:SetAlpha(0); flash:Show()
    flashAG:Stop(); flashAG:Play()
end

-- /say and /yell require a *hardware event*, so an auto-trigger can't send them
-- directly. We queue the line and flush it on the player's next keypress (which
-- is a hardware event). Group channels have no such restriction.
local pendingChat = {}  -- FIFO: several messages can queue before a keypress
local CHAT_TTL = 6      -- seconds before a queued line goes stale and is dropped
local catcher = CreateFrame("Frame", nil, UIParent)
catcher:Hide()
catcher:SetPropagateKeyboardInput(true)  -- let keys still reach the game
local function FlushPending()
    local now = GetTime()
    for i = 1, #pendingChat do
        local m = pendingChat[i]
        if now - m.t <= CHAT_TTL then
            SendChatMessage(m.msg, m.chan)   -- we're inside a hardware event here
        end
        pendingChat[i] = nil
    end
    catcher:EnableKeyboard(false)
    catcher:Hide()
end
catcher:SetScript("OnKeyDown", FlushPending)

local function SayMessage(msg, channel, fromHardware)
    local public = (channel == "SAY" or channel == "YELL" or channel == "EMOTE")
    if fromHardware or not public then
        SendChatMessage(msg, channel)        -- already in a hardware event, or group channel
    else
        pendingChat[#pendingChat + 1] = { msg = msg, chan = channel, t = GetTime() }
        catcher:EnableKeyboard(true)
        catcher:Show()
        C_Timer.After(CHAT_TTL + 1, function()   -- janitor: drop stale, release keyboard
            local now = GetTime()
            for i = #pendingChat, 1, -1 do
                if now - pendingChat[i].t > CHAT_TTL then table.remove(pendingChat, i) end
            end
            if #pendingChat == 0 then
                catcher:EnableKeyboard(false)
                catcher:Hide()
            end
        end)
    end
end

function HC:TriggerDanger(fromHardware)
    local lw = DB.lastWords
    if lw.say then
        local msg = HC:RandomLastWord()
        if msg then SayMessage(msg, lw.channel or "SAY", fromHardware) end
    end
    if lw.alertSelf then HC:DangerAlert() end
end

-- Settings "Test" button runs inside a click (a hardware event), so it can send
-- /say directly - a true preview of the real thing.
function HC:TestDanger()
    HC:TriggerDanger(true)
    if not (DB.lastWords and DB.lastWords.say) then
        print("|cffff4444HC Stats|r: \"Announce a message in chat\" is off, so nothing was sent.")
    end
end

-- ---------------------------------------------------------------------------
-- New-record announcements (after combat). Each entry: the DB field that holds
-- the record, whether lower is better, a settings label, and a message builder.
-- ---------------------------------------------------------------------------
HC.ANNOUNCE = {
    closestCall  = { field = "lowestPct", lower = true, label = "Closest Call (new low %)",
        msg = function() return ("new closest call - survived at %d%% HP%s!"):format(
            math.floor(DB.lowestPct), DB.lowestSource and (" vs " .. DB.lowestSource) or "") end },
    nearestDeath = { field = "closestSeconds", lower = true, label = "Nearest Death (seconds)",
        msg = function() return ("that was close - only %s from death!"):format(FmtSec(DB.closestSeconds)) end },
    biggestHit   = { field = "biggestHit", label = "Biggest Hit Taken",
        msg = function() return ("just took a record hit for %s%s!"):format(Comma(DB.biggestHit),
            DB.biggestHitSource and (" from " .. DB.biggestHitSource) or "") end },
    highestCrit  = { field = "highestCrit", label = "Highest Crit",
        msg = function() return ("new biggest crit - %s%s!"):format(Comma(DB.highestCrit),
            DB.highestCritSpell and (" (" .. DB.highestCritSpell .. ")") or "") end },
    biggestMelee = { field = "biggestMelee", label = "Biggest Melee Hit",
        msg = function() return ("new biggest melee hit: %s!"):format(Comma(DB.biggestMelee)) end },
    biggestRanged = { field = "biggestRanged", label = "Biggest Ranged Hit",
        msg = function() return ("new biggest ranged hit: %s!"):format(Comma(DB.biggestRanged)) end },
    toughestFoe  = { field = "biggestLevelDiff", label = "Toughest Foe",
        msg = function() return ("just took on something %s levels above me%s!"):format(
            FmtDiff(DB.biggestLevelDiff), DB.biggestLevelDiffMob and (" (" .. DB.biggestLevelDiffMob .. ")") or "") end },
    highestFall  = { field = "highestFall", label = "Highest Fall",
        msg = function() return ("survived a record fall for %s damage!"):format(Comma(DB.highestFall)) end },
    longestFight = { field = "longestFight", label = "Longest Fight",
        msg = function() return ("new longest fight: %s!"):format(FmtTime(DB.longestFight)) end },
    mostDmgFight = { field = "mostDmgFight", label = "Most Dmg in One Fight",
        msg = function() return ("record damage taken in one fight: %s!"):format(Comma(DB.mostDmgFight)) end },
    untouched    = { field = "untouched", label = "Untouched Streak",
        msg = function() return ("untouchable - %s in combat without a scratch!"):format(FmtTime(DB.untouched)) end },
    mostFoes     = { field = "mostFoes", label = "Most Foes at Once",
        msg = function() return ("fought %d enemies at once and lived!"):format(DB.mostFoes) end },
}
-- Priority order when the per-fight cap trims the list (most impressive first).
HC.ANNOUNCE_ORDER = {
    "closestCall", "nearestDeath", "toughestFoe", "biggestHit", "highestCrit",
    "mostFoes", "highestFall", "untouched", "biggestMelee", "biggestRanged",
    "longestFight", "mostDmgFight",
}

-- Channel: party (never raid), else /say. Guild is optional: alongside, or only.
-- /say queues to the next keypress via SayMessage (hardware-event rule).
function HC:Announce(msgs)
    local an = DB.announce
    local primary   = (IsInGroup() and not IsInRaid()) and "PARTY" or "SAY"
    local toGuild   = an.guild and IsInGuild()
    local guildOnly = toGuild and an.guildOnly
    for _, m in ipairs(msgs) do
        if not guildOnly then SayMessage(m, primary, false) end
        if toGuild then SayMessage(m, "GUILD", false) end
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
    local an = DB.announce
    if not (an and an.enabled) or IsInRaid() or not combatSnapshot then return end
    local cap = an.max or 2
    for _, key in ipairs(HC.ANNOUNCE_ORDER) do
        if #pendingAnnounce >= cap then break end
        if an.stats[key] then
            local def = HC.ANNOUNCE[key]
            local cur, old = DB[def.field], combatSnapshot[def.field]
            local improved
            if def.lower then
                improved = cur ~= nil and (old == nil or cur < old)
            else
                improved = (cur or 0) > (old or 0)
            end
            if key == "toughestFoe" and (DB.biggestLevelDiff or 0) <= 0 then improved = false end
            if improved then
                pendingAnnounce[#pendingAnnounce + 1] = def.msg()
            end
        end
    end
end

local function OnHealth()
    local hp  = UnitHealth("player")
    local max = UnitHealthMax("player")
    if not max or max == 0 or hp <= 0 then return end
    local pct = hp / max * 100

    if not DB.lowestPct or pct < DB.lowestPct then
        DB.lowestPct    = pct
        DB.lowestHP     = hp
        DB.lowestMax    = max
        DB.lowestLevel  = UnitLevel("player")
        DB.lowestZone   = GetZoneText()
        DB.lowestSource = lastHitBy or (inCombat and (UnitName("target")) or nil)
        HC:ComicEvent("closestCall")
        HC:UpdateDisplay()
    end

    -- Time-to-death: current HP divided by recent incoming damage rate.
    local dps = RecentDPS()
    if dps > 0 then
        local ttd = hp / dps
        if not DB.closestSeconds or ttd < DB.closestSeconds then
            DB.closestSeconds   = ttd
            DB.closestSecHP     = hp
            DB.closestSecLevel  = UnitLevel("player")
            DB.closestSecZone   = GetZoneText()
            DB.closestSecSource = lastHitBy
            HC:ComicEvent("nearestDeath")
            HC:UpdateDisplay()
        end
    end

    if pct <= PANIC_THRESHOLD then
        if not wasBelow then
            wasBelow = true
            DB.panicMoments = DB.panicMoments + 1
            HC:UpdateDisplay()
        end
    else
        wasBelow = false
    end

    -- Mark this fight as a "clutch" if you dipped below the clutch threshold.
    if inCombat and pct <= CLUTCH_THRESHOLD then fightWentLow = true end

    -- Famous last words (chat) and the attention alert fire on independent
    -- thresholds. Each: once per dip, re-arm above threshold +5, short cooldown.
    local lw = DB.lastWords
    if lw and lw.enabled then
        if lw.say then
            local th = lw.sayThreshold or 15
            if pct <= th and not lwSayArmed then
                lwSayArmed = true
                if GetTime() - lwSayFire > 10 then
                    lwSayFire = GetTime()
                    local msg = HC:RandomLastWord()
                    if msg then SayMessage(msg, lw.channel or "SAY", false) end
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
    if not DB.biggestLevelDiff or diff > DB.biggestLevelDiff then
        DB.biggestLevelDiff        = diff
        DB.biggestLevelDiffMob     = enemyName or UnitName("target")
        DB.biggestLevelDiffMyLevel = UnitLevel("player")
        DB.biggestLevelDiffZone    = GetZoneText()
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

local function OnCombatLog()
    if not DB then return end  -- events can fire before PLAYER_LOGIN initializes us

    -- Capture the header as plain locals: CLEU fires for everything in combat-log
    -- range, so this hot path must not allocate (no table per event).
    local _, sub, _, srcGUID, srcName, srcFlags, _, dstGUID, dstName, dstFlags =
        CombatLogGetCurrentEventInfo()

    if sub == "PARTY_KILL" then
        if srcGUID == playerGUID then
            DB.killingBlows = DB.killingBlows + 1
            HC:UpdateDisplay()
        end
        return
    end

    if sub == "UNIT_DIED" then
        if petGUID and dstGUID == petGUID then
            DB.petDeaths = DB.petDeaths + 1
            PushLog(DB.petDeathLog, {
                name = petName or dstName or "Pet",
                level = UnitLevel("player"), zone = GetZoneText(),
            })
            petGUID = nil
            HC:UpdateDisplay()
        elseif partyGUIDs[dstGUID] then
            DB.partyDeaths = (DB.partyDeaths or 0) + 1
            PushLog(DB.partyDeathLog, {
                name = partyGUIDs[dstGUID] or dstName or "?",
                level = UnitLevel("player"), zone = GetZoneText(),
            })
            partyGUIDs[dstGUID] = nil   -- don't recount; re-added on next roster update
            HC:UpdateDisplay()
        end
        return
    end

    if sub == "ENVIRONMENTAL_DAMAGE" then
        if dstGUID ~= playerGUID then return end
        local envType, amt = select(12, CombatLogGetCurrentEventInfo())  -- envType(12), amount(13)
        if amt and amt > 0 then
            PushIncoming(amt)
            DB.dmgTaken = (DB.dmgTaken or 0) + amt
            lastHitBy = envType
            if envType == "Falling" and (not DB.highestFall or amt > DB.highestFall) then
                DB.highestFall      = amt
                DB.highestFallLevel = UnitLevel("player")
                DB.highestFallZone  = GetZoneText()
                HC:ComicEvent("highestFall")
                HC:UpdateDisplay()
            end
        end
        return
    end

    -- Only events involving the player matter past this point.
    if srcGUID ~= playerGUID and dstGUID ~= playerGUID then return end

    -- Buffs you put on OTHER players (Fortitude, Battle Shout hitting the
    -- party, etc.). One count per application per target.
    if sub == "SPELL_AURA_APPLIED" then
        if srcGUID == playerGUID and dstGUID ~= playerGUID and dstFlags
                and bit.band(dstFlags, COMBATLOG_OBJECT_TYPE_PLAYER or 0x400) > 0 then
            local _, _, _, auraType = select(12, CombatLogGetCurrentEventInfo())  -- auraType(15)
            if auraType == "BUFF" then
                DB.buffsGiven = (DB.buffsGiven or 0) + 1
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

    if srcGUID == playerGUID and critical and amount > DB.highestCrit then
        DB.highestCrit       = amount
        DB.highestCritSpell  = spellName
        DB.highestCritTarget = dstName
        changed = true
        HC:ComicEvent("highestCrit")
    end

    -- Weapon auto-attacks: SWING = melee weapon, RANGE = ranged weapon.
    if srcGUID == playerGUID then
        if sub == "SWING_DAMAGE" and amount > DB.biggestMelee then
            DB.biggestMelee, DB.biggestMeleeTarget = amount, dstName
            changed = true
            HC:ComicEvent("biggestMelee")
        elseif sub == "RANGE_DAMAGE" and amount > DB.biggestRanged then
            DB.biggestRanged, DB.biggestRangedTarget = amount, dstName
            changed = true
            HC:ComicEvent("biggestRanged")
        end
    end

    if dstGUID == playerGUID then
        lastHitBy   = srcName
        curFightDmg = curFightDmg + amount
        PushIncoming(amount)
        DB.dmgTaken = (DB.dmgTaken or 0) + amount

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
            if fightFoeCount > DB.mostFoes then
                DB.mostFoes = fightFoeCount
                HC:ComicEvent("mostFoes")
            end
        end
        if inCombat and untouchedStart then  -- a hit ends the current no-hit streak
            local stretch = GetTime() - untouchedStart
            if stretch > DB.untouched then DB.untouched = stretch end
            untouchedStart = GetTime()
        end

        if amount > DB.biggestHit then
            DB.biggestHit       = amount
            DB.biggestHitSource = srcName
            DB.biggestHitSpell  = spellName
            DB.biggestHitLevel  = UnitLevel("player")
            DB.biggestHitZone   = GetZoneText()
            changed = true
            HC:ComicEvent("biggestHit")
        end
    end

    -- Toughest foe: sample the level of whichever side isn't the player.
    local enemyGUID, enemyName
    if srcGUID == playerGUID then
        enemyGUID, enemyName = dstGUID, dstName
    elseif dstGUID == playerGUID then
        enemyGUID, enemyName = srcGUID, srcName
    end
    if SampleTargetLevel(enemyGUID, enemyName) then
        changed = true
        HC:ComicEvent("toughestFoe")
    end

    if changed then HC:UpdateDisplay() end
end

local function OnCombatStart()
    inCombat    = true
    combatStart = GetTime()
    curFightDmg = 0
    wipe(fightAttackers)
    fightFoeCount  = 0
    fightWentLow   = false
    untouchedStart = GetTime()
    -- Snapshot record fields so combat end can detect new bests set this fight.
    combatSnapshot = {}
    for _, def in pairs(HC.ANNOUNCE) do combatSnapshot[def.field] = DB[def.field] end
    HC:UpdateDisplay()
end

local function OnCombatEnd()
    if inCombat then
        local dur = GetTime() - combatStart
        DB.fights = DB.fights + 1
        if dur > DB.longestFight then
            DB.longestFight     = dur
            DB.longestFightZone = GetZoneText()
        end
        if curFightDmg > DB.mostDmgFight then
            DB.mostDmgFight     = curFightDmg
            DB.mostDmgFightZone = GetZoneText()
        end
        -- Untouched streak: the final stretch from last hit to combat end.
        if untouchedStart then
            local stretch = GetTime() - untouchedStart
            if stretch > DB.untouched then DB.untouched = stretch end
        end
        -- Clutch save: dropped low but lived through the fight.
        if fightWentLow and (UnitHealth("player") or 0) > 0 then
            DB.clutchSaves = DB.clutchSaves + 1
            HC:ComicEvent("clutchSaves")
        end
        if (UnitHealth("player") or 0) > 0 then HC:CheckAnnounce() end  -- only if you lived
    end
    untouchedStart = nil
    fightWentLow   = false
    inCombat = false
    -- Queued brags (this fight's, or held over from a chain-pull) go out after
    -- a short breather - and only if we're still out of combat by then.
    if #pendingAnnounce > 0 then
        C_Timer.After(ANNOUNCE_DELAY, function() HC:FlushAnnounce() end)
    end
    HC:UpdateDisplay()
end

-- ---------------------------------------------------------------------------
-- Welcome window (first login on a character; nobody reads chat on login)
-- ---------------------------------------------------------------------------
function HC:ShowWelcome()
    if HC.welcomeFrame then HC.welcomeFrame:Show(); return end

    local w = CreateFrame("Frame", "HCStatsWelcome", UIParent, "BackdropTemplate")
    w:SetSize(400, 100)  -- height set after the text lays out
    w:SetPoint("CENTER", 0, 120)
    w:SetFrameStrata("DIALOG")
    w:SetClampedToScreen(true)
    w:EnableMouse(true)
    w:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    w:SetBackdropColor(0, 0, 0, 0.92)
    w:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)
    tinsert(UISpecialFrames, "HCStatsWelcome")  -- Escape closes
    HC.welcomeFrame = w

    local icon = w:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", 14, -12)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    title:SetText("|cffff4444Welcome to HC Stats|r")

    local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() w:Hide() end)

    local body = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", 16, -52)
    body:SetWidth(368)
    body:SetJustifyH("LEFT")
    body:SetSpacing(3)
    body:SetText("Your hardcore trophy case is recording: closest calls, biggest hits, "
        .. "pet & party deaths, Mak'gora, and more.\n\n"
        .. "The on-screen panel starts with a few core stats. There's a lot more to turn on:\n\n"
        .. "|cffffd100-|r  Pick which stats show on the panel in |cffffd100Settings|r\n"
        .. "|cffffd100-|r  Click |cffffd100[+]|r on the panel to see every stat with details\n"
        .. "|cffffd100-|r  Optional fun: famous last words, record announcements,\n"
        .. "    comic POW! splashes, mob damage warnings")

    local settingsBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    settingsBtn:SetSize(110, 22)
    settingsBtn:SetText("Open Settings")
    settingsBtn:SetScript("OnClick", function()
        w:Hide()
        if HC.OpenOptions then HC:OpenOptions() end
    end)

    local fullBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    fullBtn:SetSize(110, 22)
    fullBtn:SetText("View All Stats")
    fullBtn:SetScript("OnClick", function()
        w:Hide()
        HC:ToggleFull()
    end)

    local okBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    okBtn:SetSize(80, 22)
    okBtn:SetText("Got it")
    okBtn:SetScript("OnClick", function() w:Hide() end)

    local bodyH = body:GetStringHeight() or 120
    settingsBtn:SetPoint("BOTTOMLEFT", 16, 14)
    fullBtn:SetPoint("BOTTOM", 0, 14)
    okBtn:SetPoint("BOTTOMRIGHT", -16, 14)
    w:SetHeight(52 + bodyH + 52)
end

-- ---------------------------------------------------------------------------
-- Reset confirmation
-- ---------------------------------------------------------------------------
StaticPopupDialogs["HCSTATS_RESET"] = {
    text = "Reset all HC Stats records for this character?",
    button1 = YES, button2 = NO,
    OnAccept = function()
        local keep = {
            shown = DB.shown, locked = DB.locked, point = DB.point, show = DB.show,
            fullPoint = DB.fullPoint, fontSize = DB.fontSize, scale = DB.scale,
            lastWords = DB.lastWords, showVersion = DB.showVersion, mobTooltip = DB.mobTooltip,
            announce = DB.announce, welcomed = DB.welcomed, comicPops = DB.comicPops,
            comic = DB.comic,
            playedTotal = DB.playedTotal, playedLevel = DB.playedLevel,
        }
        wipe(DB)
        for k, v in pairs(keep) do DB[k] = v end
        ApplyDefaults()
        HC:UpdateDisplay()
        print("|cffff4444HC Stats|r: records reset.")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- ---------------------------------------------------------------------------
-- Slash command
-- ---------------------------------------------------------------------------
SLASH_HCSTATS1 = "/hcstats"
SLASH_HCSTATS2 = "/hc"
SlashCmdList.HCSTATS = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "lock" then
        DB.locked = not DB.locked
        print("|cffff4444HC Stats|r: frame " .. (DB.locked and "locked." or "unlocked."))
    elseif msg == "config" or msg == "options" or msg == "settings" then
        if HC.OpenOptions then HC:OpenOptions() end
    elseif msg == "full" or msg == "all" then
        HC:ToggleFull()
    elseif msg == "splashes" or msg == "splash" then
        HC:ToggleSplashPlacement()
    elseif msg == "welcome" then
        HC:ShowWelcome()
    elseif msg == "reset" then
        StaticPopup_Show("HCSTATS_RESET")
    elseif msg:match("^makgora") or msg:match("^mak'gora") then
        local arg = msg:match("(%a+)%s*$")
        if arg == "won" then
            HC.adb.makgoraWon = HC.adb.makgoraWon + 1
            print("|cffff4444HC Stats|r: Mak'gora win recorded (" .. HC.adb.makgoraWon .. " total).")
            HC:UpdateDisplay()
        elseif arg == "lost" then
            HC.adb.makgoraLost = HC.adb.makgoraLost + 1
            print("|cffff4444HC Stats|r: Mak'gora loss recorded (" .. HC.adb.makgoraLost .. " total).")
            HC:UpdateDisplay()
        elseif arg == "debug" then
            HC.adb.makgoraDebug = not HC.adb.makgoraDebug
            print("|cffff4444HC Stats|r: Mak'gora message capture "
                .. (HC.adb.makgoraDebug and "ON (watch chat during a duel, then tell the author the line)." or "OFF."))
        elseif arg == "reset" then
            HC.adb.makgoraWon, HC.adb.makgoraLost = 0, 0
            print("|cffff4444HC Stats|r: Mak'gora tallies reset.")
            HC:UpdateDisplay()
        else
            print(("|cffff4444HC Stats|r Mak'gora - won: %d, lost: %d.  /hcstats makgora won|lost|debug|reset")
                :format(HC.adb.makgoraWon, HC.adb.makgoraLost))
        end
    elseif msg == "show" then
        DB.shown = true; HC:UpdateDisplay()
    elseif msg == "hide" then
        DB.shown = false; HC:UpdateDisplay()
    else
        DB.shown = not DB.shown
        HC:UpdateDisplay()
        print("|cffff4444HC Stats|r: " .. (DB.shown and "shown." or "hidden.")
            .. "  (/hcstats lock | reset)")
    end
end

-- ---------------------------------------------------------------------------
-- Mob tooltip: "this thing has hurt you before"
-- ---------------------------------------------------------------------------
local function AddMobInfo(tooltip)
    if not DB or not DB.mobTooltip or not HC.adb then return end
    local _, unit = tooltip:GetUnit()
    if not unit or UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then return end
    local rec = HC.adb.mobDamage[UnitName(unit)]
    if not rec or rec.hit <= 0 then return end
    -- Opportunistically note the mob's level while we're looking right at it.
    local l = UnitLevel(unit)
    if l and l > 0 then rec.lvl = l end
    local ctx = rec.atLevel and ("  |cff888888(at lvl " .. rec.atLevel .. ")|r") or ""
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("|cffff5555Has hit you for up to|r", "|cffffd100" .. Comma(rec.hit) .. "|r" .. ctx)
    if rec.crit > 0 then
        tooltip:AddDoubleLine("|cffff5555Worst crit|r", "|cffffd100" .. Comma(rec.crit) .. "|r")
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tip)
        if tip == GameTooltip then AddMobInfo(tip) end
    end)
else
    GameTooltip:HookScript("OnTooltipSetUnit", AddMobInfo)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local function RequestPlayed()
    awaitingPlayedMsg = true
    RequestTimePlayed()
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("TIME_PLAYED_MSG")
frame:RegisterEvent("UNIT_PET")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterUnitEvent("UNIT_HEALTH", "player")

frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    -- Some events (UNIT_HEALTH especially) can fire during the loading screen,
    -- before PLAYER_LOGIN has initialized the saved variables.
    if not DB and event ~= "PLAYER_LOGIN" then return end
    if event == "PLAYER_LOGIN" then
        ApplyDefaults()
        playerGUID = UnitGUID("player")
        RestorePosition()
        if HC.BuildOptions then HC:BuildOptions() end
        UpdatePet()
        HC:UpdateDisplay()
        RequestPlayed()
        print("|cffff4444HC Stats|r loaded. /hcstats to toggle, config, or hover for details.")
        if not DB.welcomed then
            DB.welcomed = true
            -- a few seconds late so the world has settled in first
            C_Timer.After(4, function() HC:ShowWelcome() end)
        end
    elseif event == "TIME_PLAYED_MSG" then
        -- arg1 = total played seconds, arg2 = played at current level
        playedBase      = arg1
        playedLevelBase = arg2
        playedBaseTime  = GetTime()
        DB.playedTotal  = arg1
        DB.playedLevel  = arg2
        HC:UpdateDisplay()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "UNIT_HEALTH" then
        OnHealth()
    elseif event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    elseif event == "PLAYER_LEVEL_UP" then
        RequestPlayed() -- refresh the per-level timer base
        HC:UpdateDisplay()
    elseif event == "UNIT_PET" then
        if arg1 == "player" then UpdatePet() end
    elseif event == "GROUP_ROSTER_UPDATE" then
        RefreshGroup()
    elseif event == "QUEST_TURNED_IN" then
        DB.quests = (DB.quests or 0) + 1
        HC:UpdateDisplay()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        VisitZone()
    elseif event == "CHAT_MSG_SYSTEM" then
        OnSystemMsg(arg1)
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdatePet()
        RefreshGroup()
        VisitZone()
        HC:UpdateDisplay()
    end
end)
