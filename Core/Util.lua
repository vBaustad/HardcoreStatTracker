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
HC.STDFONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
