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

function HC:ComicPop(slot)
    if not HC.db or HC.db.comicPops == false or splashPlacement then return end
    local conf = HC.db.comic and HC.db.comic[slot]
    if not conf or conf.art == "none" then return end
    local f = GetComicFrame(slot)
    local now = GetTime()
    if now - f.lastPop < 8 then return end  -- early levels set records constantly
    f.lastPop = now
    f.tex:SetTexture(MEDIA .. conf.art)
    f.tex:SetRotation(math.rad(math.random(-TILT, TILT)))
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER",
        conf.x + math.random(-30, 30), conf.y + math.random(-25, 25))
    -- Hold = total show time minus the ~0.28s pop-in and 0.4s fade-out.
    f.aOut:SetStartDelay(math.max(0.1, (HC.db.comicDuration or 2) - 0.68))
    f:Show()
    f.ag:Stop()
    f.ag:Play()
    f.float:Stop()
    f.float:Play()
    if HC.db.comicSound then HC.PlaySplashSound(conf.sound) end
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

-- Enter/leave placement mode. Active slots (art ~= "none") show their art over a
-- green overlay with a marching border, and become draggable; positions save on drop.
function HC:SetSplashPlacement(on)
    if not HC.db or not HC.db.comic then return end
    on = on and true or false
    if on == splashPlacement then return end   -- no-op if unchanged (safe to call on combat start)
    splashPlacement = on
    for slot = 1, HC.SPLASH_SLOTS do
        local conf = HC.db.comic[slot]
        local active = conf and conf.art ~= "none"
        local f = comicFrames[slot]
        if splashPlacement and active then
            f = GetComicFrame(slot)
            f.ag:Stop()
            f.float:Stop()
            f:EnableMouse(true)
            f:SetAlpha(1)
            f.tex:SetTexture(MEDIA .. conf.art)
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
    if splashPlacement then placeAnimator:Show() else placeAnimator:Hide() end
    print("|cffff4444Hardcore Stat Tracker|r: " .. (splashPlacement
        and "drag the splashes where you want them, then click Lock (or /hst splashes) to save."
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
