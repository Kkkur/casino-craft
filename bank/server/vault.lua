-- bank/server/vault.lua

local vault = {}

local _vault    = nil
local _vaultName = nil

-- call once at startup with the peripheral name from config
function vault.init(peripheralName)
    _vaultName = peripheralName
    _vault     = peripheral.wrap(peripheralName)
    if not _vault then
        error("vault: could not wrap peripheral '" .. tostring(peripheralName) .. "'")
    end
end

local function assertInit()
    if not _vault then error("vault: not initialised, call vault.init() first") end
end

-- returns total coin count in the vault
function vault.coinCount(coinItem)
    assertInit()
    coinItem = coinItem or "createdeco:brass_coin"
    local total = 0
    local items = _vault.list()
    for _, item in pairs(items) do
        if item.name == coinItem then
            total = total + item.count
        end
    end
    return total
end

-- returns available empty space in coins
function vault.freeSpace()
    assertInit()
    local used = 0
    local items = _vault.list()
    for _, item in pairs(items) do
        used = used + item.count
    end
    local size = _vault.size()
    return (size * 64) - used
end

-- push `count` coins from vault to a target peripheral (e.g. ATM input barrel)
-- returns number actually moved
function vault.pushTo(targetName, count, coinItem)
    assertInit()
    coinItem = coinItem or "createdeco:brass_coin"
    local moved = 0
    local items = _vault.list()
    for slot, item in pairs(items) do
        if item.name == coinItem and moved < count then
            local toMove = math.min(item.count, count - moved)
            moved = moved + _vault.pushItems(targetName, slot, toMove)
        end
        if moved >= count then break end
    end
    return moved
end

-- pull `count` coins from a source peripheral into vault
-- returns number actually moved
function vault.pullFrom(sourceName, count, coinItem)
    assertInit()
    coinItem = coinItem or "createdeco:brass_coin"
    local moved   = 0
    local source  = peripheral.wrap(sourceName)
    if not source then return 0 end
    local items = source.list()
    for slot, item in pairs(items) do
        if item.name == coinItem and moved < count then
            local toMove = math.min(item.count, count - moved)
            moved = moved + source.pushItems(_vaultName, slot, toMove)
        end
        if moved >= count then break end
    end
    return moved
end

-- reconcile: compare sum of all balances vs physical coin count
-- returns ok (bool), expected, actual
function vault.reconcile(profilesSum, coinItem)
    assertInit()
    local actual   = vault.coinCount(coinItem)
    local expected = profilesSum
    local ok       = (actual == expected)
    return ok, expected, actual
end

return vault