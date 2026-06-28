local ADDON, HC = ...

-- ---------------------------------------------------------------------------
-- Game-flavour detection: which kind of Classic are we on? Lets the UI hide
-- settings/features that don't apply (e.g. permadeath bits off Hardcore realms).
-- ---------------------------------------------------------------------------

-- Season of Discovery: rune engraving is the giveaway (only SoD has it enabled).
function HC.IsSoD()
    return (C_Engraving and C_Engraving.IsEngravingEnabled and C_Engraving.IsEngravingEnabled()) and true or false
end

-- Official Hardcore mode (permadeath ruleset on this realm/character).
function HC.IsHardcore()
    if C_GameRules and C_GameRules.IsHardcoreActive then
        return C_GameRules.IsHardcoreActive() and true or false
    end
    return false
end

-- Short label for display ("Hardcore", "Season of Discovery", "Classic Era").
function HC.FlavorName()
    if HC.IsHardcore() then return "Hardcore" end
    if HC.IsSoD() then return "Season of Discovery" end
    return "Classic Era"
end

-- Whether to show the permadeath/Hardcore-only features (Famous Last Words, Memorial,
-- death-on-PLAYER_DEAD recording, the survival stats). We treat it as Hardcore on ANY HC
-- signal and as non-Hardcore only for Season of Discovery or a plain realm with no HC signal.
-- The addon checks are essential: most "Hardcore" play on Era is the community ruleset on a
-- NORMAL realm, where C_GameRules reports non-HC - relying on it alone would wrongly strip
-- those players' features.
local HC_ADDONS = { "Hardcore", "HardcoreUnlocked", "HardcoreAchievements" }
function HC.HardcoreFeatures()
    if HC.IsSoD() then return false end                                    -- SoD is never Hardcore
    if C_GameRules and C_GameRules.IsHardcoreActive and C_GameRules.IsHardcoreActive() then
        return true                                                        -- official Hardcore realm
    end
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if loaded then
        for _, a in ipairs(HC_ADDONS) do
            if loaded(a) then return true end                              -- community Hardcore addon
        end
    end
    return false                                                           -- plain Classic Era, no HC signal
end

-- Apply flavour-dependent UI gating once the flavour is known (called on PLAYER_LOGIN). The
-- Famous Last Words options page and the PLAYER_DEAD memorial are gated where they live; this
-- handles the load-time UI (the full window's Memorial button).
function HC:ApplyFlavor()
    local hc = HC.HardcoreFeatures()
    HC.hcFeatures = hc                       -- cached for the hot path (OnHealth) + stat gating
    if HC.memBtn then HC.memBtn:SetShown(hc) end
    if not hc then
        -- Off Hardcore, "Time Alive" is just /played - relabel so it doesn't imply permadeath.
        for _, s in ipairs(HC.STATS or {}) do
            if s[1] == "timeAlive" then s[2] = "Time Played" end
        end
        if HC.STAT_HELP then
            HC.STAT_HELP.timeAlive = "Your total /played time on this character. Server-authoritative, ticks live. The sub-line shows time at your current level."
        end
    end
end

-- Formatting helpers + shared font.

function HC.Comma(n)
    n = math.floor((n or 0) + 0.5)
    local s = tostring(n)
    local k
    repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end

function HC.FmtTime(s)
    s = math.floor(s or 0)
    if s >= 60 then return string.format("%dm %02ds", math.floor(s / 60), s % 60) end
    return s .. "s"
end

function HC.FmtDiff(d)
    return (d >= 0) and ("+" .. d) or tostring(d)
end

-- Compact number for tight spaces (the mini panel): 950 -> "950", 1000 -> "1k",
-- 1500 -> "1.5k", 12345 -> "12.3k", 123456 -> "123k", 1.5e6 -> "1.5M".
function HC.FmtNum(n)
    n = math.floor((n or 0) + 0.5)
    if n >= 1e6 then
        local s = ("%.1f"):format(n / 1e6):gsub("%.0$", "")
        return s .. "M"
    elseif n >= 1000 then
        local v = n / 1000
        if v >= 100 then return math.floor(v + 0.5) .. "k" end
        local s = ("%.1f"):format(v):gsub("%.0$", "")
        return s .. "k"
    end
    return tostring(n)
end

function HC.FmtShort(n)
    n = n or 0
    if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
    if n >= 1e4 then return string.format("%.1fk", n / 1e3) end
    return HC.Comma(n)
end

function HC.FmtSec(s)
    return string.format("%.1fs", s)
end

function HC.FmtPlayed(s)
    s = math.floor(s or 0)
    local d = math.floor(s / 86400); s = s % 86400
    local h = math.floor(s / 3600);  s = s % 3600
    local m = math.floor(s / 60)
    if d > 0 then return string.format("%dd %dh %dm", d, h, m) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end
-- Lightweight, dependency-free string hash (two independent rolling hashes
-- combined into one token). Used only for the saved-stats integrity check, so
-- it does not need to be cryptographic - it just has to make a hand-edit of the
-- SavedVariables file change the result. No bit ops: every step stays well under
-- 2^53 so the math is exact on WoW's Lua doubles.
function HC.Hash(s)
    s = tostring(s or "")
    local h1, h2 = 5381, 2166136261 % 2147483647
    for i = 1, #s do
        local c = s:byte(i)
        h1 = (h1 * 33 + c) % 4294967291      -- prime just under 2^32
        h2 = (h2 * 131 + c) % 2147483647     -- 2^31 - 1
    end
    return string.format("%x-%x", h1, h2)
end

HC.STDFONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

-- A button styled like the addon's dark/red panels (instead of the default gold
-- WoW button). Supports :SetText(t), :GetText(), :SetSelected(on) and a hover
-- highlight. Set its OnClick/OnEnter as usual.
function HC.MakeButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w or 100, h or 22)
    b:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", 0, 0)
    fs:SetText(text or "")
    b._fs = fs
    local function paint(self)
        if self._selected then
            self:SetBackdropColor(0.45, 0.12, 0.12, 0.95)
            self:SetBackdropBorderColor(1, 0.45, 0.45, 1)
            fs:SetTextColor(1, 0.95, 0.7)
        elseif self._hover then
            self:SetBackdropColor(0.22, 0.13, 0.13, 0.95)
            self:SetBackdropBorderColor(0.85, 0.25, 0.25, 1)
            fs:SetTextColor(1, 0.9, 0.6)
        else
            self:SetBackdropColor(0.12, 0.10, 0.10, 0.9)
            self:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)
            fs:SetTextColor(0.85, 0.82, 0.82)
        end
    end
    b:HookScript("OnEnter", function(self) self._hover = true; paint(self) end)
    b:HookScript("OnLeave", function(self) self._hover = false; paint(self) end)
    b:HookScript("OnMouseDown", function(self) fs:SetPoint("CENTER", 0, -1) end)
    b:HookScript("OnMouseUp", function(self) fs:SetPoint("CENTER", 0, 0) end)
    b.SetText = function(self, t) self._fs:SetText(t) end
    b.GetText = function(self) return self._fs:GetText() end
    b.SetSelected = function(self, on) self._selected = on; paint(self) end
    paint(b)
    return b
end
