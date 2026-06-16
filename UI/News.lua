local ADDON, HC = ...

-- ---------------------------------------------------------------------------
-- "What's New" - a short, curated highlight panel shown once after an update,
-- and re-openable via /hst news. Full details live in CHANGELOG.md.
-- ---------------------------------------------------------------------------

local function AddonVersion()
    local v = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
        or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version"))
    return v or "?"
end
HC.AddonVersion = AddonVersion

-- Curated highlights per version (newest first). Keep these short and headline-y.
-- When shipping a version, add its entry here AND bump the .toc Version to match,
-- so the panel fires for players who update to it.
HC.NEWS = {
    ["1.7.0"] = {
        "|cffffd100Full-width bar|r - the mini panel can become a Titan-style bar across the top of the screen (Mini Panel -> Display -> Full-width bar).",
        "|cffffd100Visual splash picker|r - choose comic-splash art from a gallery of images instead of a text dropdown.",
        "|cffffd100Comic splashes are off by default|r now - opt in from the Splashes page whenever you want them.",
        "|cffffd100Tidier chat|r - record announcements are tagged |cffffffff[HST]|r, and the |cffffffff/hst share|r line reads better.",
        "|cffffd100Fixed|r - an addon conflict that could block the Looking For Group listings.",
    },
}
HC.NEWS_ORDER = { "1.7.0" }   -- newest first; HC:ShowNews() with no arg uses [1]

function HC:ShowNews(version)
    version = version or HC.NEWS_ORDER[1]
    local lines = version and HC.NEWS[version]
    if not lines then return end

    local w = HC.newsFrame
    if not w then
        w = CreateFrame("Frame", "HardcoreStatTrackerNews", UIParent, "BackdropTemplate")
        w:SetSize(420, 100)   -- height set after the text lays out
        w:SetPoint("CENTER", 0, 120)
        w:SetFrameStrata("DIALOG")
        w:SetClampedToScreen(true)
        w:EnableMouse(true)
        w:SetMovable(true)
        w:RegisterForDrag("LeftButton")
        w:SetScript("OnDragStart", w.StartMoving)
        w:SetScript("OnDragStop", w.StopMovingOrSizing)
        w:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        w:SetBackdropColor(0, 0, 0, 0.92)
        w:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)
        tinsert(UISpecialFrames, "HardcoreStatTrackerNews")   -- Escape closes

        local icon = w:CreateTexture(nil, "ARTWORK")
        icon:SetSize(28, 28); icon:SetPoint("TOPLEFT", 14, -12)
        icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        w.title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
        w.title:SetText("|cffff4444Hardcore Stat Tracker|r")   -- persistent: which addon this is

        w.sub = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        w.sub:SetPoint("TOPLEFT", 16, -44)

        local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        close:SetScript("OnClick", function() w:Hide() end)

        w.body = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        w.body:SetPoint("TOPLEFT", 16, -66)
        w.body:SetWidth(388); w.body:SetJustifyH("LEFT"); w.body:SetSpacing(4)

        local settings = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        settings:SetSize(110, 22); settings:SetPoint("BOTTOMLEFT", 16, 14)
        settings:SetText("Open Settings")
        settings:SetScript("OnClick", function() w:Hide(); if HC.OpenOptions then HC:OpenOptions() end end)

        local ok = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        ok:SetSize(80, 22); ok:SetPoint("BOTTOMRIGHT", -16, 14)
        ok:SetText("Got it")
        ok:SetScript("OnClick", function() w:Hide() end)

        HC.newsFrame = w
    end

    w.sub:SetText(("|cffffd100What's New|r  |cff888888v%s|r"):format(version))
    local txt = {}
    for _, line in ipairs(lines) do txt[#txt + 1] = "|cffffd100-|r  " .. line end
    w.body:SetText(table.concat(txt, "\n\n"))
    w:SetHeight(66 + (w.body:GetStringHeight() or 120) + 50)
    w:Show()
end

-- Login check: show the panel once when the installed version is newer than what
-- the player last saw. Fresh installs are covered by the Welcome window instead.
function HC:MaybeShowNews()
    if not HC.db then return end
    local cur  = AddonVersion()
    local last = HC.db.lastNewsVersion
    HC.db.lastNewsVersion = cur
    if last == cur then return end                          -- already seen this version
    if last == nil and not HC.db.welcomed then return end   -- brand-new profile: Welcome covers it
    if HC.NEWS[cur] and C_Timer and C_Timer.After then
        C_Timer.After(5, function() HC:ShowNews(cur) end)   -- after the world settles
    end
end
