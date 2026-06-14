local ADDON, HC = ...

local Comma, FmtPlayed = HC.Comma, HC.FmtPlayed

local function classColor(classFile)
    local c = (RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]) or { r = 1, g = 1, b = 1 }
    return ("|cff%02x%02x%02x"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
end

local function classDisplay(classFile)
    return (classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile or ""
end

-- Record the current (fallen) character into the account-wide roll. Returns the
-- new entry so the caller can show it.
function HC:RecordMemorial()
    if not HC.adb then return end
    HC.adb.memorials = HC.adb.memorials or {}
    local _, classFile = UnitClass("player")
    local e = {
        name   = UnitName("player") or "?",
        class  = classFile,
        level  = UnitLevel("player") or 0,
        alive  = (HC.LiveAlive and HC.LiveAlive()) or (HC.db and HC.db.playedTotal) or 0,
        killer = HC.state and HC.state.lastHitBy,
        zone   = GetRealZoneText() or GetZoneText() or "?",
        date   = time(),
        lowestPct    = HC.db and HC.db.lowestPct,
        highestCrit  = HC.db and HC.db.highestCrit,
        killingBlows = HC.db and HC.db.killingBlows,
        quests       = HC.db and HC.db.quests,
    }
    HC.adb.memorials[#HC.adb.memorials + 1] = e
    return e
end

local frame

-- One fallen character's card text.
local function detailText(e)
    local lines = {}
    lines[#lines + 1] = "Here lies " .. classColor(e.class) .. (e.name or "?") .. "|r"
    lines[#lines + 1] = ("|cffffd100Level %d %s|r"):format(e.level or 0, classDisplay(e.class))
    if e.alive then lines[#lines + 1] = "|cff4dff4dSurvived " .. FmtPlayed(e.alive) .. "|r" end
    lines[#lines + 1] = "|cffcccccc" .. (e.killer and ("Felled by " .. e.killer) or "Fallen")
        .. " in " .. (e.zone or "?") .. "|r"
    if e.date then lines[#lines + 1] = "|cff888888" .. date("%b %d, %Y", e.date) .. "|r" end
    local rec = {}
    if e.lowestPct then rec[#rec + 1] = ("closest call %d%% HP"):format(math.floor(e.lowestPct)) end
    if (e.highestCrit or 0) > 0  then rec[#rec + 1] = "biggest crit " .. Comma(e.highestCrit) end
    if (e.killingBlows or 0) > 0 then rec[#rec + 1] = Comma(e.killingBlows) .. " killing blows" end
    if (e.quests or 0) > 0       then rec[#rec + 1] = Comma(e.quests) .. " quests" end
    if #rec > 0 then
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cffaaaaaa" .. table.concat(rec, "\n") .. "|r"
    end
    return table.concat(lines, "\n")
end

local function ensureRow(w, i)
    local row = w.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, w.listContent)
    row:SetSize(338, 30)
    row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local bg = row:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0.06)
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(20, 20); row.icon:SetPoint("LEFT", 6, 0)
    row.icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"); row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0); row.name:SetJustifyH("LEFT")
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.sub:SetPoint("RIGHT", -8, 0); row.sub:SetJustifyH("RIGHT")
    w.rows[i] = row
    return row
end

local function showList(w)
    w.title:SetText("|cffff4444Fallen Heroes|r")
    w.detail:Hide(); w.back:Hide(); w.shareBtn:Hide(); w.okBtn:Hide()
    local mem = (HC.adb and HC.adb.memorials) or {}
    local n = #mem
    if n == 0 then
        w.scroll:Hide()
        w.empty:Show()
        w.empty:SetText("|cff4dff4dNo fallen heroes... yet.|r\n\n"
            .. "Every character who dies is remembered here.\n"
            .. "May this list stay empty - keep them alive!")
        return
    end
    w.empty:Hide()
    w.scroll:Show()
    for i = 1, n do
        local e = mem[n - i + 1]   -- newest first
        local row = ensureRow(w, i)
        row.name:SetText(classColor(e.class) .. (e.name or "?") .. "|r")
        row.sub:SetText(("|cffaaaaaalvl %d|r  |cff777777%s|r"):format(
            e.level or 0, e.date and date("%b %d", e.date) or ""))
        row:SetScript("OnClick", function() HC:ShowMemorial(e) end)
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(i - 1) * 32)
        row:Show()
    end
    for j = n + 1, #w.rows do w.rows[j]:Hide() end
    w.listContent:SetHeight(math.max(1, n * 32))
end

local function showDetail(w, e)
    w.curEntry = e
    w.title:SetText("|cffff4444In Memoriam|r")
    w.scroll:Hide(); w.empty:Hide()
    w.detail:SetText(detailText(e)); w.detail:Show()
    -- "Back" only makes sense when there's a roll to go back to.
    w.back:SetShown((HC.adb and HC.adb.memorials and #HC.adb.memorials > 0) or false)
    w.shareBtn:Show(); w.okBtn:Show()
end

local function build()
    if frame then return frame end
    local w = CreateFrame("Frame", "HardcoreStatTrackerMemorial", UIParent, "BackdropTemplate")
    w:SetSize(400, 360)
    w:SetPoint("CENTER", 0, 60)
    w:SetFrameStrata("FULLSCREEN_DIALOG")
    w:SetClampedToScreen(true); w:EnableMouse(true); w:SetMovable(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", function(s) s:StartMoving() end)
    w:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    w:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    w:SetBackdropColor(0.04, 0.03, 0.03, 0.97)
    w:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)
    tinsert(UISpecialFrames, "HardcoreStatTrackerMemorial")

    local icon = w:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26); icon:SetPoint("TOPLEFT", 12, -10)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    w.title:SetPoint("TOP", 0, -14)

    local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() w:Hide() end)

    -- List view: scrollable roll of fallen characters.
    w.scroll = CreateFrame("ScrollFrame", "HardcoreStatTrackerMemorialScroll", w, "UIPanelScrollFrameTemplate")
    w.scroll:SetPoint("TOPLEFT", 14, -46)
    w.scroll:SetPoint("BOTTOMRIGHT", -30, 16)
    w.listContent = CreateFrame("Frame", nil, w.scroll)
    w.listContent:SetSize(338, 1)
    w.scroll:SetScrollChild(w.listContent)
    w.rows = {}

    -- Empty state (no deaths yet).
    w.empty = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.empty:SetPoint("CENTER", 0, 20); w.empty:SetWidth(340); w.empty:SetJustifyH("CENTER"); w.empty:SetSpacing(5)

    -- Detail view: one character's card.
    w.detail = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.detail:SetPoint("TOP", 0, -52); w.detail:SetWidth(360); w.detail:SetJustifyH("CENTER"); w.detail:SetSpacing(5)

    w.back = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    w.back:SetSize(80, 22); w.back:SetPoint("BOTTOMLEFT", 16, 14); w.back:SetText("Back")
    w.back:SetScript("OnClick", function() HC:ShowMemorial() end)

    w.shareBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    w.shareBtn:SetSize(90, 22); w.shareBtn:SetPoint("BOTTOM", 0, 14); w.shareBtn:SetText("Share")
    w.shareBtn:SetScript("OnClick", function() if HC.ShareStats then HC:ShareStats(nil, w.curEntry) end end)

    w.okBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    w.okBtn:SetSize(80, 22); w.okBtn:SetPoint("BOTTOMRIGHT", -16, 14); w.okBtn:SetText("Close")
    w.okBtn:SetScript("OnClick", function() w:Hide() end)

    frame = w
    return w
end

-- No entry -> the roll (overview). An entry -> that character's card.
function HC:ShowMemorial(entry)
    local w = build()
    if entry then showDetail(w, entry) else showList(w) end
    w:Show()
end
