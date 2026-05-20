-- ========================================================================== --
--  Barrel Handler
--  Manages chip transactions between player deposit and casino reserves.
-- ========================================================================== --

local Barrel = {}

local pName, sName
local pBarrel, sBarrel
local COIN_ID = "createdeco:brass_coin"

-- -------------------------------------------------------------------------- --
-- Initialization
-- -------------------------------------------------------------------------- --

function Barrel.init(playerName, sharedName)
    pName, sName = playerName, sharedName
    pBarrel = peripheral.wrap(pName)
    sBarrel = peripheral.wrap(sName)
    
    assert(pBarrel, "Player barrel not found: " .. tostring(pName))
    assert(sBarrel, "Shared barrel not found: " .. tostring(sName))
end

-- -------------------------------------------------------------------------- --
-- Private Helpers
-- -------------------------------------------------------------------------- --

local function countCoins(inv)
    local total = 0
    if not inv then return 0 end
    for _, stack in pairs(inv.list()) do
        if stack.name == COIN_ID then
            total = total + stack.count
        end
    end
    return total
end

local function moveCoins(dst, srcName, amount)
    local src = peripheral.wrap(srcName)
    if not src or not dst then return 0 end
    
    local moved = 0
    for slot, stack in pairs(src.list()) do
        if moved >= amount then break end
        if stack.name == COIN_ID then
            local toMove = math.min(amount - moved, stack.count)
            local result = dst.pullItems(srcName, slot, toMove)
            moved = moved + result
        end
    end
    return moved
end

-- -------------------------------------------------------------------------- --
-- Public API
-- -------------------------------------------------------------------------- --

function Barrel.countPlayerChips()
    return countCoins(pBarrel)
end

function Barrel.takeBet(amount)
    -- Moves coins from player barrel to reserve
    return moveCoins(sBarrel, pName, amount)
end

function Barrel.returnToPlayer(amount)
    -- Moves coins from reserve to player barrel
    return moveCoins(pBarrel, sName, amount)
end

return Barrel