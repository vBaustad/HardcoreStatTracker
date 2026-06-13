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

    if HC.db.highestFall then
        d.highestFall = { label = "Highest Fall", value = Comma(HC.db.highestFall),
            notes = { string.format("level %s in %s", tostring(HC.db.highestFallLevel or "?"),
                HC.db.highestFallZone or "?") } }
    else d.highestFall = { label = "Highest Fall", value = "--", dim = true } end

    d.longestFight = { label = "Longest Fight",  value = FmtTime(HC.db.longestFight) }
    d.mostDmgFight = { label = "Most Dmg / Fight", value = Comma(HC.db.mostDmgFight) }

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
    d.quests      = { label = "Quests Completed", value = Comma(HC.db.quests) }
    d.zones       = { label = "Zones Explored", value = Comma(HC.db.zones) }
    d.makgoraWon  = { label = "Mak'gora Won", value = Comma(HC.adb and HC.adb.makgoraWon) }
    d.makgoraLost = { label = "Mak'gora Lost", value = Comma(HC.adb and HC.adb.makgoraLost) }
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

local function SaveFullPos()
    local p, _, rp, x, y = full:GetPoint()
    if p and HC.db then HC.db.fullPoint = { p, rp, math.floor(x), math.floor(y) } end
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
local FULL_W, PAD, HEADER_H, ROW_BASE = 540, 12, 50, 24
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
fullTitle:SetText("|cffff4444Hardcore Stat Tracker|r")

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

-- Background-opacity slider, in the footer next to Settings.
local alphaSlider = CreateFrame("Slider", "HardcoreStatTrackerFullAlpha", full, "OptionsSliderTemplate")
alphaSlider:SetSize(140, 16)
alphaSlider:SetMinMaxValues(0.2, 1)
alphaSlider:SetValueStep(0.05)
alphaSlider:SetObeyStepOnDrag(true)
_G["HardcoreStatTrackerFullAlphaLow"]:SetText("")
_G["HardcoreStatTrackerFullAlphaHigh"]:SetText("")
_G["HardcoreStatTrackerFullAlphaText"]:SetText("|cff888888Background|r")
alphaSlider:SetScript("OnValueChanged", function(_, v)
    if HC.db then HC.db.fullAlpha = v end
    full:SetBackdropColor(0.05, 0.04, 0.04, v)
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
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("TOPLEFT", 2, -3)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.left:SetFont(STDFONT, 11, "")    -- quiet labels...
    r.left:SetJustifyH("LEFT")
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetFont(STDFONT, 15, "")   -- ...loud numbers
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

    local d = HC:StatData()
    local colGap = 12
    local colW = (FULL_W - PAD * 2 - colGap) / 2
    local colX = { PAD, PAD + colW + colGap }
    local y, idx, shade = -HEADER_H, 0, false

    -- Sections that are pure noise for this character get skipped entirely.
    local function SectionRelevant(name)
        if name == "Pet" then
            local _, class = UnitClass("player")
            return class == "HUNTER" or class == "WARLOCK"
                or (HC.db.petDeaths or 0) > 0 or UnitExists("pet")
        end
        if name == "Mak'gora (account-wide)" then
            return HC.adb ~= nil
                and ((HC.adb.makgoraWon or 0) > 0 or (HC.adb.makgoraLost or 0) > 0)
        end
        return true
    end

    -- Walk the layout: each header spans full width; its rows pair into 2 columns.
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
            if SectionRelevant(header) then
                if idx > 0 then y = y - 6 end  -- breathing room between sections
                idx = idx + 1
                StyleHeader(GetRow(idx), header, y, FULL_W - PAD * 2)
                y = y - 21
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
            end
        else
            i = i + 1
        end
    end
    for j = idx + 1, #fullRows do fullRows[j]:Hide() end

    local footerY = y - 6
    alphaSlider:ClearAllPoints()
    alphaSlider:SetPoint("TOPLEFT", PAD + 8, footerY - 14)   -- label sits above the track
    cfgBtn:ClearAllPoints()
    cfgBtn:SetPoint("TOPRIGHT", -PAD - 6, footerY - 10)
    full:SetHeight(-footerY + 42)
end

function HC:ToggleFull()
    if full:IsShown() then full:Hide(); return end
    local p = HC.db and HC.db.fullPoint
    full:ClearAllPoints()
    if p then full:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else full:SetPoint("CENTER") end
    local a = (HC.db and HC.db.fullAlpha) or 0.97
    full:SetBackdropColor(0.05, 0.04, 0.04, a)
    alphaSlider:SetValue(a)
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
