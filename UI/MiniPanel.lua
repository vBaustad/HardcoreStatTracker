local ADDON, HC = ...

local Comma, FmtTime, FmtDiff, FmtShort, FmtSec, FmtPlayed = HC.Comma, HC.FmtTime, HC.FmtDiff, HC.FmtShort, HC.FmtSec, HC.FmtPlayed
local LAYOUT_DEFAULTS = HC.LAYOUT_DEFAULTS

-- ---------------------------------------------------------------------------
-- The display frame
-- ---------------------------------------------------------------------------
HC.frame = CreateFrame("Frame", "HardcoreStatTrackerFrame", UIParent, "BackdropTemplate")
HC.frame:SetSize(180, 120)
HC.frame:SetClampedToScreen(true)
HC.frame:SetMovable(true)
HC.frame:EnableMouse(true)
HC.frame:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8X8",  -- solid: lets the slider reach true opaque
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
HC.frame:SetBackdropColor(0.05, 0.04, 0.04, 0.8)
HC.frame:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)

-- Applies the saved mini-panel opacity (called on login and from the slider).
function HC:ApplyMiniAlpha()
    HC.frame:SetBackdropColor(0.05, 0.04, 0.04, (HC.db and HC.db.miniAlpha) or 0.8)
end

local STDFONT = HC.STDFONT

local miniTitle = HC.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
miniTitle:SetPoint("TOPLEFT", 10, -7)
miniTitle:SetText("Hardcore Stat Tracker")
miniTitle:SetTextColor(1, 0.27, 0.27)

local miniDivider = HC.frame:CreateTexture(nil, "ARTWORK")
miniDivider:SetColorTexture(0.6, 0.1, 0.1, 0.7)
miniDivider:SetHeight(1)

-- Reusable mini-view rows: small icon + label (left) + value (right-aligned).
local miniRows = {}
local function CreateMiniRow()
    local r = CreateFrame("Frame", nil, HC.frame)
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
    if point and HC.db then HC.db.point = { point, relPoint, math.floor(x), math.floor(y) } end
end
HC.frame:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and not (HC.db and HC.db.locked) then
        self.moving = true
        self:StartMoving()
    end
end)
HC.frame:SetScript("OnMouseUp", function(self) StopDrag(self) end)
HC.frame:SetScript("OnHide", StopDrag)

function HC.RestorePosition()
    local p = HC.db.point or LAYOUT_DEFAULTS.point
    HC.frame:ClearAllPoints()
    HC.frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------
-- A stat is visible unless explicitly disabled in the settings page.
function HC:Visible(key) return HC.db and HC.db.show and HC.db.show[key] ~= false end
function HC:SetVisible(key, shown)
    if HC.db and HC.db.show then HC.db.show[key] = shown and true or false; HC:UpdateDisplay() end
end

-- Ordered stat definitions: key, settings-page label, and a function returning
-- the frame's right-hand value string (or nil to show a grey dash).
HC.STATS = {
    { "timeAlive",    "Time Alive",     function() local a = HC.LiveAlive(); return a and FmtPlayed(a) end },
    { "closestCall",  "Closest Call",   function()
        if HC.db.lowestPct then return math.floor(HC.db.lowestPct) .. "% (" .. Comma(HC.db.lowestHP) .. ")" end end },
    { "nearestDeath", "Nearest Death",  function() return HC.db.closestSeconds and FmtSec(HC.db.closestSeconds) end },
    { "biggestHit",   "Biggest Hit Taken", function() return Comma(HC.db.biggestHit) end },
    { "highestCrit",  "Highest Crit",   function() return Comma(HC.db.highestCrit) end },
    { "biggestMelee", "Biggest Melee Hit", function() return Comma(HC.db.biggestMelee) end },
    { "biggestRanged","Biggest Ranged Hit", function() return Comma(HC.db.biggestRanged) end },
    { "toughestFoe",  "Toughest Foe",   function() return HC.db.biggestLevelDiff and (FmtDiff(HC.db.biggestLevelDiff) .. " lvl") end },
    { "highestFall",  "Highest Fall",   function() return HC.db.highestFall and Comma(HC.db.highestFall) end },
    { "longestFight", "Longest Fight",  function() return FmtTime(HC.db.longestFight) end },
    { "mostDmgFight", "Most Dmg / Fight", function() return Comma(HC.db.mostDmgFight) end },
    { "killingBlows", "Killing Blows",  function() return Comma(HC.db.killingBlows) end },
    { "panic",        "Panic Moments",  function() return Comma(HC.db.panicMoments) end },
    { "fights",       "Fights Survived", function() return Comma(HC.db.fights) end },
    { "currentPet",   "Current Pet",    function()
        if UnitExists("pet") and not UnitIsDead("pet") then return UnitName("pet") end end },
    { "petDeaths",    "Pet Deaths",     function() return Comma(HC.db.petDeaths) end },
    { "partyDeaths",  "Party Deaths",   function() return Comma(HC.db.partyDeaths) end },
    { "mostFoes",     "Most Foes at Once", function() return Comma(HC.db.mostFoes) end },
    { "clutchSaves",  "Clutch Saves",   function() return Comma(HC.db.clutchSaves) end },
    { "untouched",    "Untouched Streak", function() return FmtTime(HC.db.untouched) end },
    { "dmgTaken",     "Total Dmg Taken", function() return FmtShort(HC.db.dmgTaken) end },
    { "quests",       "Quests Completed", function() return Comma(HC.db.quests) end },
    { "zones",        "Zones Explored", function() return Comma(HC.db.zones) end },
    { "makgoraWon",   "Mak'gora Won",   function() return Comma(HC.adb and HC.adb.makgoraWon) end },
    { "makgoraLost",  "Mak'gora Lost",  function() return Comma(HC.adb and HC.adb.makgoraLost) end },
    { "buffsGiven",   "Buffs Given",    function() return Comma(HC.db.buffsGiven) end },
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
    untouched    = ICONP .. "Ability_Parry",
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
    makgoraWon   = "Mak'gora duels won - ACCOUNT-WIDE, persists across all your characters. Auto-detected from system messages; record manually with /hst makgora won.",
    makgoraLost  = "Mak'gora duels lost - ACCOUNT-WIDE, your fallen characters' final duels. Record manually with /hst makgora lost.",
}

function HC:UpdateDisplay()
    if not HC.db then return end
    HC.frame:SetScale(HC.db.scale or 1)

    local fs     = HC.db.fontSize or 12
    local iconSz = fs + 4
    local rowH   = fs + 8
    local PADX   = 10
    local LX     = iconSz + 6           -- label x offset (after icon)

    if HC.frame._fs ~= fs then
        HC.frame._fs = fs
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

    if HC.state.inCombat and HC.db.combatTimer ~= false then
        addRow(HC.ICONS.longestFight, "In Combat " .. FmtTime(GetTime() - HC.state.combatStart),
            "|cffff9900" .. Comma(HC.state.curFightDmg) .. "|r", 1, 0.6, 0)
    end

    for j = idx + 1, #miniRows do miniRows[j]:Hide() end

    -- Size the frame to fit, then stretch each row so values right-align.
    local width = math.max(150, contentW + PADX * 2)
    HC.frame:SetWidth(width)
    HC.frame:SetHeight(-y + 8)
    for i = 1, idx do miniRows[i]:SetWidth(width - PADX * 2) end

    HC.frame:SetShown(HC.db.shown)
    if HC.fullFrame and HC.fullFrame:IsShown() then HC:RefreshFull() end
end
-- The [+] button on the mini frame opens the full window.
local plus = CreateFrame("Button", nil, HC.frame)
plus:SetSize(16, 16)
plus:SetPoint("TOPRIGHT", -4, -4)
plus:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
plus:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
plus:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
plus:SetScript("OnClick", function() HC:ToggleFull() end)

-- Periodic refresh + bulletproof drag release.
local accum = 0
HC.frame:SetScript("OnUpdate", function(self, elapsed)
    -- Stop moving the instant the left button is released, regardless of whether
    -- OnDragStop/OnMouseUp fire (the drag system can swallow those on some clients).
    if self.moving and not IsMouseButtonDown("LeftButton") then
        StopDrag(self)
    end

    accum = accum + elapsed
    local interval = HC.state.inCombat and 0.5 or 10
    if accum < interval then return end
    accum = 0
    HC:UpdateDisplay()
end)
