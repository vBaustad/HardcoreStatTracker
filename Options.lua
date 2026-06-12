-- HCStats settings page: per-stat visibility plus frame show/lock.
local ADDON, HC = ...

local checks = {}   -- visibility checkboxes, keyed by stat key
local sliders = {}  -- value sliders

-- "Buy me a coffee" support link. WoW can't open a browser, so clicking pops
-- a dialog with the URL pre-selected for copying.
local BMC_URL = "buymeacoffee.com/vbaustad"
StaticPopupDialogs["HCSTATS_BMC"] = {
    text = "Thanks for using HC Stats!\nCopy the link below if you'd like to buy me a coffee.",
    button1 = CLOSE,
    hasEditBox = true,
    editBoxWidth = 260,
    OnShow = function(self)
        local eb = self.EditBox or self.editBox  -- field name differs across client builds
        if not eb then return end
        eb:SetText(BMC_URL)
        eb:HighlightText()
        eb:SetFocus()
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function AddCoffeeButton(panel)
    local btn = CreateFrame("Button", nil, panel)
    btn:SetSize(26, 26)
    btn:SetPoint("BOTTOMLEFT", 16, 14)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\AddOns\\HCStats\\bmc-logo")
    tex:SetAlpha(0.65)
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", btn, "RIGHT", 6, 0)
    label:SetText("|cff888888if you want to support|r")
    btn:SetScript("OnEnter", function(self)
        tex:SetAlpha(1)
        label:SetText("|cffffc840if you want to support|r")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Buy me a coffee", 1, 0.85, 0.2)
        GameTooltip:AddLine(BMC_URL, 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to copy the link.", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        tex:SetAlpha(0.65)
        label:SetText("|cff888888if you want to support|r")
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function() StaticPopup_Show("HCSTATS_BMC") end)
end

local function MakeCheck(parent, name, label, x, y, getter, setter, tooltip)
    local cb = CreateFrame("CheckButton", "HCStatsCheck_" .. name, parent,
        "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    local fs = _G[cb:GetName() .. "Text"]
    if fs then fs:SetText(label) end
    cb.tooltipText = tooltip
    cb._get, cb._set = getter, setter
    cb:SetScript("OnClick", function(self)
        self._set(self:GetChecked() and true or false)
    end)
    return cb
end

local function MakeSlider(parent, name, x, y, lo, hi, step, fmt, getter, setter)
    local s = CreateFrame("Slider", "HCStatsSlider_" .. name, parent, "OptionsSliderTemplate")
    s:SetWidth(200)
    s:SetPoint("TOPLEFT", x, y)
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    _G[s:GetName() .. "Low"]:SetText(tostring(lo))
    _G[s:GetName() .. "High"]:SetText(tostring(hi))
    s._fmt, s._get = fmt, getter
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        _G[self:GetName() .. "Text"]:SetText(fmt(v))
        setter(v)
    end)
    sliders[#sliders + 1] = s
    return s
end

function HC:BuildOptions()
    if HC.panel then return end

    local panel = CreateFrame("Frame")
    panel.name = "HC Stats"
    HC.panel = panel

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("HC Stats")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(560); sub:SetJustifyH("LEFT")
    sub:SetText("These toggles control the small on-screen panel (the \"mini view\") - uncheck the "
        .. "stats you'd rather not show off. The full window (the [+] button on the panel, or "
        .. "/hcstats full) always lists every stat, grouped and with details.")

    -- Frame-level options
    MakeCheck(panel, "shown", "Show the on-screen panel", 16, -64,
        function() return HC.db and HC.db.shown end,
        function(v) HC.db.shown = v; HC:UpdateDisplay() end,
        "Show or hide the HC Stats panel entirely.")
    MakeCheck(panel, "locked", "Lock the panel in place", 16, -90,
        function() return HC.db and HC.db.locked end,
        function(v) HC.db.locked = v end,
        "Prevent dragging the panel by accident.")
    MakeCheck(panel, "mobtip", "Show mob damage history on tooltips", 16, -116,
        function() return HC.db and HC.db.mobTooltip end,
        function(v) HC.db.mobTooltip = v end,
        "Adds \"Has hit you for up to X\" to the tooltip of mobs that have hurt you before.")
    MakeCheck(panel, "comic", "Comic splash on new hit records (POW!)", 16, -142,
        function() return HC.db and HC.db.comicPops end,
        function(v) HC.db.comicPops = v end,
        "Pops a comic-book POW/BOOM/ZAP on screen when you set a new record crit, melee hit, or ranged hit.")
    MakeCheck(panel, "combattimer", "Show the in-combat timer line", 16, -168,
        function() return HC.db and HC.db.combatTimer ~= false end,
        function(v) HC.db.combatTimer = v; HC:UpdateDisplay() end,
        "The live \"In Combat\" line on the mini panel showing fight time and damage taken.")

    -- Mini-panel sizing/appearance sliders (right side of the top area)
    MakeSlider(panel, "font", 320, -70, 9, 20, 1,
        function(v) return "Mini-view text size: " .. v end,
        function() return HC.db and HC.db.fontSize or 12 end,
        function(v) HC.db.fontSize = v; HC:UpdateDisplay() end)
    MakeSlider(panel, "scale", 320, -106, 0.7, 2.0, 0.1,
        function(v) return ("Panel scale: %.1f"):format(v) end,
        function() return HC.db and HC.db.scale or 1 end,
        function(v) HC.db.scale = v; HC:UpdateDisplay() end)
    MakeSlider(panel, "miniopacity", 320, -142, 0.2, 1.0, 0.05,
        function(v) return ("Mini-view opacity: %.0f%%"):format(v * 100) end,
        function() return HC.db and HC.db.miniAlpha or 0.8 end,
        function(v) HC.db.miniAlpha = v; if HC.ApplyMiniAlpha then HC:ApplyMiniAlpha() end end)

    local hdr = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", 16, -200)
    hdr:SetText("Stats to display")

    -- Three columns of per-stat visibility toggles, driven by HC.STATS order.
    local startY, rowH, colW, cols = -222, 23, 190, 3
    local perCol = math.ceil(#HC.STATS / cols)
    for i, s in ipairs(HC.STATS) do
        local key, label = s[1], s[2]
        local col = math.floor((i - 1) / perCol)
        local row = (i - 1) % perCol
        local cb = MakeCheck(panel, key, label, 16 + col * colW, startY - row * rowH,
            function() return HC:Visible(key) end,
            function(v) HC:SetVisible(key, v) end)
        checks[key] = cb
    end

    -- Reset buttons live here (a deliberate spot), not on the stats window.
    local resetY = startY - perCol * rowH - 16
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(150, 22)
    resetBtn:SetPoint("TOPLEFT", 16, resetY)
    resetBtn:SetText("Reset all records")
    resetBtn:SetScript("OnClick", function() StaticPopup_Show("HCSTATS_RESET") end)

    -- Debug: zero only the three hit records so the comic splash can re-trigger.
    local hitResetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    hitResetBtn:SetSize(170, 22)
    hitResetBtn:SetPoint("LEFT", resetBtn, "RIGHT", 12, 0)
    hitResetBtn:SetText("Reset hit records (debug)")
    hitResetBtn:SetScript("OnClick", function()
        if HC.ResetHitRecords then HC:ResetHitRecords() end
    end)

    -- Debug: preview the first-install welcome window on demand.
    local welcomeBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    welcomeBtn:SetSize(130, 22)
    welcomeBtn:SetPoint("LEFT", hitResetBtn, "RIGHT", 12, 0)
    welcomeBtn:SetText("Show welcome")
    welcomeBtn:SetScript("OnClick", function()
        if HC.ShowWelcome then HC:ShowWelcome() end
    end)

    local resetNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    resetNote:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -6)
    resetNote:SetWidth(540); resetNote:SetJustifyH("LEFT")
    resetNote:SetText("Reset all: clears every record for this character (keeps Time Alive, asks first). "
        .. "Hit records: zeroes crit / melee / ranged only, for testing the splash.")

    local function Refresh()
        if not HC.db then return end
        for _, cb in pairs(checks) do cb:SetChecked(cb._get() and true or false) end
        -- frame-level checks live alongside; refresh them too
        local sh = _G["HCStatsCheck_shown"]; if sh then sh:SetChecked(HC.db.shown and true or false) end
        local lk = _G["HCStatsCheck_locked"]; if lk then lk:SetChecked(HC.db.locked and true or false) end
        local mt = _G["HCStatsCheck_mobtip"]; if mt then mt:SetChecked(HC.db.mobTooltip and true or false) end
        local cp = _G["HCStatsCheck_comic"]; if cp then cp:SetChecked(HC.db.comicPops and true or false) end
        local ct = _G["HCStatsCheck_combattimer"]; if ct then ct:SetChecked(HC.db.combatTimer ~= false) end
        for _, s in ipairs(sliders) do
            local v = s._get()
            s:SetValue(v)
            _G[s:GetName() .. "Text"]:SetText(s._fmt(v))
        end
    end
    panel:SetScript("OnShow", Refresh)
    Refresh()

    AddCoffeeButton(panel)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(panel, "HC Stats")
        cat.ID = "HCStats"
        Settings.RegisterAddOnCategory(cat)
        HC.category = cat
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    HC:BuildLastWordsOptions()
    HC:BuildAnnounceOptions()
    HC:BuildSplashOptions()
end

-- ---------------------------------------------------------------------------
-- "Splashes" subpanel: per-splash enable, trigger stat, and drag positioning
-- ---------------------------------------------------------------------------
function HC:BuildSplashOptions()
    if HC.splashPanel then return end
    local panel = CreateFrame("Frame")
    panel.name = "Splashes"
    HC.splashPanel = panel

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Comic Splashes")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(560); sub:SetJustifyH("LEFT")
    sub:SetText("Each splash can be turned off, linked to a different record stat, and dragged to "
        .. "a new spot on screen. The master toggle lives on the main HC Stats page.")

    local SPLASH_LABEL = { pow = "POW!", boom = "BOOM!", zap = "ZAP!" }
    local order = { "pow", "boom", "zap" }
    local cbs, dds = {}, {}

    local function labelFor(statKey)
        for _, opt in ipairs(HC.SPLASH_TRIGGERS) do
            if opt[1] == statKey then return opt[2] end
        end
        return statKey or "?"
    end

    for i, which in ipairs(order) do
        local y = -70 - (i - 1) * 46

        local name = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        name:SetPoint("TOPLEFT", 16, y - 8)
        name:SetText(SPLASH_LABEL[which])

        cbs[which] = MakeCheck(panel, "splash_" .. which, "Show", 96, y - 2,
            function() return HC.db and HC.db.comic[which].on end,
            function(v) HC.db.comic[which].on = v end,
            "Enable or disable this splash.")

        local dd = CreateFrame("Frame", "HCStatsSplashDD_" .. which, panel, "UIDropDownMenuTemplate")
        dd:SetPoint("TOPLEFT", 170, y)
        UIDropDownMenu_SetWidth(dd, 180)
        UIDropDownMenu_Initialize(dd, function(_, level)
            for _, opt in ipairs(HC.SPLASH_TRIGGERS) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt[2]
                info.value = opt[1]
                info.func = function(btn)
                    HC.db.comic[which].stat = btn.value
                    UIDropDownMenu_SetSelectedValue(dd, btn.value)
                    UIDropDownMenu_SetText(dd, opt[2])
                end
                info.checked = (HC.db.comic[which].stat == opt[1])
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        dds[which] = dd
    end

    local posBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    posBtn:SetSize(170, 22)
    posBtn:SetPoint("TOPLEFT", 16, -224)
    posBtn:SetText("Position splashes")
    posBtn:SetScript("OnClick", function() HC:ToggleSplashPlacement() end)

    local posNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    posNote:SetPoint("LEFT", posBtn, "RIGHT", 10, 0)
    posNote:SetText("Shows all three on screen - drag them, then click again to save. (/hcstats splashes)")

    local function Refresh()
        if not (HC.db and HC.db.comic) then return end
        for which, cb in pairs(cbs) do
            cb:SetChecked(HC.db.comic[which].on and true or false)
        end
        for which, dd in pairs(dds) do
            local statKey = HC.db.comic[which].stat
            UIDropDownMenu_SetSelectedValue(dd, statKey)
            UIDropDownMenu_SetText(dd, labelFor(statKey))
        end
    end
    panel:SetScript("OnShow", Refresh)
    Refresh()

    if Settings and Settings.RegisterCanvasLayoutSubcategory and HC.category then
        Settings.RegisterCanvasLayoutSubcategory(HC.category, panel, "Splashes")
    elseif InterfaceOptions_AddCategory then
        panel.parent = "HC Stats"
        InterfaceOptions_AddCategory(panel)
    end
end

-- ---------------------------------------------------------------------------
-- "Famous Last Words" subpanel
-- ---------------------------------------------------------------------------
function HC:BuildLastWordsOptions()
    if HC.lwPanel then return end
    local panel = CreateFrame("Frame")
    panel.name = "Last Words"
    HC.lwPanel = panel

    local function LW() return HC.db.lastWords end

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Famous Last Words")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(560); sub:SetJustifyH("LEFT")
    sub:SetText("Two independent low-health reactions: a random line broadcast in chat (your "
        .. "famous last words) and an attention-grabbing flash + sound - each with its own "
        .. "trigger %. |cffff8080The chat line auto-types in /say, so use it tastefully.|r")

    local lwChecks = {}
    local function add(name, label, x, y, get, set, tip)
        local cb = MakeCheck(panel, name, label, x, y, get, set, tip)
        lwChecks[#lwChecks + 1] = cb
        return cb
    end

    -- The subtitle wraps to ~3 lines and spans both columns, so all content
    -- starts below it (y = -100).
    add("lw_enabled", "Enable Famous Last Words", 16, -100,
        function() return LW().enabled end, function(v) LW().enabled = v end,
        "Master switch for the low-health announcement and alert.")

    -- Chat announcement + its own threshold
    add("lw_say", "Announce a message in chat", 16, -130,
        function() return LW().say end, function(v) LW().say = v end,
        "Broadcast a random line to chat when you drop low.")
    add("lw_yell", "Use /yell instead of /say", 36, -154,
        function() return LW().channel == "YELL" end,
        function(v) LW().channel = v and "YELL" or "SAY" end,
        "Yell reaches further than say.")
    local sayThr = MakeSlider(panel, "lwsaythr", 40, -192, 5, 60, 1,
        function(v) return "Announce at or below: " .. v .. "%" end,
        function() return LW().sayThreshold or 15 end,
        function(v) LW().sayThreshold = v end)

    -- Attention alert + its own (usually higher) threshold
    add("lw_alertSelf", "Alert me (screen flash + sound)", 16, -234,
        function() return LW().alertSelf end, function(v) LW().alertSelf = v end,
        "Flash a red low-health vignette and play a warning sound - an attention "
        .. "grab if you weren't watching your health.")
    local alertThr = MakeSlider(panel, "lwalertthr", 40, -272, 5, 60, 1,
        function(v) return "Alert at or below: " .. v .. "%" end,
        function() return LW().alertThreshold or 30 end,
        function(v) LW().alertThreshold = v end)

    add("lw_useDefaults", "Include the built-in messages (a surprise pool)", 16, -310,
        function() return LW().useDefaults end, function(v) LW().useDefaults = v end,
        "Mixes the addon's hidden built-in lines in with yours (50/50). "
        .. "Uncheck to broadcast ONLY your own messages.")

    local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testBtn:SetSize(90, 22)
    testBtn:SetPoint("TOPLEFT", 16, -346)
    testBtn:SetText("Test")
    testBtn:SetScript("OnClick", function() if HC.TestDanger then HC:TestDanger() end end)

    -- Custom-messages editor (right column): add box + removable list.
    local cmLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cmLabel:SetPoint("TOPLEFT", 320, -102)
    cmLabel:SetText("Your own messages:")

    local input = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    input:SetSize(176, 20)
    input:SetPoint("TOPLEFT", 326, -124)
    input:SetAutoFocus(false)
    input:SetMaxLetters(255)

    local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addBtn:SetSize(48, 22)
    addBtn:SetPoint("LEFT", input, "RIGHT", 8, 0)
    addBtn:SetText("Add")

    -- Scrollable list of saved messages, each with an [X] to remove it.
    local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 320, -152)
    box:SetSize(270, 150)
    box:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    box:SetBackdropColor(0, 0, 0, 0.6)
    box:SetBackdropBorderColor(0.4, 0.4, 0.4)

    local sf = CreateFrame("ScrollFrame", "HCStatsLWList", box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(230, 1)
    sf:SetScrollChild(content)

    local rowPool = {}
    local function RenderList()
        local list = LW().custom or {}
        for i, msg in ipairs(list) do
            local row = rowPool[i]
            if not row then
                row = CreateFrame("Frame", nil, content)
                row:SetSize(228, 18)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", 2, 0)
                row.text:SetPoint("RIGHT", -22, 0)
                row.text:SetJustifyH("LEFT")
                row.del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.del:SetSize(18, 18)
                row.del:SetText("x")
                row.del:SetPoint("RIGHT", 0, 0)
                rowPool[i] = row
            end
            row.text:SetText(msg)
            row.del:SetScript("OnClick", function()
                table.remove(LW().custom, i)
                RenderList()
            end)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 20)
            row:Show()
        end
        for j = #list + 1, #rowPool do rowPool[j]:Hide() end
        content:SetHeight(math.max(1, #list * 20))
        if #list == 0 then cmLabel:SetText("Your own messages: |cff888888(none yet)|r")
        else cmLabel:SetText("Your own messages: |cffffd100" .. #list .. "|r") end
    end

    local function AddMessage()
        local t = (input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if t ~= "" then
            table.insert(LW().custom, t)
            input:SetText("")
            RenderList()
        end
        input:ClearFocus()
    end
    input:SetScript("OnEnterPressed", AddMessage)
    input:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    addBtn:SetScript("OnClick", AddMessage)

    local function lwRefresh()
        if not HC.db then return end
        for _, cb in ipairs(lwChecks) do cb:SetChecked(cb._get() and true or false) end
        for _, s in ipairs({ sayThr, alertThr }) do
            local v = s._get()
            s:SetValue(v)
            _G[s:GetName() .. "Text"]:SetText(s._fmt(v))
        end
        RenderList()
    end
    panel:SetScript("OnShow", lwRefresh)
    lwRefresh()  -- initial populate, in case OnShow is unreliable on first open

    if Settings and Settings.RegisterCanvasLayoutSubcategory and HC.category then
        Settings.RegisterCanvasLayoutSubcategory(HC.category, panel, "Last Words")
    elseif InterfaceOptions_AddCategory then
        panel.parent = "HC Stats"
        InterfaceOptions_AddCategory(panel)
    end
end

-- ---------------------------------------------------------------------------
-- "Announcements" subpanel
-- ---------------------------------------------------------------------------
function HC:BuildAnnounceOptions()
    if HC.anPanel then return end
    local panel = CreateFrame("Frame")
    panel.name = "Announcements"
    HC.anPanel = panel

    local function AN() return HC.db.announce end

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Announcements")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(560); sub:SetJustifyH("LEFT")
    sub:SetText("After a fight you survive, brag about any new all-time records you set. Sent to "
        .. "party chat (or /say when solo), |cffff8080never in raid|r. Only new personal bests "
        .. "announce, so it stays rare.")

    local anChecks = {}
    local function addc(name, label, x, y, get, set, tip)
        local cb = MakeCheck(panel, name, label, x, y, get, set, tip)
        anChecks[#anChecks + 1] = cb
        return cb
    end

    addc("an_enabled", "Enable record announcements", 16, -64,
        function() return AN().enabled end, function(v) AN().enabled = v end,
        "Master switch.")
    addc("an_guild", "Announce to guild chat", 16, -90,
        function() return AN().guild end, function(v) AN().guild = v end,
        "Post the brag to guild chat (alongside party/say, unless 'guild only' is set).")
    addc("an_guildOnly", "Guild only (skip party/say)", 36, -114,
        function() return AN().guildOnly end, function(v) AN().guildOnly = v end,
        "When guild chat is on, send ONLY to guild - never to party or /say.")
    local maxSlider = MakeSlider(panel, "anmax", 30, -150, 1, 5, 1,
        function(v) return "Max announcements per fight: " .. v end,
        function() return AN().max or 2 end,
        function(v) AN().max = v end)

    local hdr = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", 16, -186)
    hdr:SetText("Records to announce")

    local startY, rowH, colW = -210, 24, 270
    local order = HC.ANNOUNCE_ORDER
    local perCol = math.ceil(#order / 2)
    for i, key in ipairs(order) do
        local def = HC.ANNOUNCE[key]
        local col = (i <= perCol) and 0 or 1
        local row = (i <= perCol) and (i - 1) or (i - perCol - 1)
        addc("an_" .. key, def.label, 16 + col * colW, startY - row * rowH,
            function() return AN().stats[key] end,
            function(v) AN().stats[key] = v end)
    end

    local function anRefresh()
        if not HC.db then return end
        for _, cb in ipairs(anChecks) do cb:SetChecked(cb._get() and true or false) end
        local v = AN().max or 2
        maxSlider:SetValue(v)
        _G[maxSlider:GetName() .. "Text"]:SetText("Max announcements per fight: " .. v)
    end
    panel:SetScript("OnShow", anRefresh)
    anRefresh()

    if Settings and Settings.RegisterCanvasLayoutSubcategory and HC.category then
        Settings.RegisterCanvasLayoutSubcategory(HC.category, panel, "Announcements")
    elseif InterfaceOptions_AddCategory then
        panel.parent = "HC Stats"
        InterfaceOptions_AddCategory(panel)
    end
end

function HC:OpenOptions()
    if not HC.panel then return end
    if Settings and Settings.OpenToCategory and HC.category then
        Settings.OpenToCategory(HC.category.ID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(HC.panel)
        InterfaceOptionsFrame_OpenToCategory(HC.panel)
    end
end
