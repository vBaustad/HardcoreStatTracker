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

local function MakeSlider(parent, name, x, y, lo, hi, step, fmt, getter, setter, tooltip, width)
    local s = CreateFrame("Slider", "HardcoreStatTrackerSlider_" .. name, parent, "OptionsSliderTemplate")
    s:SetWidth(width or 200)
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

    -- LEFT: panel + addon-wide on-screen toggles -------------------------------
    MakeHeader(panel, "Panel", 16, -78)
    chk("shown", "Show the on-screen panel", 16, -100,
        function() return HC.db and HC.db.shown end,
        function(v) HC.db.shown = v; HC:UpdateDisplay() end,
        "Show or hide the mini panel entirely. (Slash: /hst)")
    chk("locked", "Lock the panel in place", 16, -124,
        function() return HC.db and HC.db.locked end,
        function(v) HC.db.locked = v end,
        "Stops the panel from being dragged by accident. Unlock to reposition it. (Bar mode is always edge-anchored.)")

    MakeHeader(panel, "On screen", 16, -158)
    chk("mobtip", "Show mob damage history on tooltips", 16, -180,
        function() return HC.db and HC.db.mobTooltip end,
        function(v) HC.db.mobTooltip = v end,
        "Adds \"Has hit you for up to X\" to the tooltip of any mob that has hurt one of your characters before.")
    chk("minimap", "Show a minimap button", 16, -204,
        function() return HC.db and HC.db.minimapButton end,
        function(v) HC.db.minimapButton = v; if HC.ApplyMinimapButton then HC:ApplyMinimapButton() end end,
        "A button on the minimap: left-click for the full window, right-click for settings, drag to reposition.")

    local miniNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    miniNote:SetPoint("TOPLEFT", 16, -242)
    miniNote:SetWidth(290); miniNote:SetJustifyH("LEFT")
    miniNote:SetText("Mini-panel size, opacity, wide-bar mode and which stats show now live on the Mini Panel tab.")

    -- RIGHT: full window sliders -----------------------------------------------
    MakeHeader(panel, "Full window (the [+] window)", 330, -78)
    sld("fullscale", 360, -104, 0.7, 1.6, 0.05,
        function(v) return ("Scale: %.2f"):format(v) end,
        function() return HC.db and HC.db.fullScale or 1 end,
        function(v) HC.db.fullScale = v; if HC.fullFrame then HC.fullFrame:SetScale(v) end end,
        "Size of the full stats window. Also adjustable live from its Display button.")
    sld("fullopacity", 360, -144, 0.2, 1.0, 0.05,
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
    title:SetText("Mini Panel")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(560); sub:SetJustifyH("LEFT")
    sub:SetText("Top section: how the panel looks, plus the full-width bar. The tabs below pick which "
        .. "stats appear (the full window always lists everything). Hover anything for details.")

    -- key -> settings label, and category title -> keys, from the master stat list.
    local labelOf, keysOf = {}, {}
    for _, s in ipairs(HC.STATS) do labelOf[s[1]] = s[2] end
    for _, g in ipairs(HC.STAT_GROUPS) do keysOf[g[1]] = g[2] end

    local controls = {}

    -- ===== Display settings: ALWAYS shown, above the stat tabs =====
    MakeHeader(panel, "Layout", 16, -60)
    controls[#controls + 1] = MakeCheck(panel, "barmode", "Full-width bar (Titan-style)", 16, -82,
        function() return HC.db and HC.db.miniMode == "bar" end,
        function(v) HC.db.miniMode = v and "bar" or "panel"; if HC.ApplyMiniMode then HC:ApplyMiniMode() end end,
        "Replace the stacked panel with a single full-width bar across the top or bottom of the screen - stats laid out left to right, fitting as many as will show.")
    controls[#controls + 1] = MakeCheck(panel, "barscreen", "Adjust screen (push the minimap down)", 16, -104,
        function() return HC.db and HC.db.barScreenAdjust end,
        function(v) HC.db.barScreenAdjust = v; if HC.ApplyScreenAdjust then HC:ApplyScreenAdjust() end end,
        "Push the minimap down so the bar doesn't cover it (the buffs and quest tracker hang off the minimap, so they move too). May need tweaking alongside TitanPanel.")
    controls[#controls + 1] = MakeCheck(panel, "combattimer", "Show in-combat timer", 16, -126,
        function() return HC.db and HC.db.combatTimer ~= false end,
        function(v) HC.db.combatTimer = v; HC:UpdateDisplay() end,
        "Adds a live \"In Combat\" entry showing fight time and damage taken. Stacked mini-panel only - the bar never shows it.")
    controls[#controls + 1] = MakeCheck(panel, "minihighlight", "Highlight new records", 16, -148,
        function() return HC.db and HC.db.miniHighlight ~= false end,
        function(v) HC.db.miniHighlight = v end,
        "Animate a dashed gold border around an entry for a few seconds after it sets a new record.")

    MakeHeader(panel, "Size & opacity", 340, -60)
    controls[#controls + 1] = MakeSlider(panel, "scale", 370, -84, 0.7, 2.0, 0.1,
        function(v) return ("Scale: %.1f"):format(v) end,
        function() return HC.db and HC.db.scale or 1 end,
        function(v) HC.db.scale = v; HC:UpdateDisplay() end,
        "Overall size of the mini panel. (Panel mode; the bar sizes to its text instead.)")
    controls[#controls + 1] = MakeSlider(panel, "font", 370, -122, 9, 20, 1,
        function(v) return "Text size: " .. v end,
        function() return HC.db and HC.db.fontSize or 12 end,
        function(v) HC.db.fontSize = v; HC:UpdateDisplay() end,
        "Font size of the entries (and the bar's height).")
    controls[#controls + 1] = MakeSlider(panel, "miniopacity", 370, -160, 0.2, 1.0, 0.05,
        function(v) return ("Background: %.0f%%"):format(v * 100) end,
        function() return HC.db and HC.db.miniAlpha or 0.8 end,
        function(v) HC.db.miniAlpha = v; if HC.ApplyMiniAlpha then HC:ApplyMiniAlpha() end end,
        "How solid the dark background is.")
    -- ===== Full-width bar: stat direction + custom size/position (all bar-only) =====
    -- One row: where the stats fill the bar, then its width / horizontal nudge /
    -- vertical nudge. The narrow strip is for streamers whose capture is narrower
    -- than an ultrawide game.
    MakeHeader(panel, "Full-width bar", 16, -174)

    local alignNames = { left = "Left", center = "Center", right = "Right" }
    local alignOrder = { "left", "center", "right" }
    local alignBtn = HC.MakeButton(panel, "", 110, 20)
    alignBtn:SetPoint("TOPLEFT", 16, -202)
    local function setAlignText() alignBtn:SetText("Stats: " .. (alignNames[(HC.db and HC.db.barAlign) or "left"] or "Left")) end
    alignBtn:SetScript("OnClick", function()
        local cur, idx = (HC.db.barAlign or "left"), 1
        for i, a in ipairs(alignOrder) do if a == cur then idx = i end end
        HC.db.barAlign = alignOrder[(idx % #alignOrder) + 1]
        setAlignText()
        if HC.ApplyMiniMode then HC:ApplyMiniMode() end
    end)
    setAlignText()
    AddTooltip(alignBtn, "Stat direction",
        "Which way the stats fill the bar. Left = start at the left, grow right. Right = start at the right, grow left. Center = always centred. Click to cycle. (Bar mode only.)")

    controls[#controls + 1] = MakeSlider(panel, "barwidth", 150, -202, 0, 3840, 20,
        function(v) return v <= 0 and "Width: Full" or ("Width: %d"):format(v) end,
        function() return HC.db and HC.db.barWidth or 0 end,
        function(v) HC.db.barWidth = v; if HC.ApplyMiniMode then HC:ApplyMiniMode() end end,
        "Bar width in px (Full = whole screen). Pair a custom width with 'Stats: Center' and the X offset to keep the bar inside a narrower stream capture. (Bar mode only.)", 120)

    controls[#controls + 1] = MakeSlider(panel, "barx", 300, -202, -1920, 1920, 10,
        function(v) return v == 0 and "X: Centered" or ("X: %d"):format(v) end,
        function() return HC.db and HC.db.barX or 0 end,
        function(v) HC.db.barX = v; if HC.ApplyMiniMode then HC:ApplyMiniMode() end end,
        "Slide a custom-width bar left or right (centred on screen at 0). No effect at Full width. (Bar mode only.)", 120)

    controls[#controls + 1] = MakeSlider(panel, "baroffset", 450, -202, 0, 200, 2,
        function(v) return ("Y: %d"):format(v) end,
        function() return HC.db and HC.db.barOffset or 0 end,
        function(v) HC.db.barOffset = v; if HC.ApplyMiniMode then HC:ApplyMiniMode() end end,
        "Nudge the bar down from the top edge - handy to sit it just below Titan Panel or another bar. (Bar mode only.)", 120)

    -- Divider between the always-on settings and the stat tabs.
    local div = panel:CreateTexture(nil, "ARTWORK")
    div:SetColorTexture(0.6, 0.1, 0.1, 0.6); div:SetHeight(1)
    div:SetPoint("TOPLEFT", 16, -234); div:SetPoint("TOPRIGHT", -16, -234)

    -- ===== Stats to show: tabbed visibility grids =====
    local statsCap = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statsCap:SetPoint("TOPLEFT", 16, -242)
    statsCap:SetText("|cffffd100Stats to show|r")

    -- Show all / Hide all every stat at once.
    local function SetAllStats(v)
        for _, s in ipairs(HC.STATS) do HC:SetVisible(s[1], v) end
        RefreshControls(controls)
    end
    local showAllBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    showAllBtn:SetSize(80, 22)
    showAllBtn:SetPoint("TOPRIGHT", -100, -238)
    showAllBtn:SetText("Show all")
    showAllBtn:SetScript("OnClick", function() SetAllStats(true) end)
    local hideAllBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    hideAllBtn:SetSize(80, 22)
    hideAllBtn:SetPoint("TOPRIGHT", -14, -238)
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

    -- Stat categories, rebalanced so no single tab is overloaded.
    local TABS = {
        { "Survival", { "Survival" } },
        { "Combat",   { "Combat" } },
        { "Heal/Pet", { "Healing", "Pet", "Group" } },
        { "World",    { "Adventure", "Profession", "Character", "Account" } },
        { "Wealth",   { "Wealth", "Mak'gora" } },
    }
    local CONTENT_Y = -288
    local containers, tabBtns = {}, {}
    local function ShowTab(active)
        for i, c in ipairs(containers) do c:SetShown(i == active) end
        for i, b in ipairs(tabBtns) do b:SetSelected(i == active) end
    end

    -- Compact themed tab buttons (match the full window's look).
    local bx, BW, BH, GAP = 16, 96, 22, 6
    for i, t in ipairs(TABS) do
        local b = HC.MakeButton(panel, t[1], BW, BH)
        b:SetPoint("TOPLEFT", bx, -264)
        b:SetScript("OnClick", function() ShowTab(i) end)
        tabBtns[i] = b
        bx = bx + BW + GAP

        local c = CreateFrame("Frame", nil, panel)
        c:SetPoint("TOPLEFT"); c:SetPoint("BOTTOMRIGHT")
        containers[i] = c
        local y = CONTENT_Y
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
    sub:SetText("A comic-book POW! pops on screen when you set a record. Set up to six: click a "
        .. "slot's art to pick the picture, choose which record triggers it and an optional sound, "
        .. "then use Position to drag each one where you want it.")

    local masters = {}   -- checkboxes / sliders refreshed from getters
    local ddList  = {}   -- { dd, options, get } dropdowns to refresh
    local rows    = {}   -- [i] = { art = <thumbnail texture> } for refresh

    masters[#masters + 1] = MakeCheck(panel, "comicpops", "Show comic splashes (master)", 16, -74,
        function() return HC.db and HC.db.comicPops end,
        function(v) HC.db.comicPops = v end,
        "Master switch for the whole feature. Off = nothing pops, whatever the slots below say.")
    masters[#masters + 1] = MakeSlider(panel, "comicdur", 330, -84, 1, 6, 0.5,
        function(v) return ("Show for: %.1fs"):format(v) end,
        function() return HC.db and HC.db.comicDuration or 2 end,
        function(v) HC.db.comicDuration = v end,
        "How long each splash stays on screen, start to finish (pop-in + hold + fade-out).")
    masters[#masters + 1] = MakeCheck(panel, "comicrandom", "Random art on every crit (instead of specific records)", 16, -98,
        function() return HC.db and HC.db.comicRandom end,
        function(v) HC.db.comicRandom = v; if panel._splashRefresh then panel._splashRefresh() end end,
        "On: a random art pops on EVERY crit (about every 2s) at a random one of your six spots, with a random sound - the per-slot art/trigger/sound below are ignored. Position still sets where they can land.")

    local soundHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    soundHint:SetPoint("TOPLEFT", 16, -122)
    soundHint:SetText("Splash sounds use the Sound Effects channel - set its volume in the game's Sound options.")

    local function labelOf(options, value)
        for _, opt in ipairs(options) do if opt[1] == value then return opt[2] end end
        return value or "?"
    end

    -- Custom dropdown. Deliberately NOT Blizzard's UIDropDownMenu: that system uses
    -- shared globals (UIDROPDOWNMENU_OPEN_MENU etc.) that the LFG "Looking For Group"
    -- browse also uses, and our insecure use of it tainted that path, blocking the
    -- protected Search() (listings wouldn't load). This is fully self-contained:
    -- a themed button + a shared popup list, touching no shared/secure state.
    local ddMenu
    local function OpenDDMenu(dd)
        if not ddMenu then
            ddMenu = CreateFrame("Frame", "HardcoreStatTrackerDDMenu", UIParent, "BackdropTemplate")
            ddMenu:SetFrameStrata("FULLSCREEN_DIALOG"); ddMenu:SetToplevel(true)
            ddMenu:SetClampedToScreen(true); ddMenu:EnableMouse(true)
            ddMenu:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            ddMenu:SetBackdropColor(0.05, 0.04, 0.04, 0.97)
            ddMenu:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)
            tinsert(UISpecialFrames, "HardcoreStatTrackerDDMenu")   -- Escape closes
            ddMenu.rows = {}
        end
        local f = ddMenu
        if f:IsShown() and f._owner == dd then f:Hide(); return end   -- click again = toggle off
        f._owner = dd
        local opts, RH, W = dd._options, 18, math.max(dd._width or 100, 70)
        for i, opt in ipairs(opts) do
            local r = f.rows[i]
            if not r then
                r = CreateFrame("Button", nil, f)
                local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.25)
                r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                r.text:SetPoint("LEFT", 6, 0); r.text:SetJustifyH("LEFT")
                f.rows[i] = r
            end
            r:SetSize(W - 8, RH)
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * RH)
            r.text:SetText(opt[2]); r._value = opt[1]
            r:SetScript("OnClick", function(self)
                dd._setV(self._value); dd:RefreshText()
                if dd._onPick then dd._onPick(self._value) end
                f:Hide()
            end)
            r:Show()
        end
        for i = #opts + 1, #f.rows do f.rows[i]:Hide() end
        f:SetSize(W, 8 + #opts * RH)
        f:ClearAllPoints(); f:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
        f:Show(); f:Raise()
    end

    local function MakeDD(suffix, ddX, ddY, width, options, getV, setV, onPick)
        local dd = HC.MakeButton(panel, "", width, 22)
        dd:SetPoint("TOPLEFT", ddX, ddY)
        dd._options, dd._getV, dd._setV, dd._onPick, dd._width = options, getV, setV, onPick, width
        function dd:RefreshText() self:SetText(labelOf(self._options, self._getV())) end
        dd:SetScript("OnClick", function(self) OpenDDMenu(self) end)
        dd:RefreshText()
        ddList[#ddList + 1] = dd
        return dd
    end

    -- ---- Visual art picker: a shared popup grid showing every art image ----
    local MEDIA = "Interface\\AddOns\\HardcoreStatTracker\\Media\\"
    local ART_OPTS = { { "none", "Off" } }
    for _, o in ipairs(HC.SPLASH_ART) do ART_OPTS[#ART_OPTS + 1] = o end

    local artPicker
    local function GetArtPicker()
        if artPicker then return artPicker end
        local f = CreateFrame("Frame", "HardcoreStatTrackerArtPicker", UIParent, "BackdropTemplate")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0.05, 0.04, 0.04, 0.97)
        f:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)
        tinsert(UISpecialFrames, "HardcoreStatTrackerArtPicker")   -- Escape closes it

        local heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        heading:SetPoint("TOP", 0, -10)
        heading:SetText("|cffff4444Choose art|r")

        local COLS, CELL, GAP, TOP = 5, 52, 8, -30
        f.cells = {}
        for idx, opt in ipairs(ART_OPTS) do
            local col, r = (idx - 1) % COLS, math.floor((idx - 1) / COLS)
            local cell = CreateFrame("Button", nil, f)
            cell:SetSize(CELL, CELL + 12)
            cell:SetPoint("TOPLEFT", 12 + col * (CELL + GAP), TOP - r * (CELL + 12 + GAP))

            local bg = cell:CreateTexture(nil, "BACKGROUND")
            bg:SetPoint("TOPLEFT", 0, 0); bg:SetPoint("BOTTOMRIGHT", 0, 12)
            bg:SetColorTexture(0, 0, 0, 0.4)

            local tex = cell:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", 3, -3); tex:SetPoint("BOTTOMRIGHT", -3, 15)
            if opt[1] == "none" then
                tex:Hide()
                local off = cell:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge")
                off:SetPoint("CENTER", 0, 6); off:SetText("Off")
            else
                tex:SetTexture(MEDIA .. opt[1])
            end

            local lbl = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lbl:SetPoint("BOTTOM", 0, 0); lbl:SetText(opt[2])

            local hover = cell:CreateTexture(nil, "HIGHLIGHT")
            hover:SetPoint("TOPLEFT", 0, 0); hover:SetPoint("BOTTOMRIGHT", 0, 12)
            hover:SetColorTexture(1, 0.82, 0, 0.25)

            local check = cell:CreateTexture(nil, "OVERLAY")
            check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            check:SetSize(22, 22); check:SetPoint("TOPRIGHT", 2, 14); check:Hide()
            cell.check, cell.art = check, opt[1]

            cell:SetScript("OnClick", function(self)
                if f.targetSlot then
                    HC.db.comic[f.targetSlot].art = self.art
                    if f.onPick then f.onPick(self.art) end
                end
                f:Hide()
            end)
            f.cells[idx] = cell
        end

        local rowsN = math.ceil(#ART_OPTS / COLS)
        f:SetSize(24 + COLS * CELL + (COLS - 1) * GAP, 40 + rowsN * (CELL + 12 + GAP))
        f:Hide()
        artPicker = f
        return f
    end

    local function OpenArtPicker(slotIndex, anchorBtn, onPick)
        local f = GetArtPicker()
        f.targetSlot, f.onPick = slotIndex, onPick
        local cur = HC.db.comic[slotIndex].art
        for _, cell in ipairs(f.cells) do cell.check:SetShown(cell.art == cur) end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -4)
        f:Show(); f:Raise()
    end

    -- ---- Per-slot rows: art thumbnail (opens picker) + trigger + sound ----
    local function cap(text, x, y)
        local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", x, y); fs:SetText("|cffffd100" .. text .. "|r")
    end
    cap("Art",         48, -148)
    cap("Triggers on", 196, -148)
    cap("Sound",       380, -148)

    for i = 1, HC.SPLASH_SLOTS do
        local baseY = -166 - (i - 1) * 38
        local function slot() return HC.db.comic[i] end

        local num = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        num:SetPoint("TOPLEFT", 22, baseY - 10)
        num:SetText(i .. ".")

        -- Clickable art thumbnail: shows the chosen art, opens the visual picker.
        local artBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
        artBtn:SetSize(34, 34)
        artBtn:SetPoint("TOPLEFT", 44, baseY)
        artBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        artBtn:SetBackdropColor(0, 0, 0, 0.4)
        artBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
        local thumb = artBtn:CreateTexture(nil, "ARTWORK")
        thumb:SetPoint("TOPLEFT", 3, -3); thumb:SetPoint("BOTTOMRIGHT", -3, 3)
        rows[i] = { art = thumb, btn = artBtn }
        AddTooltip(artBtn, "Splash art", "Click to choose the picture for this splash (or Off to disable the slot).")
        artBtn:SetScript("OnClick", function()
            OpenArtPicker(i, artBtn, function(art) HC.SplashArtTexture(thumb, art) end)
        end)

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
        for _, dd in ipairs(ddList) do
            dd:RefreshText()
            -- Random-on-crit mode ignores the per-slot dropdowns, so grey them out.
            if randomOn then dd:Disable(); dd:SetAlpha(0.4) else dd:Enable(); dd:SetAlpha(1) end
        end
        for i = 1, HC.SPLASH_SLOTS do
            HC.SplashArtTexture(rows[i].art, HC.db.comic[i].art)
            local btn = rows[i].btn
            if btn then
                if randomOn then
                    btn:Disable(); rows[i].art:SetDesaturated(true); rows[i].art:SetAlpha(0.4)
                else
                    btn:Enable(); rows[i].art:SetDesaturated(false); rows[i].art:SetAlpha(1)
                end
            end
        end
    end
    panel._splashRefresh = Refresh
    panel:SetScript("OnShow", Refresh)
    panel:SetScript("OnHide", function()
        if artPicker then artPicker:Hide() end
        if ddMenu then ddMenu:Hide() end
    end)
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
