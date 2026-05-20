-- ========================================================================== --
--  Player Detector
--  Manages player proximity tracking for machine interaction.
-- ========================================================================== --

local PlayerDetector = {}

local detector      = nil
local currentPlayer = nil
local lastActivity  = 0
local IDLE_TIMEOUT  = 120

-- -------------------------------------------------------------------------- --
-- Initialization
-- -------------------------------------------------------------------------- --

function PlayerDetector.init(detectorName)
    if not detectorName or detectorName == "none" then
        return false
    end

    detector = peripheral.wrap(detectorName) or peripheral.find("playerDetector")
    if not detector then
        print("[PlayerDetector] Warning: Peripheral not found.")
        return false
    end

    print("[PlayerDetector] Ready. Binding: " .. peripheral.getName(detector))
    return true
end

-- -------------------------------------------------------------------------- --
-- Accessors
-- -------------------------------------------------------------------------- --

function PlayerDetector.getCurrentPlayer() return currentPlayer end
function PlayerDetector.clearPlayer()     currentPlayer = nil end
function PlayerDetector.isAvailable()     return detector ~= nil end

-- -------------------------------------------------------------------------- --
-- Tracking Logic
-- -------------------------------------------------------------------------- --

function PlayerDetector.isNearby(username, range)
    if not detector or not username then return false end
    local ok, result = pcall(detector.isPlayerInRange, range or 5, username)
    return ok and result == true
end

function PlayerDetector.getPlayersNearby(range)
    if not detector then return {} end
    local ok, players = pcall(detector.getPlayersInRange, range or 5)
    return (ok and players) or {}
end

function PlayerDetector.getClosestPlayer(range)
    if not detector then return nil end
    local ok, players = pcall(detector.getPlayersInRange, range or 5)
    return (ok and players and players[1]) or nil
end

-- -------------------------------------------------------------------------- --
-- Listener Loop
-- -------------------------------------------------------------------------- --

function PlayerDetector.listenerThread(shared, onPlayerChange)
    while not (shared and shared.shutdown) do
        local evData = {os.pullEvent()}
        local event  = evData[1]
        local username = evData[2]

        if event == "playerClick" and type(username) == "string" then
            local old = currentPlayer
            currentPlayer = username
            lastActivity  = os.clock()

            if username ~= old then
                if onPlayerChange then pcall(onPlayerChange, username, old) end
            end

        elseif event == "timer" or event == "monitor_touch" then
            if currentPlayer and not (shared and shared.gameActive) then
                if (os.clock() - lastActivity) > IDLE_TIMEOUT then
                    local old = currentPlayer
                    currentPlayer = nil
                    if onPlayerChange then pcall(onPlayerChange, nil, old) end
                end
            end
        end
    end
end

return PlayerDetector