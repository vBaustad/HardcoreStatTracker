local ADDON, HC = ...

-- ---------------------------------------------------------------------------
-- Welcome window (first login on a character; nobody reads chat on login)
-- ---------------------------------------------------------------------------
function HC:ShowWelcome()
    if HC.welcomeFrame then HC.welcomeFrame:Show(); return end

    local w = CreateFrame("Frame", "HardcoreStatTrackerWelcome", UIParent, "BackdropTemplate")
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
    tinsert(UISpecialFrames, "HardcoreStatTrackerWelcome")  -- Escape closes
    HC.welcomeFrame = w

    local icon = w:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", 14, -12)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    title:SetText("|cffff4444Welcome to Hardcore Stat Tracker|r")

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
