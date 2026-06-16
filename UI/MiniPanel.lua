local ADDON, HC = ...

local Comma, FmtTime, FmtDiff, FmtShort, FmtSec, FmtPlayed = HC.Comma, HC.FmtTime, HC.FmtDiff, HC.FmtShort, HC.FmtSec, HC.FmtPlayed
-- The mini panel is tight, so numbers there are abbreviated (1k / 1.5k / 1.2M).
local Num = HC.FmtNum
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

-- Panel mode uses the bordered tooltip backdrop. Bar mode drops the chunky border
-- for a clean full-width strip, whose background is a plain texture (more reliable
-- than a borderless backdrop table on a thin frame).
local PANEL_BACKDROP = {
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
HC.frame.barBG = HC.frame:CreateTexture(nil, "BACKGROUND")
HC.frame.barBG:SetAllPoints()
HC.frame.barBG:Hide()

-- Applies the saved mini-panel opacity (called on login and from the slider).
-- Panel uses the backdrop fill; bar uses the full-width strip (barBG) and keeps the
-- inset backdrop fill transparent, so there aren't two stacked backgrounds.
function HC:ApplyMiniAlpha()
    local a = (HC.db and HC.db.miniAlpha) or 0.8
    local bar = HC.db and HC.db.miniMode == "bar"
    HC.frame:SetBackdropColor(0.05, 0.04, 0.04, bar and 0 or a)
    HC.frame.barBG:SetColorTexture(0.05, 0.04, 0.04, a)
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

-- ---------------------------------------------------------------------------
-- Bar mode (full-width, Titan-style): a row of horizontal segments instead of
-- the stacked box. Reuses HC.STATS / HC.ICONS / HC.STAT_HELP. See HC:UpdateBar.
-- ---------------------------------------------------------------------------
local barSegs   = {}                                   -- horizontal stat segments
local measureFS = HC.frame:CreateFontString(nil, "OVERLAY")  -- hidden, for width measuring
measureFS:Hide()
local brand, moreBtn, openBtn                           -- skull identity, overflow chip, custom open button (lazy)

local function TipAnchor() return "ANCHOR_BOTTOM" end   -- bar is always at the top, so tooltips hang below

local function CreateBarSeg()
    local s = CreateFrame("Button", nil, HC.frame)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.icon:SetPoint("LEFT", 0, 0)
    s.text = s:CreateFontString(nil, "OVERLAY")
    s.text:SetPoint("LEFT", s.icon, "RIGHT", 3, 0)
    s.text:SetJustifyH("LEFT")
    s.sep = s:CreateTexture(nil, "ARTWORK")
    s.sep:SetColorTexture(0.6, 0.1, 0.1, 0.5)
    s.sep:SetWidth(1)
    s:SetScript("OnEnter", function(self)
        if not self._key then return end
        GameTooltip:SetOwner(self, TipAnchor())
        GameTooltip:AddLine(self._label or "", 1, 0.82, 0)
        if self._value then GameTooltip:AddLine(self._value, 1, 1, 1) end
        local help = HC.STAT_HELP[self._key]
        if help then GameTooltip:AddLine(help, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    s:SetScript("OnClick", function() HC:ToggleFull() end)
    barSegs[#barSegs + 1] = s
    return s
end
local function GetBarSeg(i) barSegs[i] = barSegs[i] or CreateBarSeg(); return barSegs[i] end

local function EnsureBrand()
    if brand then return brand end
    brand = CreateFrame("Button", nil, HC.frame)
    brand.icon = brand:CreateTexture(nil, "ARTWORK")
    brand.icon:SetAllPoints()
    brand.icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    brand.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    brand:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    brand:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, TipAnchor())
        GameTooltip:AddLine("Hardcore Stat Tracker", 1, 0.27, 0.27)
        GameTooltip:AddLine("Click: full window    Right-click: settings", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    brand:SetScript("OnLeave", function() GameTooltip:Hide() end)
    brand:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then if HC.OpenOptions then HC:OpenOptions() end
        else HC:ToggleFull() end
    end)
    return brand
end

-- Custom themed open button (matches the full window's buttons). The clear way to
-- open the full window: top-right on the panel, right side on the bar.
local function EnsureOpen()
    if openBtn then return openBtn end
    openBtn = HC.MakeButton(HC.frame, "+", 22, 18)
    openBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    openBtn:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then if HC.OpenOptions then HC:OpenOptions() end
        else HC:ToggleFull() end
    end)
    openBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, TipAnchor())
        GameTooltip:AddLine("Hardcore Stat Tracker", 1, 0.27, 0.27)
        GameTooltip:AddLine("Click: full window    Right-click: settings", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    openBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return openBtn
end

local function EnsureMore()
    if moreBtn then return moreBtn end
    moreBtn = CreateFrame("Button", nil, HC.frame)
    moreBtn.text = moreBtn:CreateFontString(nil, "OVERLAY")
    moreBtn.text:SetPoint("LEFT", 0, 0)
    moreBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, TipAnchor())
        GameTooltip:AddLine("More stats", 1, 0.82, 0)
        for _, line in ipairs(self._list or {}) do GameTooltip:AddLine(line, 1, 1, 1) end
        GameTooltip:Show()
    end)
    moreBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    moreBtn:SetScript("OnClick", function() HC:ToggleFull() end)
    return moreBtn
end

-- Marching-ants highlight: a dashed gold border that animates around a row for
-- a few seconds after it sets a new record, so a glance shows what just changed.
local ANTS_DASH   = "Interface\\AddOns\\HardcoreStatTracker\\Media\\"
local ANTS_TILE   = 8     -- dash texture is 8px along its run
local ANTS_FRESH  = 15    -- seconds a new record stays highlighted
local ANTS_SPEED  = 0.9   -- texcoord units marched per second
local ANTS_THICK  = 2
local ANTS_MX     = 3     -- horizontal gap between the dashed border and content
local ANTS_MY     = 1     -- vertical gap (tighter top/bottom)
local antsOffset  = 0

local function EnsureAnts(r)
    if r.ants then return r.ants end
    local function mk(vert)
        local t = r:CreateTexture(nil, "OVERLAY")
        t:SetTexture(ANTS_DASH .. (vert and "dash_v" or "dash_h"), "REPEAT", "REPEAT")
        t:SetVertexColor(1, 0.82, 0)
        t:Hide()
        return t
    end
    local top, bottom, left, right = mk(false), mk(false), mk(true), mk(true)
    local MX, MY = ANTS_MX, ANTS_MY   -- push the border out so it doesn't crowd the content
    top:SetPoint("TOPLEFT", -MX, MY);        top:SetPoint("TOPRIGHT", MX, MY);         top:SetHeight(ANTS_THICK)
    bottom:SetPoint("BOTTOMLEFT", -MX, -MY); bottom:SetPoint("BOTTOMRIGHT", MX, -MY);  bottom:SetHeight(ANTS_THICK)
    left:SetPoint("TOPLEFT", -MX, MY);       left:SetPoint("BOTTOMLEFT", -MX, -MY);    left:SetWidth(ANTS_THICK)
    right:SetPoint("TOPRIGHT", MX, MY);      right:SetPoint("BOTTOMRIGHT", MX, -MY);   right:SetWidth(ANTS_THICK)
    r.ants = { top, bottom, left, right }
    return r.ants
end

local function HideAnts(r)
    if r.ants then for _, t in ipairs(r.ants) do t:Hide() end end
end

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
    -- Bar mode is edge-anchored, not draggable.
    if button == "LeftButton" and not (HC.db and (HC.db.locked or HC.db.miniMode == "bar")) then
        self.moving = true
        self:StartMoving()
    end
end)
HC.frame:SetScript("OnMouseUp", function(self) StopDrag(self) end)
HC.frame:SetScript("OnHide", StopDrag)

function HC.RestorePosition()
    HC.frame:ClearAllPoints()
    if HC.db and HC.db.miniMode == "bar" then
        -- Full width via a SINGLE anchor + explicit width (a frame sized by two
        -- opposing anchors doesn't give its backdrop a real size, so the bg came
        -- out invisible). TitanPanel exposes anchor frames at the edge of its bar
        -- stack, so hang off those to auto-stack clear of it; else the screen edge.
        local off = HC.db.barOffset or 0
        HC.frame:SetWidth(UIParent:GetWidth())
        local a = _G.TitanPanelTopAnchor
        local rel = (a and a:IsShown()) and a or UIParent
        local rp  = (rel == UIParent) and "TOPLEFT" or "BOTTOMLEFT"
        HC.frame:SetPoint("TOPLEFT", rel, rp, 0, -off)
    else
        local p = (HC.db and HC.db.point) or LAYOUT_DEFAULTS.point
        HC.frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
end

-- Switch panel/bar mode: drag + clamp + scale differ, then re-anchor & redraw.
-- Called on login and whenever a bar setting changes in the options page.
function HC:ApplyMiniMode()
    local bar = HC.db and HC.db.miniMode == "bar"
    HC.frame:SetMovable(not bar)
    HC.frame:SetClampedToScreen(not bar)
    -- Keep the creation-time backdrop; bar mode just hides its border (the fill is
    -- coloured by ApplyMiniAlpha). barBG stays as a belt-and-suspenders backup.
    if bar then
        HC.frame.barBG:Show()
        HC.frame:SetBackdropBorderColor(0, 0, 0, 0)
        HC.frame:SetScale(1)
    else
        HC.frame.barBG:Hide()
        HC.frame:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)
    end
    HC:ApplyMiniAlpha()                    -- colours the strip / backdrop for the mode
    HC.RestorePosition()
    HC:UpdateDisplay()
    if HC.ApplyScreenAdjust then HC:ApplyScreenAdjust() end
end

-- Screen adjust: a TOP bar covers the minimap, so push the minimap cluster down to
-- sit just below the bar (buffs + quest tracker hang off it in Classic, so they
-- follow). See HC:ApplyScreenAdjust below for the taint-safe approach.
local mmBaseline, mmLastX, mmLastY
local function MinimapFollowBar()
    local mc = _G.MinimapCluster
    if not mc then return end
    if not (HC.db and HC.db.miniMode == "bar" and HC.db.barScreenAdjust) then return end
    -- Anchor to UIParent at the bar's live bottom, preserving the minimap's own
    -- horizontal offset (screen geometry auto-accounts for TitanPanel above us).
    local barBottom, uiTop = HC.frame:GetBottom(), UIParent:GetTop()
    if not (barBottom and uiTop) then return end
    local x = (mmBaseline and mmBaseline[1] and mmBaseline[1][4]) or 0
    local y = (barBottom - uiTop) - 2
    if x == mmLastX and y == mmLastY then return end
    mmLastX, mmLastY = x, y
    mc:ClearAllPoints()
    mc:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", x, y)
end

-- Taint-safe screen adjust. We do NOT hook UIParent_ManageFramePositions or write
-- the global UIPARENT_MANAGED_FRAME_POSITIONS table or call SetAttribute - all of
-- those run/poke insecure data on the secure frame-management path and taint it
-- (which blocked the LFG browse's protected Search()). Instead we only set the plain
-- `ignoreFramePositionManager` field (a non-protected frame, exactly as TitanPanel
-- does) so Blizzard leaves the minimap alone, then SetPoint it. It re-applies on
-- login, settings changes, and PLAYER_ENTERING_WORLD / DISPLAY_SIZE_CHANGED.
function HC:ApplyScreenAdjust()
    local mc = _G.MinimapCluster
    if not mc then return end
    local on = HC.db and HC.db.miniMode == "bar" and HC.db.barScreenAdjust
    if on then
        if not mmBaseline then
            mmBaseline = {}
            for i = 1, mc:GetNumPoints() do mmBaseline[i] = { mc:GetPoint(i) } end
        end
        if mc.SetDontSavePosition then mc:SetDontSavePosition(true) end
        mc.ignoreFramePositionManager = true
        if _G.TitanMovable_AddonAdjust then _G.TitanMovable_AddonAdjust("MinimapCluster", true) end
        MinimapFollowBar()
    elseif mmBaseline then
        -- Hand the minimap back to Blizzard / TitanPanel.
        mmLastX, mmLastY = nil, nil
        mc.ignoreFramePositionManager = nil
        mc:ClearAllPoints()
        for _, p in ipairs(mmBaseline) do mc:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0) end
        mmBaseline = nil
        if _G.TitanMovable_AddonAdjust then _G.TitanMovable_AddonAdjust("MinimapCluster", false) end
        if _G.TitanPanel_AdjustFrames then _G.TitanPanel_AdjustFrames(true, "HST released minimap") end
    end
end

-- Re-assert bar anchoring + screen adjust after the UI (re)lays out.
local barEvents = CreateFrame("Frame")
barEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
barEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
barEvents:SetScript("OnEvent", function()
    if HC.db and HC.db.miniMode == "bar" then
        HC.RestorePosition()
        if HC.ApplyScreenAdjust then HC:ApplyScreenAdjust() end
    end
end)

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
        if HC.db.lowestPct then return math.floor(HC.db.lowestPct) .. "% (" .. Num(HC.db.lowestHP) .. ")" end end },
    { "nearestDeath", "Nearest Death",  function() return HC.db.closestSeconds and FmtSec(HC.db.closestSeconds) end },
    { "biggestHit",   "Biggest Hit Taken", function() return Num(HC.db.biggestHit) end },
    { "highestCrit",  "Highest Crit",   function() return Num(HC.db.highestCrit) end },
    { "biggestMelee", "Biggest Melee Hit", function() return Num(HC.db.biggestMelee) end },
    { "biggestRanged","Biggest Ranged Hit", function() return Num(HC.db.biggestRanged) end },
    { "biggestSpell", "Biggest Spell Hit", function() return Num(HC.db.biggestSpell) end },
    { "biggestAbility", "Biggest Ability Hit", function() return Num(HC.db.biggestAbility) end },
    { "biggestHeal",  "Biggest Heal",   function() return Num(HC.db.biggestHeal) end },
    { "healingDone",  "Total Healing",  function() return Num(HC.db.healingDone) end },
    { "playersSaved", "Players Saved",  function() return Num(HC.db.playersSaved) end },
    { "toughestFoe",  "Toughest Foe",   function() return HC.db.biggestLevelDiff and (FmtDiff(HC.db.biggestLevelDiff) .. " lvl") end },
    { "highestFall",  "Highest Fall",   function()
        if HC.db.highestFallPct then return math.floor(HC.db.highestFallPct) .. "%" end
        return HC.db.highestFall and Num(HC.db.highestFall) end },
    { "longestFight", "Longest Fight",  function() return FmtTime(HC.db.longestFight) end },
    { "mostDmgFight", "Most Dmg Taken / Fight", function() return Num(HC.db.mostDmgFight) end },
    { "killingBlows", "Killing Blows",  function() return Num(HC.db.killingBlows) end },
    { "panic",        "Panic Moments",  function() return Num(HC.db.panicMoments) end },
    { "fights",       "Fights Survived", function() return Num(HC.db.fights) end },
    { "currentPet",   "Current Pet",    function()
        if UnitExists("pet") and not UnitIsDead("pet") then return UnitName("pet") end end },
    { "petDeaths",    "Pet Deaths",     function() return Num(HC.db.petDeaths) end },
    { "petKillingBlows", "Pet Killing Blows", function() return Num(HC.db.petKillingBlows) end },
    { "partyDeaths",  "Party Deaths",   function() return Num(HC.db.partyDeaths) end },
    { "mostFoes",     "Most Foes at Once", function() return Num(HC.db.mostFoes) end },
    { "clutchSaves",  "Clutch Saves",   function() return Num(HC.db.clutchSaves) end },
    { "untouched",    "Untouched Streak", function() return FmtTime(HC.db.untouched) end },
    { "dmgTaken",     "Total Dmg Taken", function() return Num(HC.db.dmgTaken) end },
    { "dmgDone",      "Total Dmg Done", function() return Num(HC.db.dmgDone) end },
    { "quests",       "Quests Completed", function() return Num(HC.db.quests) end },
    { "zones",        "Zones Explored", function() return Num(HC.db.zones) end },
    { "jumps",        "Jumps",          function() return Num(HC.db.jumps) end },
    { "highestLevel", "Highest Level",  function() return Num(HC.adb and HC.adb.highestLevel) end },
    { "level60s",     "Level 60s",      function() return Num(HC.adb and HC.adb.level60s) end },
    { "drowned",      "Drowned",        function() return Num(HC.adb and HC.adb.drowned) end },
    { "makgoraWon",   "Mak'gora Won",   function() return Num(HC.adb and HC.adb.makgoraWon) end },
    { "makgoraLost",  "Mak'gora Lost",  function() return Num(HC.adb and HC.adb.makgoraLost) end },
    { "buffsGiven",   "Buffs Given",    function() return Num(HC.db.buffsGiven) end },
    { "goldEarned",   "Gold Earned",    function() return GetCoinTextureString(HC.db.goldEarned or 0) end },
    { "goldSpent",    "Gold Spent",     function() return GetCoinTextureString(HC.db.goldSpent or 0) end },
    { "goldLooted",   "Gold Looted",    function() return GetCoinTextureString(HC.db.goldLooted or 0) end },
    { "bagsLooted",   "Bags Looted",    function() return Num(HC.db.bagsLooted) end },
}

-- Stats grouped by category (mirrors the full window's sections). Used by the
-- settings "Mini Panel" page to lay the visibility toggles out by theme.
HC.STAT_GROUPS = {
    { "Survival",  { "closestCall", "nearestDeath", "biggestHit", "highestFall", "panic",
                     "clutchSaves", "untouched", "mostFoes", "fights", "dmgTaken" } },
    { "Combat",    { "highestCrit", "biggestMelee", "biggestRanged", "biggestSpell", "biggestAbility",
                     "killingBlows", "dmgDone", "longestFight", "mostDmgFight", "toughestFoe" } },
    { "Healing",   { "biggestHeal", "healingDone", "playersSaved" } },
    { "Pet",       { "currentPet", "petDeaths", "petKillingBlows" } },
    { "Group",     { "partyDeaths", "buffsGiven" } },
    { "Adventure", { "quests", "zones", "jumps" } },
    { "Wealth",    { "goldEarned", "goldSpent", "goldLooted", "bagsLooted" } },
    { "Account",   { "highestLevel", "level60s", "drowned" } },
    { "Mak'gora",  { "makgoraWon", "makgoraLost" } },
    { "Character", { "timeAlive" } },
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
    biggestSpell = ICONP .. "Spell_Fire_FlameBolt",
    biggestAbility = ICONP .. "Ability_Warrior_SavageBlow",
    biggestHeal  = ICONP .. "Spell_Holy_FlashHeal",
    healingDone  = ICONP .. "Spell_Holy_GreaterHeal",
    playersSaved = ICONP .. "Spell_Holy_LayOnHands",
    goldEarned   = ICONP .. "INV_Misc_Coin_01",
    goldSpent    = ICONP .. "INV_Misc_Coin_04",
    goldLooted   = ICONP .. "INV_Misc_Coin_02",
    bagsLooted   = ICONP .. "INV_Misc_Bag_10",
    highestFall  = ICONP .. "Spell_Magic_FeatherFall",
    longestFight = ICONP .. "Ability_DualWield",
    mostDmgFight = ICONP .. "Spell_Fire_Fireball02",
    toughestFoe  = ICONP .. "INV_Misc_Head_Dragon_01",
    killingBlows = ICONP .. "Ability_Rogue_Ambush",
    panic        = ICONP .. "Spell_Shadow_PsychicScream",
    fights       = ICONP .. "Ability_Warrior_Revenge",
    currentPet   = ICONP .. "Ability_Hunter_BeastTaming",
    petDeaths    = ICONP .. "Spell_Nature_Reincarnation",
    petKillingBlows = ICONP .. "Ability_Hunter_KillCommand",
    partyDeaths  = ICONP .. "INV_Misc_Bone_HumanSkull_02",
    mostFoes     = ICONP .. "Ability_Warrior_Challange",
    clutchSaves  = ICONP .. "Spell_Holy_Restoration",
    untouched    = ICONP .. "Ability_Parry",
    dmgTaken     = ICONP .. "Spell_Shadow_ShadowWordPain",
    dmgDone      = ICONP .. "Spell_Fire_Fireball02",
    quests       = ICONP .. "INV_Scroll_08",
    zones        = ICONP .. "INV_Misc_Map_01",
    jumps        = ICONP .. "Ability_Rogue_Sprint",
    makgoraWon   = ICONP .. "INV_Sword_27",
    makgoraLost  = ICONP .. "Ability_Rogue_FeignDeath",
    highestLevel = ICONP .. "Spell_ChargePositive",
    level60s     = ICONP .. "INV_Crown_01",
    drowned      = ICONP .. "INV_Misc_Fish_02",
    buffsGiven   = ICONP .. "Spell_Holy_WordFortitude",
}

-- What each stat means and how it's tracked (full-window hover tooltips).
HC.STAT_HELP = {
    timeAlive    = "Your total /played time on this character - for a hardcore character, that IS your time alive. Server-authoritative, ticks live. The sub-line shows time at your current level.",
    closestCall  = "The lowest health you've ever reached while alive, as a percentage and raw HP. Captured the moment it happens, along with your level, the zone, and what last hit you.",
    nearestDeath = "How close you came to dying, in seconds: your HP at that moment divided by the damage-per-second you were taking (3-second window). Lower is scarier.",
    biggestHit   = "The largest single hit you've survived, with the attacker and ability that dealt it.",
    highestCrit  = "Your biggest critical hit, and what it landed on.",
    biggestMelee = "Your biggest non-crit melee auto-attack hit (white swings only - abilities don't count). Crits go to Highest Crit instead.",
    biggestRanged = "Your biggest non-crit ranged auto-attack hit (bow, gun, or wand). Crits go to Highest Crit. Stays at 0 if you never fire one.",
    biggestSpell = "Your biggest non-crit direct MAGIC spell hit (Fireball, Shadow Bolt, etc.). Physical abilities count as Biggest Ability instead. Crits go to Highest Crit; DoT ticks don't count.",
    biggestAbility = "Your biggest non-crit physical ability hit - Sinister Strike, Raptor Strike, Heroic Strike, Aimed Shot, etc. (the game logs these as spells, but they're physical). Crits go to Highest Crit.",
    biggestHeal  = "Your biggest single direct heal cast, and who it landed on. Heal-over-time ticks don't count.",
    healingDone  = "Every point of effective healing you've done, lifetime (overheal excluded).",
    playersSaved = "Times you landed a direct heal on a party member who was critically low (20% HP or less), pulling them back from the brink. Counted once per close call.",
    goldEarned   = "Every copper earned on this character, lifetime - loot, quest rewards, vendor sales. Spending doesn't reduce it.",
    goldSpent    = "Every copper you've spent on this character, lifetime - vendor purchases, repairs, training, postage, auction deposits. All money going out.",
    goldLooted   = "Coin picked up directly from kills and loot, lifetime - vendor sales and quest rewards don't count.",
    bagsLooted   = "Containers (bags, quivers, pouches) you've looted off corpses and chests - lifetime. Bags bought from a vendor don't count.",
    highestFall  = "The worst fall you've survived, as a share of your max HP at the time (the raw damage is shown too). A 230 fall is trivial at 5000 HP but nearly lethal at 300.",
    longestFight = "Your longest single stretch of combat.",
    mostDmgFight = "The most total damage you've taken within one fight.",
    toughestFoe  = "The biggest level gap above you on an enemy you actually traded blows with (it must be your target while fighting). Skull-level mobs can't be measured.",
    killingBlows = "Kills where your own hit was the killing blow - assists and pet kills don't count.",
    petKillingBlows = "Kills where your pet landed the killing blow. Tracked separately from your own (handy for pet-only challenges).",
    panic        = "Times your health dropped to 20% or below. Counts once per dip and re-arms when you recover above 20%.",
    clutchSaves  = "Fights where you dropped to 10% or below and still won. The earned version of a panic moment.",
    untouched    = "Your longest stretch inside a single fight without taking any damage at all.",
    mostFoes     = "The most separate enemies that damaged you within a single fight.",
    fights       = "Combat sessions you've entered and walked out of alive.",
    dmgTaken     = "Every point of damage this character has ever taken, lifetime - combat, falls, everything.",
    dmgDone      = "Every point of damage you've dealt, lifetime - all your attacks and spells, including damage-over-time.",
    currentPet   = "Your currently active pet.",
    petDeaths    = "Pets that died on your watch. The most recent are listed with your level and the zone.",
    partyDeaths  = "Party or raid members who died near you - witnessed through your combat log, so they must be in range.",
    buffsGiven   = "Buffs you've put on other players (Fortitude, Blessings, a Battle Shout washing over the party...). One count per application per target.",
    quests       = "Quests turned in on this character.",
    zones        = "Distinct zones you've set foot in.",
    jumps        = "How many times you've actually jumped - confirmed you left the ground. No-op presses (stunned/casting), swimming-ascend, and falling off ledges don't count. Just for fun.",
    highestLevel = "The highest level any character on this account has reached. Account-wide.",
    level60s     = "How many of your characters have reached max level (60). Account-wide.",
    drowned      = "How many of your characters have died to drowning. Account-wide.",
    makgoraWon   = "Mak'gora duels won - ACCOUNT-WIDE, persists across all your characters. Auto-detected from system messages; record manually with /hst makgora won.",
    makgoraLost  = "Mak'gora duels lost - ACCOUNT-WIDE, your fallen characters' final duels. Record manually with /hst makgora lost.",
}

function HC:UpdateDisplay()
    if not HC.db then return end
    if HC.db.miniMode == "bar" then return HC:UpdateBar() end
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

    local function addRow(icon, label, value, lr, lg, lb, statKey)
        idx = idx + 1
        local r = GetMiniRow(idx)
        r._statKey = statKey
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
            addRow(HC.ICONS[s[1]], s[2], value, nil, nil, nil, s[1])
        end
    end

    if HC.state.inCombat and HC.db.combatTimer ~= false then
        addRow(HC.ICONS.longestFight, "In Combat " .. FmtTime(GetTime() - HC.state.combatStart),
            "|cffff9900" .. Num(HC.state.curFightDmg) .. "|r", 1, 0.6, 0)
    end

    for j = idx + 1, #miniRows do miniRows[j]:Hide() end

    -- Size the frame to fit, then stretch each row so values right-align.
    local width = math.max(150, contentW + PADX * 2)
    HC.frame:SetWidth(width)
    HC.frame:SetHeight(-y + 8)
    for i = 1, idx do miniRows[i]:SetWidth(width - PADX * 2) end

    -- Make sure bar-mode widgets aren't lingering from a previous mode.
    miniTitle:Show(); miniDivider:Show()
    -- Custom open button at the top-right; the skull identity is bar-only.
    local ob = EnsureOpen()
    ob:ClearAllPoints(); ob:SetPoint("TOPRIGHT", HC.frame, "TOPRIGHT", -6, -6); ob:Show()
    if brand then brand:Hide() end
    if moreBtn then moreBtn:Hide() end
    for _, s in ipairs(barSegs) do s:Hide() end

    HC.frame:SetShown(HC.db.shown)
    if HC.fullFrame and HC.fullFrame:IsShown() then HC:RefreshFull() end
end

-- Bar renderer: a full-width row of horizontal segments. Auto-density picks the
-- richest label tier that fits the screen; overflow spills into a "+N more" tip.
function HC:UpdateBar()
    HC.frame:SetScale(1)
    -- Hide panel-only chrome.
    miniTitle:Hide(); miniDivider:Hide()
    for _, r in ipairs(miniRows) do r:Hide(); HideAnts(r) end

    local fs     = HC.db.fontSize or 12
    local iconSz = fs + 2
    local barH   = fs + 12
    local MARGIN = 8
    local SEP    = 12
    local screenW = UIParent:GetWidth()

    -- No skull on the bar; segments start at the left margin, open button on the right.
    if brand then brand:Hide() end
    local startX = MARGIN

    local ob = EnsureOpen()
    ob:ClearAllPoints(); ob:SetPoint("RIGHT", HC.frame, "RIGHT", -MARGIN, 0); ob:Show()
    local rightReserve = (ob:GetWidth() or 22) + MARGIN + 6

    -- Gather the visible stats. The combat line is kept SEPARATE so entering or
    -- leaving combat never changes the density tier (no jarring resize mid-fight).
    local items = {}
    for _, s in ipairs(HC.STATS) do
        if self:Visible(s[1]) then
            local v = s[3]()
            items[#items + 1] = { key = s[1], label = s[2], icon = HC.ICONS[s[1]], value = v or "--", dash = (v == nil) }
        end
    end
    -- The live in-combat timer is intentionally NOT shown on the bar (it kept the
    -- bar busy); it stays on the stacked mini panel only.

    -- Width of one segment at a density tier: "a" = label+value, "b" = icon+value, "c" = value only.
    measureFS:SetFont(STDFONT, fs, "")
    local function segW(it, tier)
        measureFS:SetText(tier == "a" and (it.label .. "  " .. it.value) or it.value)
        local w = (measureFS:GetStringWidth() or 0) + 10
        if tier ~= "c" then w = w + iconSz + 3 end
        return w
    end

    -- Density tier is chosen from the STATS only (combat line excluded), so it
    -- stays put in and out of combat. Honor a manual choice, else auto-fit.
    local budget = screenW - startX - MARGIN - rightReserve
    local chosen = HC.db.barDensity
    if chosen == nil or chosen == "auto" then
        chosen = "c"
        for _, tier in ipairs({ "a", "b" }) do
            local total = 0
            for _, it in ipairs(items) do total = total + segW(it, tier) + SEP end
            if total <= budget then chosen = tier; break end
        end
    end

    local order = items

    -- Lay out left-to-right until we run out of room; remainder -> "+N more".
    local x, placed = startX, 0
    for i, it in ipairs(order) do
        local w = segW(it, chosen)
        if x + w > screenW - MARGIN - rightReserve then break end
        local seg = GetBarSeg(i)
        seg._key, seg._statKey, seg._label = it.key, it.key, it.label
        seg._value = it.dash and nil or it.value
        if seg._fs ~= fs then seg._fs = fs; seg.text:SetFont(STDFONT, fs, "") end
        seg:ClearAllPoints(); seg:SetPoint("LEFT", HC.frame, "LEFT", x, 0)
        seg:SetSize(w, iconSz)
        if chosen ~= "c" then
            seg.icon:Show(); seg.icon:SetTexture(it.icon); seg.icon:SetSize(iconSz, iconSz)
            seg.text:ClearAllPoints(); seg.text:SetPoint("LEFT", seg.icon, "RIGHT", 3, 0)
        else
            seg.icon:Hide()
            seg.text:ClearAllPoints(); seg.text:SetPoint("LEFT", 0, 0)
        end
        local col = it.combat and "|cffff9900" or (it.dash and "|cff777777" or "|cffffd100")
        local val = col .. it.value .. "|r"
        seg.text:SetText(chosen == "a" and (it.label .. "  " .. val) or val)
        seg.sep:ClearAllPoints(); seg.sep:SetPoint("LEFT", seg, "RIGHT", SEP / 2, 0); seg.sep:SetHeight(iconSz - 2)
        seg.sep:Show()
        seg:Show()
        x, placed = x + w + SEP, i
    end

    -- Overflow indicator + hide leftover segments.
    if placed < #order then
        local m = EnsureMore()
        if m._fs ~= fs then m._fs = fs; m.text:SetFont(STDFONT, fs, "") end
        m.text:SetText(("|cffaaaaaa+%d more|r"):format(#order - placed))
        m._list = {}
        for i = placed + 1, #order do m._list[#m._list + 1] = order[i].label .. ":  " .. order[i].value end
        m:ClearAllPoints(); m:SetPoint("LEFT", HC.frame, "LEFT", x, 0)
        m:SetSize((m.text:GetStringWidth() or 30) + 6, iconSz); m:Show()
        if placed > 0 then barSegs[placed].sep:Hide() end   -- no divider before "+N more"
    elseif moreBtn then
        moreBtn:Hide()
        if placed > 0 then barSegs[placed].sep:Hide() end    -- last segment needs no trailing divider
    end
    for j = placed + 1, #barSegs do barSegs[j]:Hide() end

    HC.frame:SetHeight(barH)
    HC.frame:SetShown(HC.db.shown)
    if HC.fullFrame and HC.fullFrame:IsShown() then HC:RefreshFull() end
end

-- Drive the marching-ants highlight: scroll the dashes on any row whose stat set
-- a record within the last ANTS_FRESH seconds. Throttled; idles when nothing fresh.
local antsAnimator = CreateFrame("Frame", nil, HC.frame)
local antsAccum = 0
local antsShown = false
antsAnimator:SetScript("OnUpdate", function(_, elapsed)
    antsAccum = antsAccum + elapsed
    if antsAccum < 0.03 then return end
    local dt = antsAccum
    antsAccum = 0
    -- Idle fast path: nothing can be highlighted unless a record was set within
    -- the last ANTS_FRESH seconds. Skip the per-row work entirely otherwise.
    local on = HC.db and HC.db.miniHighlight ~= false
        and HC.lastRecordStamp and (time() - HC.lastRecordStamp) < ANTS_FRESH
    if not on then
        if antsShown then
            for _, pool in ipairs({ miniRows, barSegs }) do
                for _, r in ipairs(pool) do HideAnts(r) end
            end
            antsShown = false
        end
        return
    end
    antsShown = true
    antsOffset = (antsOffset + dt * ANTS_SPEED) % 1
    local stamps, now = HC.db.recordStamps, time()
    for _, pool in ipairs({ miniRows, barSegs }) do
        for _, r in ipairs(pool) do
            local stamp = r._statKey and stamps and stamps[r._statKey]
            if r:IsShown() and stamp and (now - stamp) < ANTS_FRESH then
                local a = EnsureAnts(r)
                local rw = (r:GetWidth()  or 0) / ANTS_TILE
                local rh = (r:GetHeight() or 0) / ANTS_TILE
                a[1]:SetTexCoord( antsOffset,  antsOffset + rw, 0, 1)   -- top
                a[2]:SetTexCoord(-antsOffset, -antsOffset + rw, 0, 1)   -- bottom
                a[3]:SetTexCoord(0, 1, -antsOffset, -antsOffset + rh)   -- left
                a[4]:SetTexCoord(0, 1,  antsOffset,  antsOffset + rh)   -- right
                for _, t in ipairs(a) do t:Show() end
            else
                HideAnts(r)
            end
        end
    end
end)

-- (The opener is the skull "brand" button - top-right in panel mode, left on the
-- bar - created lazily via EnsureBrand and positioned by the renderers.)

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
