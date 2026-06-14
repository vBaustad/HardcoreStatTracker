local ADDON, HC = ...

local Comma, FmtTime, FmtDiff, FmtShort, FmtSec, FmtPlayed = HC.Comma, HC.FmtTime, HC.FmtDiff, HC.FmtShort, HC.FmtSec, HC.FmtPlayed
-- Suppress the "Total time played" chat spam, but only for requests we make.
local awaitingPlayedMsg = false
if ChatFrame_DisplayTimePlayed then
    local orig = ChatFrame_DisplayTimePlayed
    ChatFrame_DisplayTimePlayed = function(...)
        if awaitingPlayedMsg then awaitingPlayedMsg = false; return end
        return orig(...)
    end
end
-- ---------------------------------------------------------------------------
-- Reset confirmation
-- ---------------------------------------------------------------------------
StaticPopupDialogs["HST_RESET"] = {
    text = "Reset all Hardcore Stat Tracker records for this character?",
    button1 = YES, button2 = NO,
    OnAccept = function()
        local keep = {
            shown = HC.db.shown, locked = HC.db.locked, point = HC.db.point, show = HC.db.show,
            fullPoint = HC.db.fullPoint, fontSize = HC.db.fontSize, scale = HC.db.scale,
            lastWords = HC.db.lastWords, showVersion = HC.db.showVersion, mobTooltip = HC.db.mobTooltip,
            announce = HC.db.announce, welcomed = HC.db.welcomed, comicPops = HC.db.comicPops,
            comic = HC.db.comic, fullAlpha = HC.db.fullAlpha, miniAlpha = HC.db.miniAlpha,
            combatTimer = HC.db.combatTimer,
            playedTotal = HC.db.playedTotal, playedLevel = HC.db.playedLevel,
            -- The audit trail must survive a reset, or resetting would hide a
            -- faker's tracks. Bump the reset count here.
            resets = (HC.db.resets or 0) + 1,
            tamperCount = HC.db.tamperCount, tamperedEver = HC.db.tamperedEver,
        }
        wipe(HC.db)
        for k, v in pairs(keep) do HC.db[k] = v end
        HC.ApplyDefaults()
        if HC.StoreIntegrity then HC.StoreIntegrity() end  -- re-stamp the now-cleared records
        HC:UpdateDisplay()
        if HC.RefreshFull then HC:RefreshFull() end
        print("|cffff4444Hardcore Stat Tracker|r: records reset (" .. (HC.db.resets or 0) .. " total).")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
-- ---------------------------------------------------------------------------
-- Slash command
-- ---------------------------------------------------------------------------
SLASH_HST1 = "/hst"
SLASH_HST2 = "/hcstats"   -- legacy alias
SLASH_HST3 = "/hc"        -- legacy alias
SlashCmdList.HST = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "lock" then
        HC.db.locked = not HC.db.locked
        print("|cffff4444Hardcore Stat Tracker|r: frame " .. (HC.db.locked and "locked." or "unlocked."))
    elseif msg == "config" or msg == "options" or msg == "settings" then
        if HC.OpenOptions then HC:OpenOptions() end
    elseif msg == "full" or msg == "all" then
        HC:ToggleFull()
    elseif msg == "splashes" or msg == "splash" then
        HC:ToggleSplashPlacement()
    elseif msg == "welcome" then
        HC:ShowWelcome()
    elseif msg == "welcome reset" then
        HC.db.welcomed = nil
        HC:ShowWelcome()
        print("|cffff4444Hardcore Stat Tracker|r: welcome flag cleared - it will also auto-show on next login.")
    elseif msg == "reset" then
        StaticPopup_Show("HST_RESET")
    elseif msg == "resethits" or msg == "debughits" then
        if HC.ResetHitRecords then HC:ResetHitRecords() end
    elseif msg == "memorial" or msg == "death" then
        if HC.ShowMemorial then HC:ShowMemorial() end
    elseif msg:match("^makgora") or msg:match("^mak'gora") then
        local arg = msg:match("(%a+)%s*$")
        if arg == "won" then
            HC.adb.makgoraWon = HC.adb.makgoraWon + 1
            print("|cffff4444Hardcore Stat Tracker|r: Mak'gora win recorded (" .. HC.adb.makgoraWon .. " total).")
            HC:UpdateDisplay()
        elseif arg == "lost" then
            HC.adb.makgoraLost = HC.adb.makgoraLost + 1
            print("|cffff4444Hardcore Stat Tracker|r: Mak'gora loss recorded (" .. HC.adb.makgoraLost .. " total).")
            HC:UpdateDisplay()
        elseif arg == "debug" then
            HC.adb.makgoraDebug = not HC.adb.makgoraDebug
            print("|cffff4444Hardcore Stat Tracker|r: Mak'gora message capture "
                .. (HC.adb.makgoraDebug and "ON (watch chat during a duel, then tell the author the line)." or "OFF."))
        elseif arg == "reset" then
            HC.adb.makgoraWon, HC.adb.makgoraLost = 0, 0
            print("|cffff4444Hardcore Stat Tracker|r: Mak'gora tallies reset.")
            HC:UpdateDisplay()
        else
            print(("|cffff4444Hardcore Stat Tracker|r Mak'gora - won: %d, lost: %d.  /hst makgora won|lost|debug|reset")
                :format(HC.adb.makgoraWon, HC.adb.makgoraLost))
        end
    elseif msg == "show" then
        HC.db.shown = true; HC:UpdateDisplay()
    elseif msg == "hide" then
        HC.db.shown = false; HC:UpdateDisplay()
    else
        HC.db.shown = not HC.db.shown
        HC:UpdateDisplay()
        print("|cffff4444Hardcore Stat Tracker|r: " .. (HC.db.shown and "shown." or "hidden.")
            .. "  (/hst lock | reset)")
    end
end
-- ---------------------------------------------------------------------------
-- Mob tooltip: "this thing has hurt you before"
-- ---------------------------------------------------------------------------
local function AddMobInfo(tooltip)
    if not HC.db or not HC.db.mobTooltip or not HC.adb then return end
    local _, unit = tooltip:GetUnit()
    if not unit or UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then return end
    local rec = HC.adb.mobDamage[UnitName(unit)]
    if not rec or rec.hit <= 0 then return end
    -- Opportunistically note the mob's level while we're looking right at it.
    local l = UnitLevel(unit)
    if l and l > 0 then rec.lvl = l end
    local ctx = rec.atLevel and ("  |cff888888(at lvl " .. rec.atLevel .. ")|r") or ""
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("|cffff5555Has hit you for up to|r", "|cffffd100" .. Comma(rec.hit) .. "|r" .. ctx)
    if rec.crit > 0 then
        tooltip:AddDoubleLine("|cffff5555Worst crit|r", "|cffffd100" .. Comma(rec.crit) .. "|r")
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tip)
        if tip == GameTooltip then AddMobInfo(tip) end
    end)
else
    GameTooltip:HookScript("OnTooltipSetUnit", AddMobInfo)
end
-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
function HC.RequestPlayed()
    awaitingPlayedMsg = true
    RequestTimePlayed()
end

HC.frame:RegisterEvent("PLAYER_LOGIN")
HC.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
HC.frame:RegisterEvent("PLAYER_LEVEL_UP")
HC.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
HC.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
HC.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
HC.frame:RegisterEvent("TIME_PLAYED_MSG")
HC.frame:RegisterEvent("UNIT_PET")
HC.frame:RegisterEvent("GROUP_ROSTER_UPDATE")
HC.frame:RegisterEvent("QUEST_TURNED_IN")
HC.frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
HC.frame:RegisterEvent("CHAT_MSG_SYSTEM")
HC.frame:RegisterEvent("PLAYER_MONEY")
HC.frame:RegisterEvent("CHAT_MSG_MONEY")
HC.frame:RegisterEvent("CHAT_MSG_LOOT")
HC.frame:RegisterEvent("PLAYER_DEAD")
HC.frame:RegisterEvent("PLAYER_LOGOUT")  -- last chance to write a fresh integrity stamp
-- player drives the low-health features; party1-4 power the "players saved" stat.
HC.frame:RegisterUnitEvent("UNIT_HEALTH", "player", "party1", "party2", "party3", "party4")

HC.frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    -- Some events (UNIT_HEALTH especially) can fire during the loading screen,
    -- before PLAYER_LOGIN has initialized the saved variables.
    if not HC.db and event ~= "PLAYER_LOGIN" then return end
    if event == "PLAYER_LOGIN" then
        HC.ApplyDefaults()
        if HC.CheckIntegrity and HC.CheckIntegrity() then
            print("|cffff4444Hardcore Stat Tracker|r: |cffff3333saved stats were changed outside the game|r - the integrity check failed.")
        end
        HC.OnMoney()   -- baseline current money so session income is counted
        HC.state.playerGUID = UnitGUID("player")
        HC.RestorePosition()
        HC:ApplyMiniAlpha()
        if HC.ApplyMinimapButton then HC:ApplyMinimapButton() end
        if HC.BuildOptions then HC:BuildOptions() end
        HC.UpdatePet()
        HC:UpdateDisplay()
        HC.RequestPlayed()
        print("|cffff4444Hardcore Stat Tracker|r loaded. /hst to toggle, config, or hover for details.")
        if not HC.db.welcomed then
            HC.db.welcomed = true
            -- a few seconds late so the world has settled in first
            C_Timer.After(4, function() HC:ShowWelcome() end)
        end
    elseif event == "TIME_PLAYED_MSG" then
        -- arg1 = total played seconds, arg2 = played at current level
        HC.state.playedBase      = arg1
        HC.state.playedLevelBase = arg2
        HC.state.playedBaseTime  = GetTime()
        HC.db.playedTotal  = arg1
        HC.db.playedLevel  = arg2
        HC:UpdateDisplay()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HC.OnCombatLog()
    elseif event == "UNIT_HEALTH" then
        if arg1 == "player" then HC.OnHealth() else HC.OnPartyHealth(arg1) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        HC.OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        HC.OnCombatEnd()
    elseif event == "PLAYER_LEVEL_UP" then
        HC.RequestPlayed() -- refresh the per-level timer base
        HC:UpdateDisplay()
    elseif event == "UNIT_PET" then
        if arg1 == "player" then HC.UpdatePet() end
    elseif event == "GROUP_ROSTER_UPDATE" then
        HC.RefreshGroup()
    elseif event == "QUEST_TURNED_IN" then
        HC.db.quests = (HC.db.quests or 0) + 1
        HC:UpdateDisplay()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        HC.VisitZone()
    elseif event == "CHAT_MSG_SYSTEM" then
        HC.OnSystemMsg(arg1)
    elseif event == "PLAYER_MONEY" then
        HC.OnMoney()
    elseif event == "CHAT_MSG_MONEY" then
        HC.OnLootMoney(arg1)
    elseif event == "CHAT_MSG_LOOT" then
        HC.OnLoot(arg1)
    elseif event == "PLAYER_DEAD" then
        if HC.ClearAnnounce then HC:ClearAnnounce() end   -- never brag from the grave
        if not HC.db.died then                            -- a hardcore death: count it once, show the memorial
            HC.db.died = true
            if HC.adb then HC.adb.deaths = (HC.adb.deaths or 0) + 1 end
            if HC.ShowMemorial then C_Timer.After(2, function() HC:ShowMemorial() end) end
        end
    elseif event == "PLAYER_LOGOUT" then
        if HC.StoreIntegrity then HC.StoreIntegrity() end  -- sign the data being written to disk
    elseif event == "PLAYER_ENTERING_WORLD" then
        HC.UpdatePet()
        HC.RefreshGroup()
        HC.VisitZone()
        HC:UpdateDisplay()
    end
end)
