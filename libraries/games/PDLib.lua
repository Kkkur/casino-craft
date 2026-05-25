-- libraries/games/PDLib.lua
-- Full wrapper for the Player Detector peripheral (both naming versions).
-- Covers every API function from the wiki plus click-to-activate session
-- management with idle timeout and player override.
--
-- Usage pattern:
--   local PD = dofile("/libraries/games/PDLib.lua")
--   PD.init("playerDetector_0")   -- or pass nil to auto-find
--   PD.startListening(shared, callbacks)  -- run in parallel thread

local PDLib = {}

-- -------------------------------------------------------------------------- --
-- Internal state
-- -------------------------------------------------------------------------- --

local _det          = nil   -- wrapped peripheral
local _detName      = nil   -- peripheral name string

-- Session state (written by listenerThread, read by game loop)
local _session = {
    player      = nil,      -- current player username, nil when idle
    idleTimer   = nil,      -- timer id for idle timeout
    gameActive  = false,    -- true while a hand is in progress
}

local IDLE_TIMEOUT = 3      -- seconds before an unclaimed click resets

-- -------------------------------------------------------------------------- --
-- Initialization
-- -------------------------------------------------------------------------- --

-- Try both peripheral names used across mod versions.
local PERI_NAMES = { "playerDetector", "player_detector" }

-- init(detectorName)
-- detectorName: peripheral name string, or nil to auto-find.
-- Returns true on success, false if no peripheral found.
function PDLib.init(detectorName)
    _det     = nil
    _detName = nil

    if detectorName and detectorName ~= "none" then
        _det = peripheral.wrap(detectorName)
        if _det then
            _detName = detectorName
        end
    end

    if not _det then
        for _, name in ipairs(PERI_NAMES) do
            local p = peripheral.find(name)
            if p then
                _det     = p
                _detName = peripheral.getName(p)
                break
            end
        end
    end

    if not _det then
        print("[PDLib] WARNING: no player detector peripheral found.")
        return false
    end

    print("[PDLib] Ready on peripheral: " .. _detName)
    return true
end

function PDLib.isAvailable() return _det ~= nil end
function PDLib.getName()     return _detName end

-- -------------------------------------------------------------------------- --
-- Raw peripheral API wrappers
-- All calls are pcall-protected so a peripheral hiccup never crashes a machine.
-- -------------------------------------------------------------------------- --

-- Returns full position/stats table for username, or nil.
function PDLib.getPlayerPos(username)
    if not _det or not username then return nil end
    local ok, result = pcall(_det.getPlayerPos, username)
    return ok and result or nil
end

-- Alias used by newer mod versions.
PDLib.getPlayer = PDLib.getPlayerPos

-- Returns a list of all online player usernames.
function PDLib.getOnlinePlayers()
    if not _det then return {} end
    local ok, result = pcall(_det.getOnlinePlayers)
    return (ok and result) or {}
end

-- Returns a list of usernames within range of the peripheral.
function PDLib.getPlayersInRange(range)
    if not _det then return {} end
    local ok, result = pcall(_det.getPlayersInRange, range or 5)
    return (ok and result) or {}
end

-- Returns a list of usernames within the axis-aligned bounding box
-- defined by posOne and posTwo ({x,y,z} tables).
function PDLib.getPlayersInCoords(posOne, posTwo)
    if not _det then return {} end
    local ok, result = pcall(_det.getPlayersInCoords, posOne, posTwo)
    return (ok and result) or {}
end

-- Returns a list of usernames within a cuboid (w x h x d) centered on the
-- peripheral.
function PDLib.getPlayersInCubic(w, h, d)
    if not _det then return {} end
    local ok, result = pcall(_det.getPlayersInCubic, w, h, d)
    return (ok and result) or {}
end

-- Returns true if username is within range of the peripheral.
function PDLib.isPlayerInRange(range, username)
    if not _det or not username then return false end
    local ok, result = pcall(_det.isPlayerInRange, range or 5, username)
    return ok and result == true
end

-- Returns true if username is within the bounding box.
function PDLib.isPlayerInCoords(posOne, posTwo, username)
    if not _det or not username then return false end
    local ok, result = pcall(_det.isPlayerInCoords, posOne, posTwo, username)
    return ok and result == true
end

-- Returns true if username is within the cuboid centered on the peripheral.
function PDLib.isPlayerInCubic(w, h, d, username)
    if not _det or not username then return false end
    local ok, result = pcall(_det.isPlayerInCubic, w, h, d, username)
    return ok and result == true
end

-- Returns true if any player is within range.
function PDLib.isPlayersInRange(range)
    if not _det then return false end
    local ok, result = pcall(_det.isPlayersInRange, range or 5)
    return ok and result == true
end

-- Returns true if any player is within the bounding box.
function PDLib.isPlayersInCoords(posOne, posTwo)
    if not _det then return false end
    local ok, result = pcall(_det.isPlayersInCoords, posOne, posTwo)
    return ok and result == true
end

-- Returns true if any player is within the cuboid.
function PDLib.isPlayersInCubic(w, h, d)
    if not _det then return false end
    local ok, result = pcall(_det.isPlayersInCubic, w, h, d)
    return ok and result == true
end

-- -------------------------------------------------------------------------- --
-- Session state accessors
-- Read from the game loop; written by listenerThread.
-- -------------------------------------------------------------------------- --

function PDLib.getCurrentPlayer()   return _session.player end
function PDLib.isGameActive()       return _session.gameActive end
function PDLib.setGameActive(v)     _session.gameActive = v end

-- Call this from the game loop after every player interaction so the idle
-- timer does not fire while the player is actively playing.
function PDLib.resetIdleTimer()
    if _session.idleTimer then
        -- Cancel the old timer by letting it fire harmlessly (CC has no
        -- os.cancelTimer, so we just replace the id and ignore old events).
    end
    _session.idleTimer = os.startTimer(IDLE_TIMEOUT)
end

-- Immediately clear the current session without waiting for timeout.
function PDLib.clearSession()
    _session.player    = nil
    _session.idleTimer = nil
    _session.gameActive = false
end

-- -------------------------------------------------------------------------- --
-- Listener thread
-- Run this with parallel.waitForAny alongside the game loop.
--
-- shared:     table with at least { shutdown = false }
-- callbacks:  table with optional functions:
--   onPlayerClick(username, previousPlayer)
--       Called when a player clicks the block. previousPlayer is the player
--       who was just overridden, or nil if the session was idle.
--   onPlayerJoin(username, dimension)
--       Called when any player joins the server.
--   onPlayerLeave(username, dimension)
--       Called when any player leaves the server. If username matches the
--       current session player the session is cleared automatically.
--   onPlayerChangedDimension(username, fromDim, toDim)
--       Called on dimension change. Session is cleared if it is the current
--       player (they effectively left the overworld).
--   onIdleTimeout(username)
--       Called when the idle timer fires while gameActive is false, meaning
--       the player clicked but never started a game.
-- -------------------------------------------------------------------------- --

function PDLib.listenerThread(shared, callbacks)
    callbacks = callbacks or {}

    local function fire(fn, ...)
        if fn then pcall(fn, ...) end
    end

    while not (shared and shared.shutdown) do
        local ev, p1, p2, p3 = os.pullEvent()

        -- A player physically right-clicked the detector block.
        if ev == "playerClick" then
            local username = p1
            local prev     = _session.player

            -- Override any existing session immediately.
            _session.player    = username
            _session.gameActive = false
            _session.idleTimer = os.startTimer(IDLE_TIMEOUT)

            fire(callbacks.onPlayerClick, username, prev)

        -- Idle timeout: player clicked but never interacted with the machine.
        elseif ev == "timer" and p1 == _session.idleTimer then
            _session.idleTimer = nil
            if not _session.gameActive and _session.player then
                local who = _session.player
                _session.player = nil
                fire(callbacks.onIdleTimeout, who)
            end

        -- A player joined the server (not the same as entering range).
        elseif ev == "playerJoin" then
            fire(callbacks.onPlayerJoin, p1, p2)

        -- A player left the server entirely.
        elseif ev == "playerLeave" then
            local username = p1
            if username == _session.player then
                _session.player    = nil
                _session.idleTimer = nil
                _session.gameActive = false
            end
            fire(callbacks.onPlayerLeave, username, p2)

        -- A player changed dimensions (effectively left the current world).
        elseif ev == "playerChangedDimension" then
            local username = p1
            if username == _session.player then
                _session.player    = nil
                _session.idleTimer = nil
                _session.gameActive = false
            end
            fire(callbacks.onPlayerChangedDimension, username, p2, p3)
        end
    end
end

return PDLib