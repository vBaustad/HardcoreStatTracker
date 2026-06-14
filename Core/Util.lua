local ADDON, HC = ...

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
