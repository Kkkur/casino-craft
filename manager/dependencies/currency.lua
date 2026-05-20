-- currency.lua
-- Numismatics mod currency system
-- 1 sun = 8 crowns = 64 cogs = 512 sprockets = 4096 bevels = 32768 spurs

local Currency = {}

-- Denomination values in spurs (base unit)
Currency.DENOM = {
    { name = "sun",      plural = "suns",      value = 32768 },
    { name = "crown",    plural = "crowns",    value = 4096  },
    { name = "cog",      plural = "cogs",      value = 512   },
    { name = "sprocket", plural = "sprockets", value = 64    },
    { name = "bevel",    plural = "bevels",    value = 8     },
    { name = "spur",     plural = "spurs",     value = 1     },
}

-- Short display names for the monitor
Currency.SHORT = {
    sun      = "sun",
    crown    = "cro",
    cog      = "cog",
    sprocket = "spr",
    bevel    = "bev",
    spur     = "sp",
}

-- Convert a raw spur amount into a denomination table
function Currency.toCoins(spurs)
    local result = {}
    local remaining = math.floor(spurs)
    for _, denom in ipairs(Currency.DENOM) do
        local count = math.floor(remaining / denom.value)
        remaining = remaining % denom.value
        if count > 0 then
            table.insert(result, { name = denom.name, short = Currency.SHORT[denom.name], count = count })
        end
    end
    if #result == 0 then
        table.insert(result, { name = "spur", short = "sp", count = 0 })
    end
    return result
end

-- Convert a denomination table back to raw spurs
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

-- Format a spur amount as a short readable string
function Currency.format(spurs, maxDenoms)
    maxDenoms = maxDenoms or 3
    local coins = Currency.toCoins(spurs)
    local parts = {}
    for i = 1, math.min(#coins, maxDenoms) do
        table.insert(parts, coins[i].count .. coins[i].short)
    end
    if #parts == 0 then return "0sp" end
    return table.concat(parts, " ")
end

-- Format a spur amount as a long readable string
function Currency.formatLong(spurs)
    local coins = Currency.toCoins(spurs)
    local parts = {}
    for _, coin in ipairs(coins) do
        local label = coin.count == 1 and coin.name or coin.name .. "s"
        table.insert(parts, coin.count .. " " .. label)
    end
    if #parts == 0 then return "0 spurs" end
    return table.concat(parts, ", ")
end

function Currency.parse(str)
    local total = 0
    local shortMap = {}
    for _, denom in ipairs(Currency.DENOM) do
        shortMap[denom.name] = denom.value
        shortMap[Currency.SHORT[denom.name]] = denom.value
    end
    for num, unit in str:gmatch("(%d+)%s*(%a+)") do
        local val = shortMap[unit:lower()]
        if val then
            total = total + (tonumber(num) * val)
        end
    end
    return total
end

return Currency
