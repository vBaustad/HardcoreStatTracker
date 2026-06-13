local ADDON, HC = ...

-- Built-in "famous last words" - cocky, ironic things a player casually types
-- to their party right before it all goes wrong. Kept hidden in-game for the
-- karmic surprise factor.
local DEFAULT_LASTWORDS = {
    "yeah this is easy",
    "pfft i got this",
    "watch this",
    "they barely even hit me",
    "i don't need to heal yet",
    "totally safe zone, relax",
    "let me just pull a few more",
    "no need to rest, keep going",
    "trust me i do this all the time",
    "who needs a healer anyway",
    "what's the worst that could happen",
    "one more pull then i'll be careful",
    "imagine dying to this lol",
    "these mobs are basically gray to me",
    "i never even use my potions",
    "hardcore is easy if you're not bad",
    "i'll tank it, go go go",
    "almost dinged, one more",
    "should probably go to bed after this",
    "ok last pull then i'm logging",
    "it's not even that late",
}
-- ---------------------------------------------------------------------------
-- Danger alert: screen-flash vignette + sound + center warning text
-- ---------------------------------------------------------------------------
local flash = CreateFrame("Frame", nil, UIParent)
flash:SetAllPoints(UIParent)
flash:SetFrameStrata("FULLSCREEN_DIALOG")
flash:EnableMouse(false)
flash:SetToplevel(false)
flash:Hide()
local flashTex = flash:CreateTexture(nil, "BACKGROUND")
flashTex:SetAllPoints()
flashTex:SetTexture("Interface\\FullScreenTextures\\LowHealth")  -- red edge vignette, clear center
local flashAG = flash:CreateAnimationGroup()
local fa1 = flashAG:CreateAnimation("Alpha")
fa1:SetFromAlpha(0); fa1:SetToAlpha(0.35); fa1:SetDuration(0.2); fa1:SetOrder(1)
local fa2 = flashAG:CreateAnimation("Alpha")
fa2:SetFromAlpha(0.35); fa2:SetToAlpha(0); fa2:SetDuration(0.9); fa2:SetOrder(2)
flashAG:SetScript("OnFinished", function() flash:Hide() end)
function HC:RandomLastWord()
    local lw = HC.db.lastWords
    local customs = {}
    for _, m in ipairs(lw.custom or {}) do
        if m and m ~= "" then customs[#customs + 1] = m end
    end
    local defaults = lw.useDefaults and DEFAULT_LASTWORDS or {}
    local haveC, haveD = #customs > 0, #defaults > 0

    if haveC and haveD then
        -- 50/50 so your own lines show as often as the whole built-in set
        if math.random(2) == 1 then return customs[math.random(#customs)] end
        return defaults[math.random(#defaults)]
    elseif haveC then
        return customs[math.random(#customs)]
    elseif haveD then
        return defaults[math.random(#defaults)]
    end
    return nil
end

function HC:DangerAlert()
    -- Custom low-health warning clip; falls back to the raid-warning sound.
    if not PlaySoundFile("Interface\\AddOns\\HardcoreStatTracker\\Sounds\\Frank.ogg", "Master") then
        PlaySound(8959, "Master")
    end
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        RaidNotice_AddMessage(RaidWarningFrame, "|cffff2020LOW HEALTH!|r", ChatTypeInfo["RAID_WARNING"])
    end
    flash:SetAlpha(0); flash:Show()
    flashAG:Stop(); flashAG:Play()
end

-- /say and /yell require a *hardware event*, so an auto-trigger can't send them
-- directly. We queue the line and flush it on the player's next keypress (which
-- is a hardware event). Group channels have no such restriction.
local pendingChat = {}  -- FIFO: several messages can queue before a keypress
local CHAT_TTL = 6      -- seconds before a queued line goes stale and is dropped
local catcher = CreateFrame("Frame", nil, UIParent)
catcher:Hide()
catcher:SetPropagateKeyboardInput(true)  -- let keys still reach the game
local function FlushPending()
    local now = GetTime()
    for i = 1, #pendingChat do
        local m = pendingChat[i]
        if now - m.t <= CHAT_TTL then
            SendChatMessage(m.msg, m.chan)   -- we're inside a hardware event here
        end
        pendingChat[i] = nil
    end
    catcher:EnableKeyboard(false)
    catcher:Hide()
end
catcher:SetScript("OnKeyDown", FlushPending)

function HC.SayMessage(msg, channel, fromHardware)
    local public = (channel == "SAY" or channel == "YELL" or channel == "EMOTE")
    if fromHardware or not public then
        SendChatMessage(msg, channel)        -- already in a hardware event, or group channel
    else
        pendingChat[#pendingChat + 1] = { msg = msg, chan = channel, t = GetTime() }
        catcher:EnableKeyboard(true)
        catcher:Show()
        C_Timer.After(CHAT_TTL + 1, function()   -- janitor: drop stale, release keyboard
            local now = GetTime()
            for i = #pendingChat, 1, -1 do
                if now - pendingChat[i].t > CHAT_TTL then table.remove(pendingChat, i) end
            end
            if #pendingChat == 0 then
                catcher:EnableKeyboard(false)
                catcher:Hide()
            end
        end)
    end
end

function HC:TriggerDanger(fromHardware)
    local lw = HC.db.lastWords
    if lw.say then
        local msg = HC:RandomLastWord()
        if msg then HC.SayMessage(msg, lw.channel or "SAY", fromHardware) end
    end
    if lw.alertSelf then HC:DangerAlert() end
end

-- Settings "Test" button runs inside a click (a hardware event), so it can send
-- /say directly - a true preview of the real thing.
function HC:TestDanger()
    HC:TriggerDanger(true)
    if not (HC.db.lastWords and HC.db.lastWords.say) then
        print("|cffff4444Hardcore Stat Tracker|r: \"Announce a message in chat\" is off, so nothing was sent.")
    end
end
