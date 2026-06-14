local ADDON, HC = ...

-- ---------------------------------------------------------------------------
-- Comic-book splashes. Up to 6 configurable slots; each picks its art, the
-- record stat that triggers it, and an optional sound, and can be dragged into
-- place. art = "none" disables a slot.
-- ---------------------------------------------------------------------------

-- Record stats a splash can be linked to (key -> label for the dropdown).
HC.SPLASH_TRIGGERS = {
    { "highestCrit",   "Highest Crit" },
    { "biggestMelee",  "Biggest Melee Hit" },
    { "biggestRanged", "Biggest Ranged Hit" },
    { "biggestSpell",  "Biggest Spell Hit" },
    { "biggestAbility","Biggest Ability Hit" },
    { "biggestHit",    "Biggest Hit Taken" },
    { "closestCall",   "Closest Call (new low)" },
    { "nearestDeath",  "Nearest Death" },
    { "highestFall",   "Highest Fall" },
    { "toughestFoe",   "Toughest Foe" },
    { "mostFoes",      "Most Foes at Once" },
    { "clutchSaves",   "Clutch Save" },
    { "longestFight",  "Longest Fight" },
    { "mostDmgFight",  "Most Dmg in One Fight" },
    { "untouched",     "Untouched Streak" },
    { "biggestHeal",   "Biggest Heal" },
    { "playersSaved",  "Player Saved" },
}

-- Art a splash can show (texture key in Media\ -> dropdown label).
HC.SPLASH_ART = {
    { "pow",  "POW!" },
    { "boom", "BOOM!" },
    { "zap",  "ZAP!" },
    { "ouch", "OUCH!" },
    { "bang", "BANG!" },
    { "wow",  "WOW!" },
}

-- Sound a splash can play on pop (file key in Sounds\ -> dropdown label).
HC.SPLASH_SOUNDS = {
    { "none", "None" },
    { "pow",  "Pow" },
    { "bonk", "Bonk" },
    { "honk", "Honk" },
    { "slap", "Slap" },
    { "pew",  "Pew" },
}

local MEDIA  = "Interface\\AddOns\\HardcoreStatTracker\\Media\\"
local SOUNDS = "Interface\\AddOns\\HardcoreStatTracker\\Sounds\\"

-- Play a splash sound by key (shared with the settings preview). "none"/nil is silent.
function HC.PlaySplashSound(soundKey)
    if soundKey and soundKey ~= "none" then
        PlaySoundFile(SOUNDS .. soundKey .. ".ogg", "Master")
    end
end

HC.SPLASH_SLOTS = 6        -- how many configurable splash slots exist
local TILT = 14            -- max degrees a splash leans when it pops

local splashPlacement = false
local comicFrames = {}     -- [slotIndex] = frame

-- Point a texture at a splash art ("none"/nil -> hidden). Shared with the
-- settings preview thumbnails.
function HC.SplashArtTexture(tex, art)
    if art and art ~= "none" then
        tex:SetTexture(MEDIA .. art)
        tex:Show()
    else
        tex:Hide()
    end
end

local function SaveSlotPos(f)
    local cx, cy = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local conf = HC.db and HC.db.comic and HC.db.comic[f.slot]
    if cx and ux and conf then
        conf.x = math.floor(cx - ux + 0.5)
        conf.y = math.floor(cy - uy + 0.5)
    end
end

local function StopSplashDrag(f)
    if not f.moving then return end
    f.moving = false
    f:StopMovingOrSizing()
    SaveSlotPos(f)
end

-- Lazily attach placement-mode decor: a faded-green fill + a dashed marching-ants
-- border, shown only while positioning so it reads as "this is movable".
local function EnsureDecor(f)
    if f.placeBG then return end
    f.placeBG = f:CreateTexture(nil, "BACKGROUND")
    f.placeBG:SetAllPoints()
    f.placeBG:SetColorTexture(0.2, 1, 0.2, 0.18)
    f.placeBG:Hide()
    local function edge(vert)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetTexture(MEDIA .. (vert and "dash_v" or "dash_h"), "REPEAT", "REPEAT")
        t:SetVertexColor(0.3, 1, 0.3)
        t:Hide()
        return t
    end
    local top, bottom, left, right = edge(false), edge(false), edge(true), edge(true)
    local TH = 3
    top:SetPoint("TOPLEFT", 0, 0);       top:SetPoint("TOPRIGHT", 0, 0);       top:SetHeight(TH)
    bottom:SetPoint("BOTTOMLEFT", 0, 0); bottom:SetPoint("BOTTOMRIGHT", 0, 0); bottom:SetHeight(TH)
    left:SetPoint("TOPLEFT", 0, 0);      left:SetPoint("BOTTOMLEFT", 0, 0);    left:SetWidth(TH)
    right:SetPoint("TOPRIGHT", 0, 0);    right:SetPoint("BOTTOMRIGHT", 0, 0);  right:SetWidth(TH)
    f.ants = { top, bottom, left, right }
end

local function ShowDecor(f, on)
    EnsureDecor(f)
    if on then f.placeBG:Show() else f.placeBG:Hide() end
    for _, t in ipairs(f.ants) do if on then t:Show() else t:Hide() end end
end

local function GetComicFrame(slot)
    local f = comicFrames[slot]
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f.slot = slot
    f:SetSize(150, 150)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(false)
    f:Hide()
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.lastPop = -99

    -- Scale from/to, guarding the API name across client builds.
    local function scaleFromTo(a, fx, fy, tx, ty)
        if a.SetScaleFrom then a:SetScaleFrom(fx, fy); a:SetScaleTo(tx, ty)
        else a:SetFromScale(fx, fy); a:SetToScale(tx, ty) end
    end

    -- "Poof": fade in fast while popping from tiny, overshoot past full size,
    -- then settle back - then hold a beat and fade out.
    f.ag = f:CreateAnimationGroup()
    local aIn = f.ag:CreateAnimation("Alpha")
    aIn:SetFromAlpha(0); aIn:SetToAlpha(1); aIn:SetDuration(0.06); aIn:SetOrder(1)
    local pop = f.ag:CreateAnimation("Scale")
    scaleFromTo(pop, 0.1, 0.1, 1.18, 1.18)
    pop:SetOrigin("CENTER", 0, 0); pop:SetDuration(0.16); pop:SetOrder(1); pop:SetSmoothing("OUT")
    local settle = f.ag:CreateAnimation("Scale")
    scaleFromTo(settle, 1.18, 1.18, 1.0, 1.0)
    settle:SetOrigin("CENTER", 0, 0); settle:SetDuration(0.12); settle:SetOrder(2); settle:SetSmoothing("IN_OUT")
    local aOut = f.ag:CreateAnimation("Alpha")
    aOut:SetFromAlpha(1); aOut:SetToAlpha(0); aOut:SetDuration(0.4); aOut:SetStartDelay(0.9); aOut:SetOrder(3)
    f.aOut = aOut   -- hold time (start delay) is set per-pop from the user's "show for" setting
    f.ag:SetScript("OnFinished", function()
        if f.float then f.float:Stop() end
        if not splashPlacement then f:Hide() end
    end)

    -- Gentle floating bob while the splash is up (independent looping group).
    f.float = f:CreateAnimationGroup()
    f.float:SetLooping("BOUNCE")
    local bob = f.float:CreateAnimation("Translation")
    bob:SetOffset(0, 4); bob:SetDuration(0.5); bob:SetSmoothing("IN_OUT")

    -- Dragging, active only while placement mode is on.
    f:SetScript("OnMouseDown", function(self, btn)
        if splashPlacement and btn == "LeftButton" then
            self.moving = true
            self:StartMoving()
        end
    end)
    f:SetScript("OnMouseUp", function(self) StopSplashDrag(self) end)
    f:SetScript("OnUpdate", function(self)
        if self.moving and not IsMouseButtonDown("LeftButton") then StopSplashDrag(self) end
    end)

    comicFrames[slot] = f
    return f
end

-- Low-level: play one comic pop on frame f with the given art/position/sound,
-- honoring a per-frame cooldown so it can't machine-gun.
local function PopFrame(f, art, x, y, soundKey, cd)
    local now = GetTime()
    if now - f.lastPop < (cd or 8) then return end
    f.lastPop = now
    f.tex:SetTexture(MEDIA .. art)
    f.tex:SetRotation(math.rad(math.random(-TILT, TILT)))
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x, y)
    -- Hold = total show time minus the ~0.28s pop-in and 0.4s fade-out.
    f.aOut:SetStartDelay(math.max(0.1, (HC.db.comicDuration or 2) - 0.68))
    f:Show()
    f.ag:Stop(); f.ag:Play()
    f.float:Stop(); f.float:Play()
    if soundKey and soundKey ~= "none" then HC.PlaySplashSound(soundKey) end
end

-- Record-driven splash for a configured slot. Disabled in "random art on crit"
-- mode, which replaces the specific slots entirely.
function HC:ComicPop(slot)
    if not HC.db or HC.db.comicPops == false or splashPlacement then return end
    if HC.db.comicRandom then return end
    local conf = HC.db.comic and HC.db.comic[slot]
    if not conf or conf.art == "none" then return end
    PopFrame(GetComicFrame(slot), conf.art,
        conf.x + math.random(-30, 30), conf.y + math.random(-25, 25), conf.sound, 8)
end

-- "Random art on crit" mode: a random comic art pops on every crit (~2s
-- cooldown), at a random spot, with a random sound. Driven from the combat log.
local RANDOM_CD = 2
function HC:RandomCritSplash()
    if not HC.db or HC.db.comicPops == false or not HC.db.comicRandom or splashPlacement then return end
    local art = HC.SPLASH_ART[math.random(#HC.SPLASH_ART)][1]
    -- Random mode has no per-slot dropdown, so it always uses a random sound.
    local sound
    local pool = {}
    for _, s in ipairs(HC.SPLASH_SOUNDS) do if s[1] ~= "none" then pool[#pool + 1] = s[1] end end
    if #pool > 0 then sound = pool[math.random(#pool)] end
    -- Land at a random one of the 6 positioned spots (jittered), so the player
    -- controls where random splashes can appear via Position splashes.
    local spot = HC.db.comic[math.random(HC.SPLASH_SLOTS)]
    local x = (spot and spot.x or 0) + math.random(-25, 25)
    local y = (spot and spot.y or 0) + math.random(-25, 25)
    PopFrame(GetComicFrame(0), art, x, y, sound, RANDOM_CD)
end

-- Remember when a record was set, so the full window can flag it as "new!".
function HC:StampRecord(statKey)
    if HC.db and HC.db.recordStamps then
        local t = time()
        HC.db.recordStamps[statKey] = t
        HC.lastRecordStamp = t   -- lets the mini-panel highlight idle cheaply
    end
end

-- Called wherever a record stat improves; stamps it and pops every slot wired to it.
function HC:ComicEvent(statKey)
    if not HC.db then return end
    HC:StampRecord(statKey)
    if not HC.db.comic then return end
    for slot = 1, HC.SPLASH_SLOTS do
        local conf = HC.db.comic[slot]
        if conf and conf.art ~= "none" and conf.stat == statKey then HC:ComicPop(slot) end
    end
end

-- Marching-ants animator: scrolls the dashed borders while placement mode is on.
local placeOffset = 0
local placeAnimator = CreateFrame("Frame", nil, UIParent)
placeAnimator:Hide()
placeAnimator:SetScript("OnUpdate", function(_, elapsed)
    placeOffset = (placeOffset + elapsed * 0.9) % 1
    local r = 150 / 8   -- frame size / dash tile
    for _, f in pairs(comicFrames) do
        if f:IsShown() and f.ants then
            f.ants[1]:SetTexCoord( placeOffset,  placeOffset + r, 0, 1)   -- top
            f.ants[2]:SetTexCoord(-placeOffset, -placeOffset + r, 0, 1)   -- bottom
            f.ants[3]:SetTexCoord(0, 1, -placeOffset, -placeOffset + r)   -- left
            f.ants[4]:SetTexCoord(0, 1,  placeOffset,  placeOffset + r)   -- right
        end
    end
end)

-- Floating control window shown while positioning splashes. During placement the
-- Blizzard settings window is hidden (it covers the splashes), so this little
-- panel - styled like the full window's Quick Settings popup - carries the only
-- two actions you need: lock them down, or hop back to settings.
local placeControls
local function EnsurePlacementControls()
    if placeControls then return placeControls end
    local f = CreateFrame("Frame", "HardcoreStatTrackerSplashPlace", UIParent, "BackdropTemplate")
    f:SetSize(232, 126)
    f:SetFrameStrata("FULLSCREEN_DIALOG")   -- above the HIGH-strata splashes
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.04, 0.04, 0.95)
    f:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)
    tinsert(UISpecialFrames, "HardcoreStatTrackerSplashPlace")  -- Escape locks & closes
    f:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    f:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        if p and HC.db then HC.db.splashCtrlPoint = { p, rp, math.floor(x), math.floor(y) } end
    end)
    -- Closing it (Escape / no close button needed) means "I'm done" -> lock.
    f:SetScript("OnHide", function()
        if splashPlacement then HC:SetSplashPlacement(false) end
    end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cffff4444Positioning Splashes|r")

    local note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOP", 0, -30)
    note:SetWidth(204); note:SetJustifyH("CENTER")
    note:SetText("Drag each splash where you want it.")

    local lock = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    lock:SetSize(204, 24)
    lock:SetPoint("TOP", 0, -56)
    lock:SetText("Lock positions")
    lock:SetScript("OnClick", function() HC:SetSplashPlacement(false) end)

    local back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    back:SetSize(204, 24)
    back:SetPoint("TOP", 0, -86)
    back:SetText("Open settings panel")
    back:SetScript("OnClick", function()
        HC:SetSplashPlacement(false)
        if HC.OpenOptions then HC:OpenOptions() end
    end)

    placeControls = f
    return f
end

-- Close the Blizzard settings window (modern Settings panel or the legacy one)
-- so it isn't sitting on top of the splashes during placement.
local function HideSettingsWindow()
    if SettingsPanel and SettingsPanel:IsShown() then
        HideUIPanel(SettingsPanel)
    elseif InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
        HideUIPanel(InterfaceOptionsFrame)
    end
end

-- Enter/leave placement mode. Active slots (art ~= "none") show their art over a
-- green overlay with a marching border, and become draggable; positions save on drop.
function HC:SetSplashPlacement(on)
    if not HC.db or not HC.db.comic then return end
    on = on and true or false
    if on == splashPlacement then return end   -- no-op if unchanged (safe to call on combat start)
    splashPlacement = on
    for slot = 1, HC.SPLASH_SLOTS do
        local conf = HC.db.comic[slot]
        -- Specific mode positions the enabled slots; random mode positions ALL 6
        -- (they are the spots a random crit splash can land on).
        local active = conf and (HC.db.comicRandom or conf.art ~= "none")
        local f = comicFrames[slot]
        if splashPlacement and active then
            f = GetComicFrame(slot)
            f.ag:Stop()
            f.float:Stop()
            f:EnableMouse(true)
            f:SetAlpha(1)
            -- Show the slot's art, or a sample (random-mode slots may be "none").
            local showArt = (conf.art and conf.art ~= "none") and conf.art
                or HC.SPLASH_ART[((slot - 1) % #HC.SPLASH_ART) + 1][1]
            f.tex:SetTexture(MEDIA .. showArt)
            f.tex:SetRotation(0)
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", conf.x, conf.y)
            ShowDecor(f, true)
            f:Show()
        elseif f then
            StopSplashDrag(f)
            f.float:Stop()
            f:EnableMouse(false)
            ShowDecor(f, false)
            f:Hide()
        end
    end
    if splashPlacement then
        placeAnimator:Show()
        HideSettingsWindow()
        local f = EnsurePlacementControls()
        f:ClearAllPoints()
        local p = HC.db.splashCtrlPoint
        if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("TOP", 0, -140) end
        f:Show()
    else
        placeAnimator:Hide()
        if placeControls then placeControls:Hide() end
    end
    print("|cffff4444Hardcore Stat Tracker|r: " .. (splashPlacement
        and "drag the splashes where you want them, then click Lock positions (or /hst splashes) to save."
        or "splash positions saved."))
end

function HC:ToggleSplashPlacement()
    HC:SetSplashPlacement(not splashPlacement)
end

-- Debug helper: zero the per-hit records (and splash cooldowns) so the next hit
-- sets a "new record" and pops the splash again. (/hst resethits)
function HC:ResetHitRecords()
    if not HC.db then return end
    HC.db.highestCrit, HC.db.highestCritSpell, HC.db.highestCritTarget = 0, nil, nil
    HC.db.biggestMelee, HC.db.biggestMeleeTarget = 0, nil
    HC.db.biggestRanged, HC.db.biggestRangedTarget = 0, nil
    HC.db.biggestSpell, HC.db.biggestSpellName, HC.db.biggestSpellTarget = 0, nil, nil
    for _, f in pairs(comicFrames) do f.lastPop = -99 end
    HC:UpdateDisplay()
    print("|cffff4444Hardcore Stat Tracker|r: hit records reset (crit / melee / ranged / spell). Next hit pops the splash.")
end
