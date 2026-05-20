-- barrel_handler.lua
-- Handles all chip movement between barrels on the wired network.
--
-- How to use:
--   local Barrel = dofile("../libraries/barrel_handler.lua")
--   Barrel.init("minecraft:barrel_2", "minecraft:barrel_5")
--   local chips = Barrel.countPlayerChips()
--   Barrel.takeBet(2)
--   Barrel.returnToPlayer(4)

local Barrel = {}

local playerBarrelName = nil
local sharedBarrelName = nil
local playerBarrel     = nil
local sharedBarrel     = nil

-- Call this once on startup with the two barrel peripheral names.
-- playerName is the deposit barrel the player puts chips into.
-- sharedName is the casino reserve barrel payouts come from.
function Barrel.init(playerName, sharedName)
    playerBarrelName = playerName
    sharedBarrelName = sharedName
    playerBarrel     = peripheral.wrap(playerName)
    sharedBarrel     = peripheral.wrap(sharedName)
    assert(playerBarrel, "Player barrel not found: " .. tostring(playerName))
    assert(sharedBarrel, "Shared barrel not found: " .. tostring(sharedName))
end

-- Counts how many brass coins are sitting in a given inventory peripheral.
local function countCoins(inv)
    local total = 0
    for _, stack in pairs(inv.list()) do
        if stack.name == "createdeco:brass_coin" then
            total = total + stack.count
        end
    end
    return total
end

-- Moves up to `amount` coins from srcName into dst inventory.
-- Returns how many were actually moved.
local function moveCoins(dst, srcName, amount)
    local src = peripheral.wrap(srcName)
    if not src then return 0 end
    local moved = 0
    for slot, stack in pairs(src.list()) do
        if moved >= amount then break end
        if stack.name == "createdeco:brass_coin" then
            local toMove = math.min(amount - moved, stack.count)
            moved = moved + dst.pullItems(srcName, slot, toMove)
        end
    end
    return moved
end

-- Returns the current chip count in the player deposit barrel.
function Barrel.countPlayerChips()
    return countCoins(playerBarrel)
end

-- Takes `amount` chips from the player barrel into the shared reserve.
-- Returns how many chips were actually moved.
function Barrel.takeBet(amount)
    return moveCoins(sharedBarrel, playerBarrelName, amount)
end

-- Returns `amount` chips from the shared reserve back to the player barrel.
-- Returns how many chips were actually moved.
function Barrel.returnToPlayer(amount)
    return moveCoins(playerBarrel, sharedBarrelName, amount)
end

return Barrel