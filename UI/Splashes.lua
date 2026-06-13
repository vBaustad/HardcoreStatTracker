local ADDON, HC = ...

-- ---------------------------------------------------------------------------
-- Comic-book splashes (POW/BOOM/ZAP). Each splash can be toggled, dragged to
-- a new position (placement mode), and linked to any record stat in settings.
-- ---------------------------------------------------------------------------

-- Record stats a splash can be linked to (key -> label for the dropdown).
HC.SPLASH_TRIGGERS = {
    { "highestCrit",   "Highest Crit" },
    { "biggestMelee",  "Biggest Melee Hit" },
    { "biggestRanged", "Biggest Ranged Hit" },
    { "biggestHit",    "Biggest Hit Taken" },
    { "closestCall",   "Closest Call (new low)" },
    { "nearestDeath",  "Nearest Death" },
    { "highestFall",   "Highest Fall" },
    { "toughestFoe",   "Toughest Foe" },
    { "mostFoes",      "Most Foes at Once" },
    { "clutchSaves",   "Clutch Save" },
}

-- Tilt direction per splash (SetRotation: positive = counter-clockwise = top
-- leans left). POW leans right, BOOM leans left, ZAP goes either way.
local COMIC_TILT = {
    pow  = { -18, -6 },
    boom = {   6, 18 },
    zap  = { -15, 15 },
}

local splashPlacement = false
local comicFrames = {}

local function StopSplashDrag(f)
    if not f.moving then return end
    f.moving = false
    f:StopMovingOrSizing()
    local cx, cy = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local conf = HC.db and HC.db.comic and HC.db.comic[f.which]
    if cx and ux and conf then
        conf.x = math.floor(cx - ux + 0.5)
        conf.y = math.floor(cy - uy + 0.5)
    end
end

local function GetComicFrame(which)
    local f = comicFrames[which]
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f.which = which
    f:SetSize(150, 150)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(false)
    f:Hide()
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexture("Interface\\AddOns\\HardcoreStatTracker\\Media\\" .. which)
    f.lastPop = -99

    f.ag = f:CreateAnimationGroup()
    local aIn = f.ag:CreateAnimation("Alpha")
    aIn:SetFromAlpha(0); aIn:SetToAlpha(1); aIn:SetDuration(0.08); aIn:SetOrder(1)
    local grow = f.ag:CreateAnimation("Scale")
    if grow.SetScaleFrom then
        grow:SetScaleFrom(0.4, 0.4); grow:SetScaleTo(1, 1)
    else
        grow:SetFromScale(0.4, 0.4); grow:SetToScale(1, 1)  -- older anim API
    end
    grow:SetOrigin("CENTER", 0, 0)
    grow:SetDuration(0.14); grow:SetOrder(1)
    local aOut = f.ag:CreateAnimation("Alpha")
    aOut:SetFromAlpha(1); aOut:SetToAlpha(0); aOut:SetDuration(0.45)
    aOut:SetStartDelay(0.9); aOut:SetOrder(2)
    f.ag:SetScript("OnFinished", function() if not splashPlacement then f:Hide() end end)

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

    comicFrames[which] = f
    return f
end

function HC:ComicPop(which)
    if not HC.db or HC.db.comicPops == false or splashPlacement then return end
    local conf = HC.db.comic and HC.db.comic[which]
    if not conf or conf.on == false then return end
    local f = GetComicFrame(which)
    local now = GetTime()
    if now - f.lastPop < 8 then return end  -- early levels set records constantly
    f.lastPop = now
    local t = COMIC_TILT[which] or COMIC_TILT.pow
    f.tex:SetRotation(math.rad(math.random(t[1], t[2])))
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER",
        conf.x + math.random(-30, 30), conf.y + math.random(-25, 25))
    f:Show()
    f.ag:Stop()
    f.ag:Play()
end

-- Remember when a record was set, so the full window can flag it as "new!".
function HC:StampRecord(statKey)
    if HC.db and HC.db.recordStamps then HC.db.recordStamps[statKey] = time() end
end

-- Called wherever a record stat improves; stamps it and pops linked splashes.
function HC:ComicEvent(statKey)
    if not HC.db then return end
    HC:StampRecord(statKey)
    if not HC.db.comic then return end
    for which, conf in pairs(HC.db.comic) do
        if conf.stat == statKey then HC:ComicPop(which) end
    end
end

-- Placement mode: show all splashes statically and let the user drag them.
function HC:ToggleSplashPlacement()
    if not HC.db or not HC.db.comic then return end
    splashPlacement = not splashPlacement
    for which, conf in pairs(HC.db.comic) do
        local f = GetComicFrame(which)
        f.ag:Stop()
        if splashPlacement then
            f:EnableMouse(true)
            f:SetAlpha(1)
            f.tex:SetRotation(0)
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", conf.x, conf.y)
            f:Show()
        else
            StopSplashDrag(f)
            f:EnableMouse(false)
            f:Hide()
        end
    end
    print("|cffff4444Hardcore Stat Tracker|r: " .. (splashPlacement
        and "drag the splashes where you want them, then toggle placement again to save."
        or "splash positions saved."))
end

-- Debug helper: zero just the three hit records (and splash cooldowns) so the
-- next hit sets a "new record" and pops the splash again.
function HC:ResetHitRecords()
    if not HC.db then return end
    HC.db.highestCrit, HC.db.highestCritSpell, HC.db.highestCritTarget = 0, nil, nil
    HC.db.biggestMelee, HC.db.biggestMeleeTarget = 0, nil
    HC.db.biggestRanged, HC.db.biggestRangedTarget = 0, nil
    for _, f in pairs(comicFrames) do f.lastPop = -99 end
    HC:UpdateDisplay()
    print("|cffff4444Hardcore Stat Tracker|r: hit records reset (crit / melee / ranged). Next hit pops the splash.")
end
