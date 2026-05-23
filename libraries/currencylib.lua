-- libraries/currencylib.lua
--
-- Canonical currency definitions for casino-craft.
-- All other modules load currency from here; do not hardcode denominations
-- or chip values elsewhere.
--
-- Unit hierarchy (Numismatics mod):
--   1 sun = 8 crowns = 64 cogs = 512 sprockets = 4096 bevels = 32768 spurs
--
-- Chip mapping:
--   1 chip (brass_coin) = CHIP_VALUE_SPURS spurs   (default: 8, i.e. 1 bevel)
--   Loaded at runtime from chip_value.txt if present.

local Currency = {}

-- chip value 

Currency.CHIP_VALUE_SPURS = 8   -- 1 chip = 8 spurs (1 bevel) by default

local function loadChipValue()
    if fs.exists("chip_value.txt") then
        local f = fs.open("chip_value.txt", "r")
        if f then
            local n = tonumber(f.readLine())
            f.close()
            if n and n > 0 then
                Currency.CHIP_VALUE_SPURS = n
            end
        end
    end
end
loadChipValue()

-- Convert a chip count to raw spurs
function Currency.chipsToSpurs(chips)
    return math.floor(chips) * Currency.CHIP_VALUE_SPURS
end

-- Convert raw spurs to chips (fractional chips rounded down)
function Currency.spursToChips(spurs)
    return math.floor(spurs / Currency.CHIP_VALUE_SPURS)
end

-- denomination table 

Currency.DENOM = {
    { name = "sun",      plural = "suns",      value = 32768 },
    { name = "crown",    plural = "crowns",    value = 4096  },
    { name = "cog",      plural = "cogs",      value = 512   },
    { name = "sprocket", plural = "sprockets", value = 64    },
    { name = "bevel",    plural = "bevels",    value = 8     },
    { name = "spur",     plural = "spurs",     value = 1     },
}

Currency.SHORT = {
    sun      = "sun",
    crown    = "cro",
    cog      = "cog",
    sprocket = "spr",
    bevel    = "bev",
    spur     = "sp",
}

-- conversion helpers 

-- Break a raw spur amount into denomination counts (largest first, zeros omitted)
function Currency.toCoins(spurs)
    local result    = {}
    local remaining = math.floor(spurs)
    for _, denom in ipairs(Currency.DENOM) do
        local count = math.floor(remaining / denom.value)
        remaining   = remaining % denom.value
        if count > 0 then
            table.insert(result, {
                name  = denom.name,
                short = Currency.SHORT[denom.name],
                count = count,
            })
        end
    end
    if #result == 0 then
        table.insert(result, { name = "spur", short = "sp", count = 0 })
    end
    return result
end

-- Reconstruct a spur total from a denomination list
function Currency.toSpurs(coins)
    local total = 0
    for _, coin in ipairs(coins) do
        for _, denom in ipairs(Currency.DENOM) do
            if denom.name == coin.name then
                total = total + (coin.count * denom.value)
                break
            end
        end
    end
    return total
end

-- formatting 

-- Short compact string, e.g. "2bev 3sp"  (up to maxDenoms parts)
function Currency.format(spurs, maxDenoms)
    maxDenoms   = maxDenoms or 3
    local coins = Currency.toCoins(spurs)
    local parts = {}
    for i = 1, math.min(#coins, maxDenoms) do
        table.insert(parts, coins[i].count .. coins[i].short)
    end
    if #parts == 0 then return "0sp" end
    return table.concat(parts, " ")
end

-- Long human string, e.g. "2 bevels, 3 spurs"
function Currency.formatLong(spurs)
    local coins = Currency.toCoins(spurs)
    local parts = {}
    for _, coin in ipairs(coins) do
        local label = coin.count == 1 and coin.name or (coin.name .. "s")
        table.insert(parts, coin.count .. " " .. label)
    end
    if #parts == 0 then return "0 spurs" end
    return table.concat(parts, ", ")
end

-- Format a chip count as   "42 chips (2bev 2sp)"
function Currency.formatChips(chips, maxDenoms)
    local spurs = Currency.chipsToSpurs(chips)
    return tostring(chips) .. " chips (" .. Currency.format(spurs, maxDenoms) .. ")"
end

-- parsing 

-- Parse a string like "1bev 3sp" or "2 bevels 1 spur" into raw spurs
function Currency.parse(str)
    local total    = 0
    local shortMap = {}
    for _, denom in ipairs(Currency.DENOM) do
        shortMap[denom.name]                    = denom.value
        shortMap[denom.plural]                  = denom.value
        shortMap[Currency.SHORT[denom.name]]    = denom.value
    end
    for num, unit in str:gmatch("(%d+)%s*(%a+)") do
        local val = shortMap[unit:lower()]
        if val then total = total + (tonumber(num) * val) end
    end
    return total
end

return Currency