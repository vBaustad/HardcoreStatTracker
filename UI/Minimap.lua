local ADDON, HC = ...

-- A lightweight, self-contained minimap button (no external libs). Left-click
-- opens the full window, right-click opens settings, drag moves it around the
-- minimap ring (position saved as an angle).

local RADIUS = 80
local btn

local function UpdatePosition()
    if not btn then return end
    local angle = math.rad((HC.db and HC.db.minimapAngle) or 200)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", RADIUS * math.cos(angle), RADIUS * math.sin(angle))
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    if not (mx and cx and scale and scale > 0) then return end
    local angle = math.atan2(cy / scale - my, cx / scale - mx)
    if HC.db then HC.db.minimapAngle = math.deg(angle) end
    UpdatePosition()
end

function HC:CreateMinimapButton()
    if btn then return end
    btn = CreateFrame("Button", "HardcoreStatTrackerMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetMovable(true)

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("TOPLEFT", 7, -6)

    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if HC.OpenOptions then HC:OpenOptions() end
        else
            if HC.ToggleFull then HC:ToggleFull() end
        end
    end)
    btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffff4444Hardcore Stat Tracker|r")
        GameTooltip:AddLine("Left-click: full stats", 1, 1, 1)
        GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
        GameTooltip:AddLine("Drag: move around the minimap", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
end

-- Create/show or hide per the setting. Called on login and from the toggle.
function HC:ApplyMinimapButton()
    if HC.db and HC.db.minimapButton then
        if not btn then HC:CreateMinimapButton() end
        UpdatePosition()
        if btn then btn:Show() end
    elseif btn then
        btn:Hide()
    end
end
