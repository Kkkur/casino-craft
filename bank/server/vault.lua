-- bank/server/vault.lua

local vault = {}

local _vault     = nil
local _vaultName = nil
local _log       = nil

function vault.init(peripheralName, logger)
    _vaultName = peripheralName
    _log       = logger
    _vault     = peripheral.wrap(peripheralName)
    if not _vault then
        if _log then _log.error("Could not wrap vault peripheral: '" .. tostring(peripheralName) .. "'") end
        error("vault: could not wrap peripheral '" .. tostring(peripheralName) .. "'")
    end
    if _log then _log.info("Vault wrapped: " .. peripheralName) end
end

local function assertInit()
    if not _vault then error("vault: not initialised, call vault.init() first") end
end

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

function vault.freeSpace()
    assertInit()
    local used = 0
    local items = _vault.list()
    for _, item in pairs(items) do used = used + item.count end
    return (_vault.size() * 64) - used
end

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
    if _log then _log.debug("Vault pushTo " .. targetName .. " count=" .. count .. " moved=" .. moved) end
    return moved
end

function vault.pullFrom(sourceName, count, coinItem)
    assertInit()
    coinItem = coinItem or "createdeco:brass_coin"
    local moved  = 0
    local source = peripheral.wrap(sourceName)
    if not source then
        if _log then _log.error("pullFrom: cannot wrap source '" .. tostring(sourceName) .. "'") end
        return 0
    end
    local items = source.list()
    for slot, item in pairs(items) do
        if item.name == coinItem and moved < count then
            local toMove = math.min(item.count, count - moved)
            moved = moved + source.pushItems(_vaultName, slot, toMove)
        end
        if moved >= count then break end
    end
    if _log then _log.debug("Vault pullFrom " .. sourceName .. " count=" .. count .. " moved=" .. moved) end
    return moved
end

function vault.reconcile(profilesSum, coinItem)
    assertInit()
    local actual   = vault.coinCount(coinItem)
    local expected = profilesSum
    local ok       = (actual == expected)
    if _log and not ok then
        _log.warn("Reconcile FAIL: expected=" .. expected .. " actual=" .. actual .. " delta=" .. (actual - expected))
    end
    return ok, expected, actual
end

return vault