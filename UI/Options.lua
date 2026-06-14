-- HardcoreStatTracker settings: General + Mini Panel + Splashes + Famous Last
-- Words + Announcements canvas pages. Pure presentation; the toggles drive the
-- same saved-variable fields the rest of the addon reads.
local ADDON, HC = ...

-- "Buy me a coffee" support link. WoW can't open a browser, so clicking pops
-- a dialog with the URL pre-selected for copying.
local BMC_URL = "buymeacoffee.com/vbaustad"
StaticPopupDialogs["HST_BMC"] = {
    text = "Thanks for using Hardcore Stat Tracker!\nCopy the link below if you'd like to buy me a coffee.",
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

-- ---------------------------------------------------------------------------
-- Shared building blocks (used by every page)
-- ---------------------------------------------------------------------------

-- Attach a hover tooltip to any mouse-aware frame. HookScript so we never clobber
-- a template's own OnEnter/OnLeave.
local function AddTooltip(frame, title, body)
    if not body and not title then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title then GameTooltip:AddLine(title, 1, 0.82, 0) end
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Section header.
local function MakeHeader(parent, text, x, y)
    local h = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h:SetPoint("TOPLEFT", x, y)
    h:SetText("|cffffd100" .. text .. "|r")
    return h
end

-- Checkbox with a label that is itself hoverable + clickable, plus a tooltip.
local function MakeCheck(parent, name, label, x, y, getter, setter, tooltip, compact)
    local cb = CreateFrame("CheckButton", "HardcoreStatTrackerCheck_" .. name, parent,
        "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    local fs = _G[cb:GetName() .. "Text"]
    if fs then
        fs:SetText(label)
        -- Extend the click/hover area over the label - unless compact, where
        -- tightly-packed columns would otherwise overlap each other's hit rects.
        if not compact then cb:SetHitRectInsets(0, -(fs:GetStringWidth() + 4), 0, 0) end
    end
    cb._get, cb._set = getter, setter
    cb:SetScript("OnClick", function(self) self._set(self:GetChecked() and true or false) end)
    AddTooltip(cb, label, tooltip)
    return cb
end

local function MakeSlider(parent, name, x, y, lo, hi, step, fmt, getter, setter, tooltip)
    local s = CreateFrame("Slider", "HardcoreStatTrackerSlider_" .. name, parent, "OptionsSliderTemplate")
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
    AddTooltip(s, nil, tooltip)
    return s
end

-- Refresh a list of checkboxes / sliders from their live getters.
local function RefreshControls(controls)
    for _, c in ipairs(controls) do
        if c._fmt then            -- slider
            local v = c._get()
            c:SetValue(v)
            _G[c:GetName() .. "Text"]:SetText(c._fmt(v))
        else                      -- checkbox
            c:SetChecked(c._get() and true or false)
        end
    end
end

local function AddCoffeeButton(panel)
    local btn = CreateFrame("Button", nil, panel)
    btn:SetSize(26, 26)
    btn:SetPoint("BOTTOMLEFT", 16, 14)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\AddOns\\HardcoreStatTracker\\bmc-logo")
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
    btn:SetScript("OnClick", function() StaticPopup_Show("HST_BMC") end)
end

local function RegisterPage(panel, label, parent)
    if Settings and Settings.RegisterCanvasLayoutCategory and not parent then
        local cat = Settings.RegisterCanvasLayoutCategory(panel, label)
        cat.ID = "HardcoreStatTracker"
        Settings.RegisterAddOnCategory(cat)
        HC.category = cat
    elseif Settings and Settings.RegisterCanvasLayoutSubcategory and HC.category then
        Settings.RegisterCanvasLayoutSubcategory(HC.category, panel, label)
    elseif InterfaceOptions_AddCategory then
        if parent then panel.parent = parent end
        InterfaceOptions_AddCategory(panel)
    end
end

-- ---------------------------------------------------------------------------
-- Main page: panel appearance + on-screen behaviour
-- ---------------------------------------------------------------------------
function HC:BuildOptions()
    if HC.panel then return end

    local panel = CreateFrame("Frame")
    panel.name = "Hardcore Stat Tracker"
    HC.panel = panel

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Hardcore Stat Tracker")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(560); sub:SetJustifyH("LEFT")
    sub:SetText("This page controls the on-screen panel. Use the sub-pages on the left for which "
        .. "stats it shows (Mini Panel), comic splashes, famous last words, and announcements. "
        .. "Hover any option for details.")

    local controls = {}
    local function chk(...) local cb = MakeCheck(panel, ...); controls[#controls + 1] = cb; return cb end
    local function sld(...) local s = MakeSlider(panel, ...); controls[#controls + 1] = s; return s end

    -- LEFT: panel toggles + on-screen behaviours --------------------------------
    MakeHeader(panel, "Panel", 16, -78)
    chk("shown", "Show the on-screen panel", 16, -100,
        function() return HC.db and HC.db.shown end,
        function(v) HC.db.shown = v; HC:UpdateDisplay() end,
        "Show or hide the mini panel entirely. (Slash: /hst)")
    chk("locked", "Lock the panel in place", 16, -124,
        function() return HC.db and HC.db.locked end,
        function(v) HC.db.locked = v end,
        "Stops the panel from being dragged by accident. Unlock to reposition it.")

    MakeHeader(panel, "On screen", 16, -158)
    chk("combattimer", "Show in-combat timer", 16, -180,
        function() return HC.db and HC.db.combatTimer ~= false end,
        function(v) HC.db.combatTimer = v; HC:UpdateDisplay() end,
        "Adds a live \"In Combat\" line to the panel during a fight, showing fight time and damage taken.")
    chk("minihighlight", "Highlight new records on the panel", 16, -204,
        function() return HC.db and HC.db.miniHighlight ~= false end,
        function(v) HC.db.miniHighlight = v end,
        "Animate a dashed gold border around a panel row for a few seconds after it sets a new record.")
    chk("mobtip", "Show mob damage history on tooltips", 16, -228,
        function() return HC.db and HC.db.mobTooltip end,
        function(v) HC.db.mobTooltip = v end,
        "Adds \"Has hit you for up to X\" to the tooltip of any mob that has hurt one of your characters before.")
    chk("minimap", "Show a minimap button", 16, -252,
        function() return HC.db and HC.db.minimapButton end,
        function(v) HC.db.minimapButton = v; if HC.ApplyMinimapButton then HC:ApplyMinimapButton() end end,
        "A button on the minimap: left-click for the full window, right-click for settings, drag to reposition.")

    -- RIGHT: size / opacity sliders, grouped per window -------------------------
    MakeHeader(panel, "Mini panel", 330, -78)
    sld("scale", 360, -104, 0.7, 2.0, 0.1,
        function(v) return ("Scale: %.1f"):format(v) end,
        function() return HC.db and HC.db.scale or 1 end,
        function(v) HC.db.scale = v; HC:UpdateDisplay() end,
        "Overall size of the mini panel.")
    sld("font", 360, -144, 9, 20, 1,
        function(v) return "Text size: " .. v end,
        function() return HC.db and HC.db.fontSize or 12 end,
        function(v) HC.db.fontSize = v; HC:UpdateDisplay() end,
        "Font size of the rows on the mini panel.")
    sld("miniopacity", 360, -184, 0.2, 1.0, 0.05,
        function(v) return ("Background: %.0f%%"):format(v * 100) end,
        function() return HC.db and HC.db.miniAlpha or 0.8 end,
        function(v) HC.db.miniAlpha = v; if HC.ApplyMiniAlpha then HC:ApplyMiniAlpha() end end,
        "How solid the mini panel's dark background is.")

    MakeHeader(panel, "Full window (the [+] window)", 330, -222)
    sld("fullscale", 360, -248, 0.7, 1.6, 0.05,
        function(v) return ("Scale: %.2f"):format(v) end,
        function() return HC.db and HC.db.fullScale or 1 end,
        function(v) HC.db.fullScale = v; if HC.fullFrame then HC.fullFrame:SetScale(v) end end,
        "Size of the full stats window. Also adjustable live from its Display button.")
    sld("fullopacity", 360, -288, 0.2, 1.0, 0.05,
        function(v) return ("Background: %.0f%%"):format(v * 100) end,
        function() return HC.db and HC.db.fullAlpha or 0.97 end,
        function(v) HC.db.fullAlpha = v; if HC.fullFrame then HC.fullFrame:SetBackdropColor(0.05, 0.04, 0.04, v) end end,
        "Background opacity of the full stats window.")

    -- Footer: reset + support --------------------------------------------------
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, 22)
    resetBtn:SetPoint("TOPLEFT", 16, -328)
    resetBtn:SetText("Reset all records")
    resetBtn:SetScript("OnClick", function() StaticPopup_Show("HST_RESET") end)
    AddTooltip(resetBtn, "Reset all records",
        "Clears every record for this character. Time Alive and account-wide Mak'gora are kept. Asks first.")

    local resetNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    resetNote:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
    resetNote:SetText("Clears this character's records (keeps Time Alive). Asks first.")

    local function Refresh() if HC.db then RefreshControls(controls) end end
    panel:SetScript("OnShow", Refresh)
    Refresh()

    AddCoffeeButton(panel)
    RegisterPage(panel, "Hardcore Stat Tracker")

    -- Sub-pages, in display order.
    HC:BuildStatsOptions()
    HC:BuildSplashOptions()
    HC:BuildLastWordsOptions()
    HC:BuildAlertOptions()
    HC:BuildAnnounceOptions()
end

-- ---------------------------------------------------------------------------
-- "Mini Panel" sub-page: which stats show, grouped by category
-- ---------------------------------------------------------------------------
function HC:BuildStatsOptions()
    if HC.statsPanel then return end
    local panel = CreateFrame("Frame")
    panel.name = "Mini Panel"
    HC.statsPanel = panel

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Mini Panel - stats to show")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(560); sub:SetJustifyH("LEFT")
    sub:SetText("Pick which stats appear on the small on-screen panel. The full window (the [+] "
        .. "button on the panel, or /hst full) always lists every stat. Hover a checkbox for what it tracks.")

    -- key -> settings label, and title -> keys, from the master stat list.
    local labelOf, keysOf = {}, {}
    for _, s in ipairs(HC.STATS) do labelOf[s[1]] = s[2] end
    for _, g in ipairs(HC.STAT_GROUPS) do keysOf[g[1]] = g[2] end

    local controls = {}

    -- Show all / Hide all every stat at once (handy now there are ~35).
    local function SetAllStats(v)
        for _, s in ipairs(HC.STATS) do HC:SetVisible(s[1], v) end
        RefreshControls(controls)
    end
    local showAllBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    showAllBtn:SetSize(80, 22)
    showAllBtn:SetPoint("TOPRIGHT", -100, -16)
    showAllBtn:SetText("Show all")
    showAllBtn:SetScript("OnClick", function() SetAllStats(true) end)
    local hideAllBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    hideAllBtn:SetSize(80, 22)
    hideAllBtn:SetPoint("TOPRIGHT", -14, -16)
    hideAllBtn:SetText("Hide all")
    hideAllBtn:SetScript("OnClick", function() SetAllStats(false) end)

    -- Render one category (header + stats in 3 aligned columns) into parent at y;
    -- returns the next y below it.
    local function renderCategory(parent, gtitle, y)
        MakeHeader(parent, gtitle, 16, y)
        y = y - 22
        local keys = keysOf[gtitle] or {}
        for i, key in ipairs(keys) do
            local col = (i - 1) % 3
            local row = math.floor((i - 1) / 3)
            controls[#controls + 1] = MakeCheck(parent, key, labelOf[key] or key,
                16 + col * 188, y - row * 22,
                function() return HC:Visible(key) end,
                function(v) HC:SetVisible(key, v) end,
                HC.STAT_HELP[key])
        end
        return y - math.ceil(#keys / 3) * 22 - 10
    end

    -- Tabs keep each section short and aligned instead of one giant column.
    local TABS = {
        { "Survival",        { "Survival" } },
        { "Combat & Healing", { "Combat", "Healing" } },
        { "World & Wealth",  { "Pet", "Group", "Adventure", "Wealth", "Mak'gora", "Character" } },
    }
    local containers, tabBtns = {}, {}
    local function ShowTab(active)
        for i, c in ipairs(containers) do c:SetShown(i == active) end
        for i, b in ipairs(tabBtns) do
            if i == active then b:Disable() else b:Enable() end
        end
    end

    local bx = 16
    for i, t in ipairs(TABS) do
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(150, 22)
        b:SetPoint("TOPLEFT", bx, -72)
        b:SetText(t[1])
        b:SetScript("OnClick", function() ShowTab(i) end)
        tabBtns[i] = b
        bx = bx + 154

        local c = CreateFrame("Frame", nil, panel)
        c:SetPoint("TOPLEFT"); c:SetPoint("BOTTOMRIGHT")
        containers[i] = c
        local y = -104
        for _, gtitle in ipairs(t[2]) do
            y = renderCategory(c, gtitle, y)
        end
    end

    local function Refresh() if HC.db then RefreshControls(controls) end end
    panel:SetScript("OnShow", Refresh)
    Refresh()
    ShowTab(1)

    RegisterPage(panel, "Mini Panel", "Hardcore Stat Tracker")
end

-- ---------------------------------------------------------------------------
-- "Splashes" sub-page: master toggles + a 6-slot table (art / trigger / sound)
-- with live art previews, plus Position / Lock placement controls.
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
    sub:SetText("Up to six splashes can pop on screen when you set a record. For each slot pick its "
        .. "art (or Off to disable it), the record that triggers it, and an optional sound - then use "
        .. "Position to drag them where you want.")

    local masters = {}
    local ddList = {}        -- { dd, options, get } for refresh
    local rows = {}          -- [i] = { preview } for refresh

    masters[#masters + 1] = MakeCheck(panel, "comicpops", "Show comic splashes (master)", 16, -74,
        function() return HC.db and HC.db.comicPops end,
        function(v) HC.db.comicPops = v end,
        "Master switch for the whole feature. Off = nothing pops, whatever the slots below say.")
    local soundHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    soundHint:SetPoint("TOPLEFT", 16, -120)
    soundHint:SetText("Sound plays per slot below (None = silent), on the Sound Effects channel - set its volume in the game's Sound options.")
    masters[#masters + 1] = MakeSlider(panel, "comicdur", 330, -84, 1, 6, 0.5,
        function(v) return ("Show for: %.1fs"):format(v) end,
        function() return HC.db and HC.db.comicDuration or 2 end,
        function(v) HC.db.comicDuration = v end,
        "How long each splash stays on screen, start to finish (pop-in + hold + fade-out).")
    masters[#masters + 1] = MakeCheck(panel, "comicrandom", "Random art on every crit", 16, -98,
        function() return HC.db and HC.db.comicRandom end,
        function(v) HC.db.comicRandom = v; if panel._splashRefresh then panel._splashRefresh() end end,
        "Pop a RANDOM comic art on every crit (about every 2s), cycling through all arts and sounds, at a random one of your 6 spots. The slots' art/trigger/sound are ignored, but Position splashes still sets where they can appear.")

    -- Art options = "Off" plus every art texture.
    local ART_OPTS = { { "none", "Off" } }
    for _, o in ipairs(HC.SPLASH_ART) do ART_OPTS[#ART_OPTS + 1] = o end

    local function labelOf(options, value)
        for _, opt in ipairs(options) do if opt[1] == value then return opt[2] end end
        return value or "?"
    end

    local function MakeDD(suffix, ddX, ddY, width, options, getV, setV, onPick)
        local dd = CreateFrame("Frame", "HardcoreStatTrackerSplashDD_" .. suffix, panel, "UIDropDownMenuTemplate")
        dd:SetPoint("TOPLEFT", ddX, ddY)
        UIDropDownMenu_SetWidth(dd, width)
        UIDropDownMenu_Initialize(dd, function(_, level)
            for _, opt in ipairs(options) do
                local info = UIDropDownMenu_CreateInfo()
                info.text, info.value = opt[2], opt[1]
                info.func = function(btn)
                    setV(btn.value)
                    UIDropDownMenu_SetSelectedValue(dd, btn.value)
                    UIDropDownMenu_SetText(dd, opt[2])
                    if onPick then onPick(btn.value) end
                end
                info.checked = (getV() == opt[1])
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        ddList[#ddList + 1] = { dd = dd, options = options, get = getV }
        return dd
    end

    -- Column captions.
    local function cap(text, x, y)
        local f = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        f:SetPoint("TOPLEFT", x, y); f:SetText("|cffffd100" .. text .. "|r")
    end
    cap("Art",         52, -148)
    cap("Triggers on", 196, -148)
    cap("Sound",       380, -148)

    for i = 1, HC.SPLASH_SLOTS do
        local baseY = -166 - (i - 1) * 38
        local function slot() return HC.db.comic[i] end

        local artDD = MakeDD("art_" .. i, 72, baseY, 64, ART_OPTS,
            function() return slot().art end,
            function(v) slot().art = v end,
            function(v) HC.SplashArtTexture(rows[i].preview, v) end)

        -- Slot number + live art thumbnail, anchored to the art dropdown.
        local preview = panel:CreateTexture(nil, "ARTWORK")
        preview:SetSize(26, 26)
        preview:SetPoint("RIGHT", artDD, "LEFT", 4, 2)
        local num = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        num:SetPoint("RIGHT", preview, "LEFT", -2, 0)
        num:SetText(i .. ".")
        rows[i] = { preview = preview }

        MakeDD("trigger_" .. i, 185, baseY, 145, HC.SPLASH_TRIGGERS,
            function() return slot().stat end,
            function(v) slot().stat = v end)

        MakeDD("sound_" .. i, 366, baseY, 95, HC.SPLASH_SOUNDS,
            function() return slot().sound end,
            function(v) slot().sound = v end,
            function(v) HC.PlaySplashSound(v) end)
    end

    local posBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    posBtn:SetSize(150, 22)
    posBtn:SetPoint("TOPLEFT", 16, -406)
    posBtn:SetText("Position splashes")
    posBtn:SetScript("OnClick", function() HC:SetSplashPlacement(true) end)
    AddTooltip(posBtn, "Position splashes",
        "Show every active splash on screen (green overlay, dashed border) so you can drag each one into place.")

    local lockBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    lockBtn:SetSize(90, 22)
    lockBtn:SetPoint("LEFT", posBtn, "RIGHT", 8, 0)
    lockBtn:SetText("Lock")
    lockBtn:SetScript("OnClick", function() HC:SetSplashPlacement(false) end)
    AddTooltip(lockBtn, "Lock", "Stop positioning and save where the splashes are.")

    local posNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    posNote:SetPoint("TOPLEFT", 16, -436)
    posNote:SetText("Position hides this window and shows a small drag-and-lock panel. (also /hst splashes)")

    local function Refresh()
        if not (HC.db and HC.db.comic) then return end
        RefreshControls(masters)
        local randomOn = HC.db.comicRandom
        for _, e in ipairs(ddList) do
            local v = e.get()
            UIDropDownMenu_SetSelectedValue(e.dd, v)
            UIDropDownMenu_SetText(e.dd, labelOf(e.options, v))
            -- Random mode replaces the slots, so grey them out.
            if randomOn then UIDropDownMenu_DisableDropDown(e.dd)
            else UIDropDownMenu_EnableDropDown(e.dd) end
        end
        for i = 1, HC.SPLASH_SLOTS do
            HC.SplashArtTexture(rows[i].preview, HC.db.comic[i].art)
        end
    end
    panel._splashRefresh = Refresh
    panel:SetScript("OnShow", Refresh)
    Refresh()

    RegisterPage(panel, "Splashes", "Hardcore Stat Tracker")
end

-- ---------------------------------------------------------------------------
-- "Famous Last Words" sub-page
-- ---------------------------------------------------------------------------
function HC:BuildLastWordsOptions()
    if HC.lwPanel then return end
    local panel = CreateFrame("Frame")
    panel.name = "Famous Last Words"
    HC.lwPanel = panel

    local function LW() return HC.db.lastWords end

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Famous Last Words")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(560); sub:SetJustifyH("LEFT")
    sub:SetText("When your health drops low, broadcast a random cocky/ironic line to chat - your "
        .. "famous last words. |cffff8080The line auto-types in /say, so use it tastefully.|r  "
        .. "(The screen flash + sound warning is now its own page: Low-Health Alert.)")

    local controls = {}
    local function add(name, label, x, y, get, set, tip)
        local cb = MakeCheck(panel, name, label, x, y, get, set, tip)
        controls[#controls + 1] = cb
        return cb
    end

    add("lw_enabled", "Enable Famous Last Words", 16, -100,
        function() return LW().enabled end, function(v) LW().enabled = v end,
        "Master switch for the low-health chat line.")
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
        function(v) LW().sayThreshold = v end,
        "Health % at which the chat line fires.")
    controls[#controls + 1] = sayThr

    add("lw_useDefaults", "Include the built-in messages (a surprise pool)", 16, -234,
        function() return LW().useDefaults end, function(v) LW().useDefaults = v end,
        "Mixes the addon's hidden built-in lines in with yours (50/50). Uncheck to broadcast ONLY your own messages.")

    local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testBtn:SetSize(90, 22)
    testBtn:SetPoint("TOPLEFT", 16, -270)
    testBtn:SetText("Test")
    testBtn:SetScript("OnClick", function() if HC.TestLastWords then HC:TestLastWords() end end)
    AddTooltip(testBtn, "Test", "Send a sample line to chat right now, as a preview.")

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

    local sf = CreateFrame("ScrollFrame", "HardcoreStatTrackerLWList", box, "UIPanelScrollFrameTemplate")
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
        RefreshControls(controls)
        RenderList()
    end
    panel:SetScript("OnShow", lwRefresh)
    lwRefresh()  -- initial populate, in case OnShow is unreliable on first open

    RegisterPage(panel, "Famous Last Words", "Hardcore Stat Tracker")
end

-- ---------------------------------------------------------------------------
-- "Low-Health Alert" sub-page: a personal screen-flash + sound warning,
-- independent of the Famous Last Words chat line.
-- ---------------------------------------------------------------------------
function HC:BuildAlertOptions()
    if HC.alertPanel then return end
    local panel = CreateFrame("Frame")
    panel.name = "Low-Health Alert"
    HC.alertPanel = panel

    local function LW() return HC.db.lastWords end

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Low-Health Alert")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(560); sub:SetJustifyH("LEFT")
    sub:SetText("A heads-up for YOU when your health drops low: a red screen-edge flash and a "
        .. "warning sound. Nothing is sent to chat - that's the separate Famous Last Words page.")

    local controls = {}
    local enableCB = MakeCheck(panel, "alert_enabled", "Enable low-health alert", 16, -76,
        function() return LW().alertSelf end,
        function(v) LW().alertSelf = v end,
        "Flash a red low-health vignette and play a warning sound when you drop below the threshold.")
    controls[#controls + 1] = enableCB

    local thr = MakeSlider(panel, "alertthr", 30, -120, 5, 60, 1,
        function(v) return "Alert at or below: " .. v .. "%" end,
        function() return LW().alertThreshold or 30 end,
        function(v) LW().alertThreshold = v end,
        "Health % at which the flash + sound fire. Set it higher than the chat-line % for an earlier warning.")
    controls[#controls + 1] = thr

    local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testBtn:SetSize(90, 22)
    testBtn:SetPoint("TOPLEFT", 16, -168)
    testBtn:SetText("Test")
    testBtn:SetScript("OnClick", function() if HC.TestAlert then HC:TestAlert() end end)
    AddTooltip(testBtn, "Test", "Fire the flash + sound right now, as a preview.")

    local function Refresh() if HC.db then RefreshControls(controls) end end
    panel:SetScript("OnShow", Refresh)
    Refresh()

    RegisterPage(panel, "Low-Health Alert", "Hardcore Stat Tracker")
end

-- ---------------------------------------------------------------------------
-- "Announcements" sub-page
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
    sub:SetText("Two separate, low-spam brags after a fight you SURVIVE (never on death, never in "
        .. "raid): personal-best records to your group, and rare clutch-survival hype to your guild.")

    local controls = {}
    local function addc(name, label, x, y, get, set, tip)
        local cb = MakeCheck(panel, name, label, x, y, get, set, tip)
        controls[#controls + 1] = cb
        return cb
    end
    local function adds(...) local s = MakeSlider(panel, ...); controls[#controls + 1] = s; return s end

    addc("an_enabled", "Enable announcements", 16, -70,
        function() return AN().enabled end, function(v) AN().enabled = v end,
        "Master switch for both brags below.")

    -- Left: records -> your group.
    MakeHeader(panel, "To your group (party / say)", 16, -100)
    addc("an_records", "Brag about new personal-best records", 16, -122,
        function() return AN().records end, function(v) AN().records = v end,
        "When you set a new all-time record this fight, post it to party (or /say solo). Pick which records below.")
    adds("anmax", 30, -160, 1, 5, 1,
        function(v) return "Max per fight: " .. v end,
        function() return AN().max or 2 end,
        function(v) AN().max = v end,
        "Caps how many records one fight can post, so a big fight doesn't flood your group.")

    -- Right: clutch hype -> guild (intentionally not tunable).
    MakeHeader(panel, "To guild", 305, -100)
    addc("an_clutch", "Hype clutch survivals", 305, -122,
        function() return AN().clutch end, function(v) AN().clutch = v end,
        "Post a \"survived a fight at X% HP\" line to guild. Records (crits, hits, etc.) never go to guild.")
    local gnote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    gnote:SetPoint("TOPLEFT", 305, -150)
    gnote:SetWidth(290); gnote:SetJustifyH("LEFT")
    gnote:SetText("|cff888888Only fires when you survive a real fight at 5% HP or less, and at most "
        .. "once every 5 minutes - so guild stays quiet. Never fires on death.|r")

    MakeHeader(panel, "Records to announce (to your group)", 16, -256)
    local startY, rowH, colW = -280, 24, 188
    local order = HC.ANNOUNCE_ORDER
    local perCol = math.ceil(#order / 3)
    for i, key in ipairs(order) do
        local def = HC.ANNOUNCE[key]
        local col = math.floor((i - 1) / perCol)
        local row = (i - 1) % perCol
        addc("an_" .. key, def.label, 16 + col * colW, startY - row * rowH,
            function() return AN().stats[key] end,
            function(v) AN().stats[key] = v end,
            "Announce when you beat your " .. def.label:lower() .. ".")
    end

    local function anRefresh() if HC.db then RefreshControls(controls) end end
    panel:SetScript("OnShow", anRefresh)
    anRefresh()

    RegisterPage(panel, "Announcements", "Hardcore Stat Tracker")
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
