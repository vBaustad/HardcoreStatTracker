local ADDON, HC = ...

-- ---------------------------------------------------------------------------
-- Welcome carousel (first login on a character; nobody reads chat on login).
-- A few Back/Next pages; the comic-splash page is interactive so the player can
-- preview a splash and turn it on right there.
-- ---------------------------------------------------------------------------
function HC:ShowWelcome()
    if HC.welcomeFrame then HC.welcomeFrame:Show(); HC.welcomeFrame.ShowPage(1); return end

    local w = CreateFrame("Frame", "HardcoreStatTrackerWelcome", UIParent, "BackdropTemplate")
    w:SetSize(420, 296)
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
    tinsert(UISpecialFrames, "HardcoreStatTrackerWelcome")  -- Escape closes
    HC.welcomeFrame = w

    local icon = w:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28); icon:SetPoint("TOPLEFT", 14, -12)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local header = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    header:SetText("|cffff4444Hardcore Stat Tracker|r")   -- persistent: which addon this is

    local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() w:Hide() end)

    local divider = w:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.6, 0.1, 0.1, 0.6); divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 14, -44); divider:SetPoint("TOPRIGHT", -14, -44)

    -- Shared page helpers ----------------------------------------------------
    local pages = {}
    local function newPage()
        local c = CreateFrame("Frame", nil, w)
        c:SetPoint("TOPLEFT", 0, 0); c:SetPoint("BOTTOMRIGHT", 0, 44)   -- leave the nav row
        c:Hide()
        pages[#pages + 1] = c
        return c
    end
    local function pageTitle(c, text)   -- per-page subtitle under the persistent header
        local t = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOPLEFT", 16, -50)
        t:SetText(text)
    end
    local function pageBody(c, text, y)
        local b = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b:SetPoint("TOPLEFT", 16, y or -52); b:SetWidth(388)
        b:SetJustifyH("LEFT"); b:SetSpacing(3); b:SetText(text)
        return b
    end
    local function pageCheck(c, label, x, y, get, set)
        local cb = CreateFrame("CheckButton", "HardcoreStatTrackerWelcomeCheck_" .. label:gsub("%s", ""),
            c, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", x, y)
        local fs = _G[cb:GetName() .. "Text"]; if fs then fs:SetText(label) end
        cb:SetChecked(get() and true or false)
        cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
        return cb
    end
    local function pageButton(c, label, x, y, onClick)
        local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
        b:SetSize(120, 24); b:SetPoint("TOPLEFT", x, y); b:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end
    local MEDIA = "Interface\\AddOns\\HardcoreStatTracker\\Media\\"
    -- A centered horizontal row of square images, each `size` px (trim = crop icon border).
    local function imageRow(c, paths, y, size, gap, trim)
        local n = #paths
        local startX = math.floor((420 - (n * size + (n - 1) * gap)) / 2)
        for i, path in ipairs(paths) do
            local t = c:CreateTexture(nil, "ARTWORK")
            t:SetSize(size, size)
            t:SetPoint("TOPLEFT", startX + (i - 1) * (size + gap), y)
            t:SetTexture(path)
            if trim then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        end
    end

    -- Page 1: Welcome - a strip of stat icons shows off the "trophy case".
    do
        local c = newPage()
        pageTitle(c, "|cffffd100Welcome|r")
        local icons = {}
        for _, k in ipairs({ "closestCall", "biggestHit", "highestCrit", "goldEarned", "toughestFoe", "makgoraWon" }) do
            icons[#icons + 1] = HC.ICONS[k]
        end
        imageRow(c, icons, -76, 40, 20, true)
        pageBody(c, "Your hardcore trophy case quietly records the moments that define a run.", -122)
        pageBody(c, "|cffffd100-|r  Everything is tracked |cffffffffautomatically|r as you play - no setup\n"
            .. "|cffffd100-|r  A small panel shows your picks; the |cffffd100+|r button opens the full window\n"
            .. "|cffffd100-|r  Records are |cffffffffper-character|r; Mak'gora & milestones are account-wide\n"
            .. "|cffffd100-|r  Optional extras: comic splashes, chat brags, low-health alerts", -148)
    end

    -- Page 2: Comic splashes (interactive) - the actual art, fewer & bigger.
    do
        local c = newPage()
        pageTitle(c, "|cffffd100Comic splashes|r")
        imageRow(c, { MEDIA .. "pow", MEDIA .. "boom", MEDIA .. "zap" }, -74, 72, 16, false)
        pageBody(c, "Optional fun: a comic-book splash pops on screen when you set a new record. "
            .. "Try it, then decide - you can pick the art and where it shows in Settings.", -156)
        pageButton(c, "Show me one", 16, -200, function() if HC.PreviewSplash then HC:PreviewSplash() end end)
        pageCheck(c, "Enable comic splashes", 150, -199,
            function() return HC.db and HC.db.comicPops end,
            function(v) if HC.db then HC.db.comicPops = v end end)
    end

    -- Page 3: Make it yours.
    do
        local c = newPage()
        pageTitle(c, "|cffffd100Make it yours|r")
        pageBody(c, "|cffffd100-|r  Pick which stats show, by category\n"
            .. "|cffffd100-|r  Click the |cffffd100+|r button on the panel for the full window\n"
            .. "|cffffd100-|r  Prefer a Titan-style layout? Switch to a full-width bar\n"
            .. "|cffffd100-|r  Optional chat: low-health alerts, famous last words, survival brags\n"
            .. "|cffffd100-|r  Records stay honest - resets counted, outside edits flagged", -76)
        pageBody(c, "It all lives in Settings - tweak it whenever:", -182)
        pageButton(c, "Open Settings", 16, -204, function()
            w:Hide(); if HC.OpenOptions then HC:OpenOptions() end
        end)
    end

    -- Navigation -------------------------------------------------------------
    local back = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    back:SetSize(80, 22); back:SetPoint("BOTTOMLEFT", 16, 14); back:SetText("Back")
    local nextBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    nextBtn:SetSize(90, 22); nextBtn:SetPoint("BOTTOMRIGHT", -16, 14)

    -- Page dots as small textures (the game font has no bullet glyph - it shows tofu).
    local dotTex, DOT, GAP = {}, 8, 8
    local span = #pages * DOT + (#pages - 1) * GAP
    for j = 1, #pages do
        local t = w:CreateTexture(nil, "OVERLAY")
        t:SetSize(DOT, DOT)
        t:SetPoint("BOTTOM", w, "BOTTOM", -span / 2 + DOT / 2 + (j - 1) * (DOT + GAP), 18)
        dotTex[j] = t
    end

    local function ShowPage(i)
        i = math.max(1, math.min(#pages, i))
        w.page = i
        for j, c in ipairs(pages) do c:SetShown(j == i) end
        back:SetShown(i > 1)
        nextBtn:SetText(i == #pages and "Done" or "Next")
        for j, t in ipairs(dotTex) do
            if j == i then t:SetColorTexture(1, 0.82, 0, 1) else t:SetColorTexture(0.45, 0.38, 0.38, 1) end
        end
    end
    w.ShowPage = ShowPage
    back:SetScript("OnClick", function() ShowPage(w.page - 1) end)
    nextBtn:SetScript("OnClick", function()
        if w.page == #pages then w:Hide() else ShowPage(w.page + 1) end
    end)

    ShowPage(1)
end
