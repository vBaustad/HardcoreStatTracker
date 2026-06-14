local ADDON, HC = ...

local Comma, FmtPlayed = HC.Comma, HC.FmtPlayed

-- 1 -> "1st", 2 -> "2nd", 11 -> "11th", etc.
local function Ordinal(n)
    n = n or 0
    local s = tostring(n)
    local t2 = n % 100
    if t2 >= 11 and t2 <= 13 then return s .. "th" end
    local t = n % 10
    if t == 1 then return s .. "st" elseif t == 2 then return s .. "nd"
    elseif t == 3 then return s .. "rd" else return s .. "th" end
end

-- A "trophy case" memorial: shown once when the character dies (and via
-- /hst memorial). Summarizes the run - who they were, how long they lasted,
-- what felled them, a few headline records, and the account's death tally.
function HC:ShowMemorial()
    if not HC.db then return end
    local w = HC.memorialFrame
    if not w then
        w = CreateFrame("Frame", "HardcoreStatTrackerMemorial", UIParent, "BackdropTemplate")
        w:SetSize(380, 120)  -- height set after the body lays out
        w:SetPoint("CENTER", 0, 80)
        w:SetFrameStrata("FULLSCREEN_DIALOG")
        w:SetClampedToScreen(true)
        w:EnableMouse(true); w:SetMovable(true)
        w:RegisterForDrag("LeftButton")
        w:SetScript("OnDragStart", function(self) self:StartMoving() end)
        w:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        w:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        w:SetBackdropColor(0.04, 0.03, 0.03, 0.97)
        w:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)
        tinsert(UISpecialFrames, "HardcoreStatTrackerMemorial")  -- Escape closes
        HC.memorialFrame = w

        local icon = w:CreateTexture(nil, "ARTWORK")
        icon:SetSize(34, 34); icon:SetPoint("TOP", 0, -12)
        icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -50)
        title:SetText("|cffff4444In Memoriam|r")

        local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        close:SetScript("OnClick", function() w:Hide() end)

        w.body = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        w.body:SetPoint("TOP", 0, -76)
        w.body:SetWidth(346); w.body:SetJustifyH("CENTER"); w.body:SetSpacing(4)

        local fullBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        fullBtn:SetSize(120, 22)
        fullBtn:SetPoint("BOTTOMLEFT", 20, 14)
        fullBtn:SetText("View Full Stats")
        fullBtn:SetScript("OnClick", function() if HC.ToggleFull then HC:ToggleFull() end end)

        local shareBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        shareBtn:SetSize(90, 22)
        shareBtn:SetPoint("BOTTOM", 0, 14)
        shareBtn:SetText("Share")
        shareBtn:SetScript("OnClick", function() if HC.ShareStats then HC:ShareStats() end end)

        local okBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        okBtn:SetSize(90, 22)
        okBtn:SetPoint("BOTTOMRIGHT", -20, 14)
        okBtn:SetText("Close")
        okBtn:SetScript("OnClick", function() w:Hide() end)
    end

    -- Populate for the current character.
    local name = UnitName("player") or "?"
    local className, classFile = UnitClass("player")
    local c = (RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]) or { r = 1, g = 1, b = 1 }
    local nameCol = ("|cff%02x%02x%02x%s|r"):format(
        math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), name)
    local alive  = HC.LiveAlive and HC.LiveAlive()
    local killer = HC.state and HC.state.lastHitBy
    local zone   = GetRealZoneText() or GetZoneText() or "?"
    local deaths = (HC.adb and HC.adb.deaths) or 1

    local lines = {}
    lines[#lines + 1] = "Here lies " .. nameCol
    lines[#lines + 1] = ("|cffffd100Level %d %s|r"):format(UnitLevel("player") or 0, className or "")
    if alive then lines[#lines + 1] = "|cff4dff4dSurvived " .. FmtPlayed(alive) .. "|r" end
    lines[#lines + 1] = "|cffcccccc" .. (killer and ("Felled by " .. killer) or "Fallen") .. " in " .. zone .. "|r"
    lines[#lines + 1] = " "

    local rec = {}
    if HC.db.lowestPct          then rec[#rec + 1] = ("closest call %d%% HP"):format(math.floor(HC.db.lowestPct)) end
    if (HC.db.highestCrit or 0) > 0 then rec[#rec + 1] = "biggest crit " .. Comma(HC.db.highestCrit) end
    if (HC.db.killingBlows or 0) > 0 then rec[#rec + 1] = Comma(HC.db.killingBlows) .. " killing blows" end
    if (HC.db.quests or 0) > 0   then rec[#rec + 1] = Comma(HC.db.quests) .. " quests" end
    if #rec > 0 then lines[#lines + 1] = "|cffaaaaaa" .. table.concat(rec, "   |   ") .. "|r" end

    lines[#lines + 1] = " "
    lines[#lines + 1] = ("|cff888888The %s hardcore character lost on this account.|r"):format(Ordinal(deaths))

    w.body:SetText(table.concat(lines, "\n"))
    local bodyH = w.body:GetStringHeight() or 130
    w:SetHeight(76 + bodyH + 46)
    w:Show()
end
