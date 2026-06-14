local ADDON, HC = ...

local Comma, FmtTime, FmtDiff, FmtShort, FmtSec, FmtPlayed = HC.Comma, HC.FmtTime, HC.FmtDiff, HC.FmtShort, HC.FmtSec, HC.FmtPlayed
local STDFONT = HC.STDFONT

-- ---------------------------------------------------------------------------
-- Keyed stat data for the full window. Each entry:
--   { label, value, notes (array), color {r,g,b}, dim (bool), barPct (number) }
-- ---------------------------------------------------------------------------
function HC:StatData()
    local d = {}
    local a, lt = HC.LiveAlive(), HC.LiveLevelTime()
    d.timeAlive = { label = "Time Alive", value = a and FmtPlayed(a) or "--", dim = not a,
        color = { 0.3, 1, 0.3 }, notes = (a and lt) and { "this level: " .. FmtPlayed(lt) } or nil }

    if HC.db.lowestPct then
        d.closestCall = { label = "Closest Call",
            value = string.format("%d%%  (%s)", math.floor(HC.db.lowestPct), Comma(HC.db.lowestHP)),
            barPct = HC.db.lowestPct,
            notes = { string.format("at level %s in %s%s", tostring(HC.db.lowestLevel or "?"),
                HC.db.lowestZone or "?", HC.db.lowestSource and (", vs " .. HC.db.lowestSource) or "") } }
    else d.closestCall = { label = "Closest Call", value = "--", dim = true } end

    if HC.db.closestSeconds then
        d.nearestDeath = { label = "Nearest Death", value = FmtSec(HC.db.closestSeconds),
            notes = { string.format("at %s HP, level %s in %s%s", Comma(HC.db.closestSecHP or 0),
                tostring(HC.db.closestSecLevel or "?"), HC.db.closestSecZone or "?",
                HC.db.closestSecSource and (", vs " .. HC.db.closestSecSource) or "") } }
    else d.nearestDeath = { label = "Nearest Death", value = "--", dim = true } end

    -- "(Melee)" on an auto-attack is noise; only name the ability when it's one.
    local hitSpell = HC.db.biggestHitSpell
    local hitBy = HC.db.biggestHitSource
    if hitBy and hitSpell and hitSpell ~= "Melee" then
        hitBy = hitBy .. " (" .. hitSpell .. ")"
    end
    d.biggestHit = { label = "Biggest Hit Taken", value = Comma(HC.db.biggestHit),
        notes = hitBy and { string.format("%s, level %s in %s", hitBy,
            tostring(HC.db.biggestHitLevel or "?"), HC.db.biggestHitZone or "?") } }
    d.highestCrit = { label = "Highest Crit", value = Comma(HC.db.highestCrit),
        notes = HC.db.highestCritSpell and
            { string.format("%s -> %s", HC.db.highestCritSpell, HC.db.highestCritTarget or "?") } }
    d.biggestMelee  = { label = "Biggest Melee Hit",  value = Comma(HC.db.biggestMelee) }
    d.biggestRanged = { label = "Biggest Ranged Hit", value = Comma(HC.db.biggestRanged) }
    d.biggestSpell  = { label = "Biggest Spell Hit", value = Comma(HC.db.biggestSpell),
        notes = HC.db.biggestSpellName and
            { string.format("%s -> %s", HC.db.biggestSpellName, HC.db.biggestSpellTarget or "?") } }
    d.biggestAbility = { label = "Biggest Ability Hit", value = Comma(HC.db.biggestAbility),
        notes = HC.db.biggestAbilityName and
            { string.format("%s -> %s", HC.db.biggestAbilityName, HC.db.biggestAbilityTarget or "?") } }

    d.biggestHeal = { label = "Biggest Heal", value = Comma(HC.db.biggestHeal) }
    d.healingDone = { label = "Total Healing", value = FmtShort(HC.db.healingDone) }
    local snotes, slog = {}, HC.db.playerSavedLog or {}
    for i = #slog, math.max(1, #slog - 4), -1 do
        local p = slog[i]
        snotes[#snotes + 1] = string.format("%s - lvl %s, %s", p.name or "?",
            tostring(p.level or "?"), p.zone or "?")
    end
    d.playersSaved = { label = "Players Saved", value = Comma(HC.db.playersSaved),
        notes = #snotes > 0 and snotes or nil }

    if HC.db.highestFall then
        local val = HC.db.highestFallPct and (math.floor(HC.db.highestFallPct) .. "%") or Comma(HC.db.highestFall)
        d.highestFall = { label = "Highest Fall", value = val,
            notes = { string.format("%s damage, level %s in %s", Comma(HC.db.highestFall),
                tostring(HC.db.highestFallLevel or "?"), HC.db.highestFallZone or "?") } }
    else d.highestFall = { label = "Highest Fall", value = "--", dim = true } end

    d.longestFight = { label = "Longest Fight",  value = FmtTime(HC.db.longestFight) }
    d.mostDmgFight = { label = "Most Dmg Taken / Fight", value = Comma(HC.db.mostDmgFight) }

    if HC.db.biggestLevelDiff then
        d.toughestFoe = { label = "Toughest Foe", value = FmtDiff(HC.db.biggestLevelDiff) .. " lvl",
            notes = { string.format("%s, you were level %s in %s", HC.db.biggestLevelDiffMob or "?",
                tostring(HC.db.biggestLevelDiffMyLevel or "?"), HC.db.biggestLevelDiffZone or "?") } }
    else d.toughestFoe = { label = "Toughest Foe", value = "--", dim = true } end

    d.killingBlows = { label = "Killing Blows",  value = Comma(HC.db.killingBlows) }
    d.panic        = { label = "Panic Moments",  value = Comma(HC.db.panicMoments) }
    d.fights       = { label = "Fights Survived", value = Comma(HC.db.fights) }

    local petname = (UnitExists("pet") and not UnitIsDead("pet")) and UnitName("pet") or nil
    d.currentPet = { label = "Current Pet", value = petname or "none", dim = not petname,
        color = { 0.4, 0.8, 1 } }

    local pnotes, log = {}, HC.db.petDeathLog or {}
    for i = #log, math.max(1, #log - 4), -1 do
        local p = log[i]
        pnotes[#pnotes + 1] = string.format("%s - lvl %s, %s", p.name or "?",
            tostring(p.level or "?"), p.zone or "?")
    end
    d.petDeaths = { label = "Pet Deaths", value = Comma(HC.db.petDeaths),
        notes = #pnotes > 0 and pnotes or nil }
    d.petKillingBlows = { label = "Pet Killing Blows", value = Comma(HC.db.petKillingBlows) }

    local anotes, alog = {}, HC.db.partyDeathLog or {}
    for i = #alog, math.max(1, #alog - 4), -1 do
        local p = alog[i]
        anotes[#anotes + 1] = string.format("%s - lvl %s, %s", p.name or "?",
            tostring(p.level or "?"), p.zone or "?")
    end
    d.partyDeaths = { label = "Party Deaths", value = Comma(HC.db.partyDeaths),
        notes = #anotes > 0 and anotes or nil }

    d.mostFoes    = { label = "Most Foes at Once", value = Comma(HC.db.mostFoes) }
    d.clutchSaves = { label = "Clutch Saves", value = Comma(HC.db.clutchSaves) }
    d.untouched   = { label = "Untouched Streak", value = FmtTime(HC.db.untouched) }
    d.dmgTaken    = { label = "Total Damage Taken", value = FmtShort(HC.db.dmgTaken) }
    d.dmgDone     = { label = "Total Damage Done", value = FmtShort(HC.db.dmgDone) }
    d.quests      = { label = "Quests Completed", value = Comma(HC.db.quests) }
    d.zones       = { label = "Zones Explored", value = Comma(HC.db.zones) }
    d.jumps       = { label = "Jumps", value = Comma(HC.db.jumps) }
    d.goldEarned  = { label = "Gold Earned", value = GetCoinTextureString(HC.db.goldEarned or 0) }
    d.goldSpent   = { label = "Gold Spent", value = GetCoinTextureString(HC.db.goldSpent or 0) }
    d.goldLooted  = { label = "Gold Looted", value = GetCoinTextureString(HC.db.goldLooted or 0) }
    d.bagsLooted  = { label = "Bags Looted", value = Comma(HC.db.bagsLooted) }
    d.makgoraWon  = { label = "Mak'gora Won", value = Comma(HC.adb and HC.adb.makgoraWon) }
    d.makgoraLost = { label = "Mak'gora Lost", value = Comma(HC.adb and HC.adb.makgoraLost) }
    d.highestLevel = { label = "Highest Level", value = Comma(HC.adb and HC.adb.highestLevel) }
    d.level60s    = { label = "Level 60s", value = Comma(HC.adb and HC.adb.level60s) }
    d.buffsGiven  = { label = "Buffs Given", value = Comma(HC.db.buffsGiven) }
    return d
end

-- ---------------------------------------------------------------------------
-- Full-stats window (shows every stat, ignoring the mini-view toggles)
-- ---------------------------------------------------------------------------
local full = CreateFrame("Frame", "HardcoreStatTrackerFullFrame", UIParent, "BackdropTemplate")
full:SetSize(300, 420)
full:SetFrameStrata("DIALOG")
full:SetClampedToScreen(true)
full:SetMovable(true)
full:EnableMouse(true)
full:SetBackdrop({
    -- Solid fill: the tooltip background texture is inherently translucent,
    -- so the slider's max could never reach actually-opaque with it.
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
full:SetBackdropColor(0.05, 0.04, 0.04, 0.97)  -- near-opaque: the world behind hurt readability
full:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)
full:Hide()
tinsert(UISpecialFrames, "HardcoreStatTrackerFullFrame")  -- Escape closes the window
HC.fullFrame = full

-- Always store a TOP anchor so the window grows/shrinks downward and the top
-- edge (title, tabs, buttons) never moves when the active tab changes height.
local function SaveFullPos()
    local _, _, _, x, y = full:GetPoint()
    if x and HC.db then HC.db.fullPoint = { "TOP", "TOP", math.floor(x), math.floor(y) } end
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
local FULL_W, PAD, HEADER_H, ROW_BASE = 540, 12, 90, 22
local ICON = "Interface\\Icons\\"
local FULL_LAYOUT = {
    { header = "Survival" },
    { key = "closestCall",  icon = ICON .. "INV_Misc_Bone_HumanSkull_01" },
    { key = "nearestDeath", icon = ICON .. "Spell_Shadow_Twilight" },
    { key = "biggestHit",   icon = ICON .. "INV_Shield_04" },
    { key = "highestFall",  icon = ICON .. "Spell_Magic_FeatherFall" },
    { key = "panic",        icon = ICON .. "Spell_Shadow_PsychicScream" },
    { key = "clutchSaves",  icon = ICON .. "Spell_Holy_Restoration" },
    { key = "untouched",    icon = ICON .. "Ability_Parry" },
    { key = "mostFoes",     icon = ICON .. "Ability_Warrior_Challange" },
    { key = "fights",       icon = ICON .. "Ability_Warrior_Revenge" },
    { key = "dmgTaken",     icon = ICON .. "Spell_Shadow_ShadowWordPain" },
    { header = "Combat" },
    { key = "highestCrit",  icon = ICON .. "Ability_Rogue_Eviscerate" },
    { key = "biggestMelee", icon = ICON .. "INV_Sword_04" },
    { key = "biggestRanged", icon = ICON .. "INV_Weapon_Bow_07" },
    { key = "biggestSpell", icon = ICON .. "Spell_Fire_FlameBolt" },
    { key = "biggestAbility", icon = ICON .. "Ability_Warrior_SavageBlow" },
    { key = "killingBlows", icon = ICON .. "Ability_Rogue_Ambush" },
    { key = "dmgDone",      icon = ICON .. "Spell_Fire_Fireball02" },
    { key = "longestFight", icon = ICON .. "Ability_DualWield" },
    { key = "mostDmgFight", icon = ICON .. "Spell_Fire_Fireball02" },
    { key = "toughestFoe",  icon = ICON .. "INV_Misc_Head_Dragon_01" },
    { header = "Healing" },
    { key = "biggestHeal",  icon = ICON .. "Spell_Holy_FlashHeal" },
    { key = "healingDone",  icon = ICON .. "Spell_Holy_GreaterHeal" },
    { key = "playersSaved", icon = ICON .. "Spell_Holy_LayOnHands" },
    { header = "Pet" },
    { key = "currentPet",   icon = ICON .. "Ability_Hunter_BeastTaming" },
    { key = "petDeaths",    icon = ICON .. "Spell_Nature_Reincarnation" },
    { key = "petKillingBlows", icon = ICON .. "Ability_Hunter_KillCommand" },
    { header = "Group" },
    { key = "partyDeaths",  icon = ICON .. "INV_Misc_Bone_HumanSkull_02" },
    { key = "buffsGiven",   icon = ICON .. "Spell_Holy_WordFortitude" },
    { header = "Adventure" },
    { key = "quests",       icon = ICON .. "INV_Scroll_08" },
    { key = "zones",        icon = ICON .. "INV_Misc_Map_01" },
    { key = "jumps",        icon = ICON .. "Ability_Rogue_Sprint" },
    { header = "Wealth" },
    { key = "goldEarned",   icon = ICON .. "INV_Misc_Coin_01" },
    { key = "goldSpent",    icon = ICON .. "INV_Misc_Coin_04" },
    { key = "goldLooted",   icon = ICON .. "INV_Misc_Coin_02" },
    { key = "bagsLooted",   icon = ICON .. "INV_Misc_Bag_10" },
    { header = "Account (all characters)" },
    { key = "highestLevel", icon = ICON .. "Spell_ChargePositive" },
    { key = "level60s",     icon = ICON .. "INV_Crown_01" },
    { header = "Mak'gora (account-wide)" },
    { key = "makgoraWon",   icon = ICON .. "INV_Sword_27" },
    { key = "makgoraLost",  icon = ICON .. "Ability_Rogue_FeignDeath" },
}

-- Sections are grouped into tabs so the window stays a sane height.
local FULL_TABS = {
    { name = "Combat",  sections = { Survival = true, Combat = true, Healing = true } },
    { name = "World",   sections = { Pet = true, Group = true, Adventure = true, Wealth = true } },
    { name = "Account", sections = { ["Account (all characters)"] = true, ["Mak'gora (account-wide)"] = true } },
}
local tabButtons = {}

full:SetWidth(FULL_W)

local fullTitle = full:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
fullTitle:SetPoint("TOP", 0, -10)
fullTitle:SetText("|cffff4444Hardcore Stat Tracker|r")

local fullChar = full:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fullChar:SetPoint("TOP", 0, -30)

-- Time Alive lives in the header (it's THE hardcore stat), freeing a row below.
local aliveLine = full:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
aliveLine:SetPoint("TOP", 0, -44)

-- Audit line: reset count + (if flagged) a tamper warning. A hoverable band that
-- carries the tooltip; positioned in the footer between the two buttons by
-- RefreshFull. Text is filled in RefreshFull too.
local auditFrame = CreateFrame("Frame", nil, full)
auditFrame:SetHeight(20)
auditFrame:EnableMouse(true)
local auditText = auditFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
auditText:SetPoint("CENTER")
auditFrame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Records integrity", 1, 0.82, 0)
    GameTooltip:AddLine(("Stat resets: %d"):format(HC.db.resets or 0), 1, 1, 1)
    GameTooltip:AddLine("Times this character's records have been wiped with /hst reset.", 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine(" ")
    if HC.db.tamperedEver then
        GameTooltip:AddLine("Integrity check FAILED", 1, 0.2, 0.2)
        GameTooltip:AddLine(("The saved stats were changed outside the game (%d time%s). These records may not be legitimate."):format(
            HC.db.tamperCount or 1, (HC.db.tamperCount or 1) == 1 and "" or "s"), 1, 1, 1, true)
    else
        GameTooltip:AddLine("Integrity check OK", 0.4, 1, 0.4)
        GameTooltip:AddLine("The saved stats match the value written by the addon. A manual edit of the SavedVariables file would show here.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end)
auditFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

local fullClose = CreateFrame("Button", nil, full, "UIPanelCloseButton")
fullClose:SetPoint("TOPRIGHT", 2, 2)
fullClose:SetScript("OnClick", function() full:Hide() end)

-- Top-left "Memorial" button: opens the death memorial / fallen-heroes roll.
local memBtn = HC.MakeButton(full, "Memorial", 84, 20)
memBtn:SetPoint("TOPLEFT", 8, -8)
memBtn:SetScript("OnClick", function() if HC.ShowMemorial then HC:ShowMemorial() end end)

local cfgBtn = HC.MakeButton(full, "Settings", 100, 22)
cfgBtn:SetScript("OnClick", function()
    full:Hide()                       -- get out of the way of the settings window
    if HC.OpenOptions then HC:OpenOptions() end
end)

-- "Display" button opens a shared Quick Settings popup (mini panel + full window
-- size/opacity). The popup is parented to the screen (NOT the full window), so
-- scaling the window can't move its own slider out from under the cursor. These
-- same controls also live on the Settings page; both read/write the saved vars.
local displayBtn = HC.MakeButton(full, "Display", 100, 22)

local adjust = CreateFrame("Frame", "HardcoreStatTrackerFullAdjust", UIParent, "BackdropTemplate")
adjust:SetSize(240, 290)
adjust:SetFrameStrata("FULLSCREEN_DIALOG")
adjust:SetClampedToScreen(true)
adjust:SetMovable(true); adjust:EnableMouse(true)
adjust:Hide()
adjust:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
adjust:SetBackdropColor(0.05, 0.04, 0.04, 0.95)
adjust:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)
tinsert(UISpecialFrames, "HardcoreStatTrackerFullAdjust")  -- Escape closes
adjust:SetScript("OnMouseDown", function(self) self:StartMoving() end)
adjust:SetScript("OnMouseUp", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    if p and HC.db then HC.db.adjustPoint = { p, rp, math.floor(x), math.floor(y) } end
end)

local aTitle = adjust:CreateFontString(nil, "OVERLAY", "GameFontNormal")
aTitle:SetPoint("TOP", 0, -8)
aTitle:SetText("|cffff4444Quick Settings|r")
local aClose = CreateFrame("Button", nil, adjust, "UIPanelCloseButton")
aClose:SetPoint("TOPRIGHT", 2, 2)
aClose:SetScript("OnClick", function() adjust:Hide() end)

local function quickHeader(text, y)
    local h = adjust:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", 14, y)
    h:SetText("|cffffd100" .. text .. "|r")
end

local quickSliders = {}
local function quickSlider(suffix, y, lo, hi, step, fmt, get, set)
    local nm = "HardcoreStatTrackerQuick" .. suffix
    local s = CreateFrame("Slider", nm, adjust, "OptionsSliderTemplate")
    s:SetSize(190, 16)
    s:SetPoint("TOP", 0, y)
    s:SetMinMaxValues(lo, hi); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
    _G[nm .. "Low"]:SetText(""); _G[nm .. "High"]:SetText("")
    s._fmt, s._get = fmt, get
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        _G[nm .. "Text"]:SetText(fmt(v))
        set(v)
    end)
    quickSliders[#quickSliders + 1] = s
    return s
end

quickHeader("Mini Panel", -32)
quickSlider("MiniScale", -58, 0.7, 2.0, 0.1,
    function(v) return ("Scale: %.1f"):format(v) end,
    function() return HC.db and HC.db.scale or 1 end,
    function(v) HC.db.scale = v; HC:UpdateDisplay() end)
quickSlider("MiniFont", -96, 9, 20, 1,
    function(v) return "Text size: " .. v end,
    function() return HC.db and HC.db.fontSize or 12 end,
    function(v) HC.db.fontSize = v; HC:UpdateDisplay() end)
quickSlider("MiniAlpha", -134, 0.2, 1, 0.05,
    function(v) return ("Background: %.0f%%"):format(v * 100) end,
    function() return HC.db and HC.db.miniAlpha or 0.8 end,
    function(v) HC.db.miniAlpha = v; if HC.ApplyMiniAlpha then HC:ApplyMiniAlpha() end end)

quickHeader("Full Window", -168)
quickSlider("FullScale", -194, 0.7, 1.6, 0.05,
    function(v) return ("Scale: %.2f"):format(v) end,
    function() return HC.db and HC.db.fullScale or 1 end,
    function(v) HC.db.fullScale = v; full:SetScale(v) end)
quickSlider("FullAlpha", -232, 0.2, 1, 0.05,
    function(v) return ("Background: %.0f%%"):format(v * 100) end,
    function() return HC.db and HC.db.fullAlpha or 0.97 end,
    function(v) HC.db.fullAlpha = v; full:SetBackdropColor(0.05, 0.04, 0.04, v) end)

function HC:ToggleFullAdjust()
    if adjust:IsShown() then adjust:Hide(); return end
    for _, s in ipairs(quickSliders) do
        local v = s._get()
        s:SetValue(v)
        _G[s:GetName() .. "Text"]:SetText(s._fmt(v))
    end
    adjust:ClearAllPoints()
    local p = HC.db and HC.db.adjustPoint
    if p then adjust:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else adjust:SetPoint("CENTER") end
    adjust:Show()
end
displayBtn:SetScript("OnClick", function() HC:ToggleFullAdjust() end)

local divider = full:CreateTexture(nil, "ARTWORK")
divider:SetColorTexture(0.6, 0.1, 0.1, 0.8)
divider:SetPoint("TOPLEFT", PAD, -58)
divider:SetPoint("TOPRIGHT", -PAD, -58)
divider:SetHeight(1)

-- Tab bar (Combat / World / Account) under the divider. RefreshFull only renders
-- the active tab's sections, so the window stays short.
do
    local gap = 4
    local tw = (FULL_W - PAD * 2 - gap * (#FULL_TABS - 1)) / #FULL_TABS
    for i, t in ipairs(FULL_TABS) do
        local b = HC.MakeButton(full, t.name, tw, 21)
        b:SetPoint("TOPLEFT", PAD + (i - 1) * (tw + gap), -64)
        b:SetScript("OnClick", function()
            if HC.db then HC.db.fullTab = i end
            HC:RefreshFull()
        end)
        tabButtons[i] = b
    end
end

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
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("TOPLEFT", 2, -3)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.left:SetFont(STDFONT, 11, "")    -- quiet labels...
    r.left:SetJustifyH("LEFT")
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetFont(STDFONT, 13, "")   -- ...loud numbers
    r.right:SetPoint("TOPRIGHT", -4, -3)
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

    -- Records set in the last 30 minutes get celebrated: warm gold row + tag.
    local stamp = HC.db.recordStamps and HC.db.recordStamps[item.key]
    local fresh = stamp and (time() - stamp) < 1800
    if fresh then
        r.bg:SetColorTexture(1, 0.72, 0.1, 0.12)
        r.left:SetText(sd.label .. "  |cffffe080new!|r")
    else
        r.bg:SetColorTexture(1, 1, 1, shade and 0.09 or 0.03)
        r.left:SetText(sd.label)
    end

    r.icon:Show(); r.icon:SetTexture(item.icon)
    r.left:ClearAllPoints(); r.left:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, -1)
    local lc = sd.color
    if lc then r.left:SetTextColor(lc[1], lc[2], lc[3]) else r.left:SetTextColor(1, 1, 1) end
    -- Zeroes read as noise, not achievements - dim them so real records pop.
    local zero = (sd.value == "0" or sd.value == "0s" or sd.value == "0m")
    r.right:SetText(((sd.dim or zero) and "|cff777777" or "|cffffd100") .. sd.value .. "|r")
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

    local a, lt = HC.LiveAlive(), HC.LiveLevelTime()
    if a then
        local t = "|cff4dff4dAlive: " .. FmtPlayed(a) .. "|r"
        if lt then t = t .. "   |cff888888this level: " .. FmtPlayed(lt) .. "|r" end
        aliveLine:SetText(t)
    else
        aliveLine:SetText("")
    end

    local resets = HC.db.resets or 0
    local audit = ("|cff888888Stat resets:|r |cffffd100%d|r"):format(resets)
    if HC.db.tamperedEver then
        audit = audit .. "      |cffff3333! values edited outside the game|r"
    end
    auditText:SetText(audit)

    local d = HC:StatData()
    local colGap = 12
    local colW = (FULL_W - PAD * 2 - colGap) / 2
    local colX = { PAD, PAD + colW + colGap }
    local y, idx = -HEADER_H, 0

    -- Active tab: only its sections render; the tab button is shown "pressed".
    local tab = HC.db.fullTab or 1
    if tab < 1 or tab > #FULL_TABS then tab = 1 end
    for ti, b in ipairs(tabButtons) do
        b:SetSelected(ti == tab)
    end
    local activeSections = FULL_TABS[tab].sections

    -- Sections that are pure noise for this character get skipped entirely.
    local function SectionRelevant(name)
        if name == "Pet" then
            local _, class = UnitClass("player")
            return class == "HUNTER" or class == "WARLOCK"
                or (HC.db.petDeaths or 0) > 0 or (HC.db.petKillingBlows or 0) > 0 or UnitExists("pet")
        end
        if name == "Mak'gora (account-wide)" then
            return HC.adb ~= nil
                and ((HC.adb.makgoraWon or 0) > 0 or (HC.adb.makgoraLost or 0) > 0)
        end
        if name == "Healing" then
            return (HC.db.healingDone or 0) > 0 or (HC.db.biggestHeal or 0) > 0
                or (HC.db.playersSaved or 0) > 0
        end
        return true
    end

    -- Walk the layout: each header spans full width; its stats flow into 2 balanced columns.
    local i = 1
    while i <= #FULL_LAYOUT do
        local item = FULL_LAYOUT[i]
        if item.header then
            local header = item.header
            i = i + 1
            local items = {}
            while i <= #FULL_LAYOUT and not FULL_LAYOUT[i].header do
                items[#items + 1] = FULL_LAYOUT[i]; i = i + 1
            end
            -- A noise section (Pet/Healing/Mak'gora for off-class chars) is normally
            -- skipped, but if the player put any of its stats on the mini panel we
            -- honor that here - showing ONLY those opted-in stats, not the whole
            -- (mostly-zero) section. Relevant sections still show everything.
            local shown = items
            if not SectionRelevant(header) then
                shown = {}
                for _, it in ipairs(items) do
                    if HC:Visible(it.key) then shown[#shown + 1] = it end
                end
            end
            if activeSections[header] and #shown > 0 then
                if idx > 0 then y = y - 6 end  -- breathing room between sections
                idx = idx + 1
                StyleHeader(GetRow(idx), header, y, FULL_W - PAD * 2)
                y = y - 21
                -- Two independent columns: each stat drops into whichever column is
                -- currently shorter, so a tall (sub-line) cell never leaves a gap
                -- beside a short one. Stays L/R-ordered when heights match.
                local yL, yR = y, y
                local sL, sR = false, false
                for _, it in ipairs(shown) do
                    idx = idx + 1
                    if yL >= yR then
                        sL = not sL
                        local h = StyleStat(GetRow(idx), it, colX[1], yL, colW, d, sL)
                        yL = yL - h - 2
                    else
                        sR = not sR
                        local h = StyleStat(GetRow(idx), it, colX[2], yR, colW, d, sR)
                        yR = yR - h - 2
                    end
                end
                y = math.min(yL, yR)
            end
        else
            i = i + 1
        end
    end
    for j = idx + 1, #fullRows do fullRows[j]:Hide() end

    local footerY = y - 6
    displayBtn:ClearAllPoints()
    displayBtn:SetPoint("TOPLEFT", PAD + 6, footerY - 10)
    cfgBtn:ClearAllPoints()
    cfgBtn:SetPoint("TOPRIGHT", -PAD - 6, footerY - 10)
    auditFrame:ClearAllPoints()
    auditFrame:SetPoint("LEFT", displayBtn, "RIGHT", 4, 0)
    auditFrame:SetPoint("RIGHT", cfgBtn, "LEFT", -4, 0)
    full:SetHeight(-footerY + 48)   -- extra padding below the footer buttons
end

function HC:ToggleFull()
    if full:IsShown() then full:Hide(); return end
    local p = HC.db and HC.db.fullPoint
    full:ClearAllPoints()
    if p and p[1] == "TOP" then
        full:SetPoint("TOP", UIParent, "TOP", p[3], p[4])   -- top-anchored: top edge stays put
    else
        full:SetPoint("TOP", UIParent, "TOP", 0, -100)      -- default / migrate old center anchor
    end
    full:SetBackdropColor(0.05, 0.04, 0.04, (HC.db and HC.db.fullAlpha) or 0.97)
    full:SetScale((HC.db and HC.db.fullScale) or 1)
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
