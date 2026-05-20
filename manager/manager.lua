-- manager.lua
-- Casino Manager 

local Data        = dofile("dependencies/data.lua")
local Net         = dofile("dependencies/rednet_manager.lua")
local UI          = dofile("dependencies/ui.lua")
local Logger      = dofile("dependencies/logger.lua")
local Leaderboard = dofile("dependencies/leaderboards/leaderboard.lua")
local Currency    = dofile("dependencies/currency.lua")

-- CONFIG

local CHIP_VALUE_SPURS = 8   -- default: 1 chip = 8 spurs (1 bevel)

local function loadChipValue()
    if fs.exists("chip_value.txt") then
        local f = fs.open("chip_value.txt", "r")
        if f then
            local n = tonumber(f.readLine())
            f.close()
            if n and n > 0 then
                CHIP_VALUE_SPURS = n
                Logger.info("Chip value loaded: 1 chip = " .. n .. " spurs")
                return
            end
        end
    end
    Logger.info("Chip value: default 1 chip = " .. CHIP_VALUE_SPURS .. " spurs")
end

-- RESERVE BARREL

local RESERVE_NAME = nil   -- loaded from reserve.txt

local function loadReserveConfig()
    if fs.exists("reserve.txt") then
        local f = fs.open("reserve.txt", "r")
        if f then
            local line = f.readLine()
            f.close()
            if line then
                line = line:match("^%s*(.-)%s*$")  -- trim whitespace
                if line ~= "" then
                    RESERVE_NAME = line
                    Logger.info("Reserve configured: " .. RESERVE_NAME)
                    return
                end
            end
        end
    end
    Logger.warn("reserve.txt not found or empty — reserve balance unavailable")
end

local function readReserve()
    if not RESERVE_NAME then
        return 0, 0, "No reserve configured"
    end

    local barrel = peripheral.wrap(RESERVE_NAME)
    if not barrel then
        return 0, 0, "Reserve not found: " .. RESERVE_NAME
    end

    local ok, result = pcall(function()
        local contents = barrel.list()
        local chips = 0
        for _, stack in pairs(contents) do
            if stack.name == "createdeco:brass_coin" then
                chips = chips + stack.count
            end
        end
        return chips
    end)

    if not ok then
        return 0, 0, "Error reading reserve: " .. tostring(result)
    end

    local spurs = result * CHIP_VALUE_SPURS
    return result, spurs, nil
end

local function updateReserve()
    local chips, spurs, err = readReserve()
    if err then
        Logger.warn("Reserve: " .. err)
        Data.setGlobalStat("reserveSpurs", 0)
    else
        Logger.info("Reserve: " .. chips .. " chips = " .. Currency.format(spurs))
        Data.setGlobalStat("reserveSpurs", spurs)
    end
end

-- FILE SERVER

local LEADERBOARD_RELAY_ID = 43

local FS_PROTOCOL = "CASINO_FS"

local FS_FILES = {
    "slot_startup.lua",
    "slot_machine.lua",
    "blackjack.lua",
    "bj_ui.lua",
    "bj_machine.lua",
    "bj_startup.lua",
    "currency.lua",
    "rednet_manager.lua",
    "player_detector.lua",
}

local function handleFileRequest(senderId, msg)
    if type(msg) ~= "table" then
        Logger.warn("FS: non-table message from ID " .. senderId)
        return
    end

    Logger.logNet(senderId, FS_PROTOCOL, msg)

    if msg.type == "ping" then
        rednet.send(senderId, { type = "pong" }, FS_PROTOCOL)
        Logger.info("FS: ping from ID " .. senderId .. " -> pong sent")

    elseif msg.type == "list" then
        rednet.send(senderId, { type = "list_response", files = FS_FILES }, FS_PROTOCOL)
        Logger.info("FS: sent file list (" .. #FS_FILES .. " files) to ID " .. senderId)

    elseif (msg.type == "get" or msg.type == "request") and type(msg.file) == "string" then
        local filename = msg.file:gsub("[/\\]", ""):gsub("%.%.", "")
        Logger.info("FS: file request '" .. filename .. "' from ID " .. senderId)

        if fs.exists(filename) then
            local f = fs.open(filename, "r")
            local content = f.readAll()
            f.close()
            rednet.send(senderId, {
                type    = "file_response",
                file    = filename,
                content = content,
                ok      = true,
            }, FS_PROTOCOL)
            Logger.info("FS: sent '" .. filename .. "' (" .. #content .. " bytes) to ID " .. senderId)
        else
            rednet.send(senderId, {
                type = "file_response",
                file = filename,
                ok   = false,
                err  = "File not found: " .. filename,
            }, FS_PROTOCOL)
            Logger.warn("FS: file not found '" .. filename .. "' (requested by ID " .. senderId .. ")")
        end
    else
        Logger.warn("FS: unknown message type '" .. tostring(msg.type) .. "' from ID " .. senderId)
    end
end

-- INIT

Logger.init()
Logger.info("Casino Manager starting up...")

loadChipValue()
loadReserveConfig()

Data.load()
Logger.info("Data loaded.")
Leaderboard.load()
Logger.info("Leaderboard loaded.")

if not Net.open() then
    Logger.error("No wireless modem found!")
    error("No wireless modem found! Attach one and restart.")
end
Logger.info("Modem online. Manager ID: " .. os.getComputerID())

local ok, uiErr = pcall(UI.init)
if not ok then
    Logger.warn("Monitor init failed: " .. tostring(uiErr))
    Logger.warn("Continuing without monitor display.")
else
    Logger.info("Monitor initialised.")
end

updateReserve()

-- HELPERS

local PING_INTERVAL  = 15
local OFFLINE_THRESH = 45
local lastPingTime   = 0

local function refreshUI()
    local machines    = Data.getAllMachines()
    local globalStats = Data.globalStats()
    UI.setMachines(machines, globalStats)
    UI.draw()
end

local function pingAllMachines()
    local machines = Data.getAllMachines()
    local ids = {}
    for _, m in ipairs(machines) do table.insert(ids, m.id) end
    if #ids == 0 then
        Logger.debug("Ping: no machines registered, skipping.")
        return
    end

    Logger.info("Pinging " .. #ids .. " machine(s)...")
    UI.setStatus("Pinging " .. #ids .. " machine(s)...", 3)
    local results = Net.pingAll(ids, 3)
    local alive = 0
    for id, isAlive in pairs(results) do
        Data.setConfig(id, "online", isAlive)
        if isAlive then
            alive = alive + 1
            Logger.debug("Ping: ID " .. id .. " online")
        else
            Logger.debug("Ping: ID " .. id .. " no response")
        end
    end
    Data.pruneOffline(OFFLINE_THRESH)
    Logger.info("Ping done: " .. alive .. "/" .. #ids .. " online.")
    UI.setStatus("Ping done. " .. alive .. "/" .. #ids .. " online.", 3)
end

local function sendConfigToMachine(machine)
    Logger.info("Sending config to " .. machine.label .. " (ID " .. machine.id .. ")")
    Net.sendConfig(machine.id, {
        winPercent = machine.winPercent,
        enabled    = machine.enabled,
        label      = machine.label,
    })
    UI.setStatus("Config sent to " .. machine.label, 3)
end

local function termPrompt(prompt, default)
    term.write(prompt)
    if default then term.write("[" .. tostring(default) .. "]: ")
    else term.write(": ") end
    local input = read()
    if input == "" then return default end
    return input
end

-- PLAY RESULT HANDLER (shared across all game types)

-- Called after any completed hand/play from any machine type.
-- Re-reads the reserve barrel so the UI always reflects real chip count.
local function onPlayResult()
    updateReserve()
end

-- BLACKJACK HAND RESULT HANDLER

local PAYOUT_RATIOS = {
    win       = 2.0,
    blackjack = 2.5,
    push      = 1.0,
    loss      = 0.0,
}

local function handleBlackjackResult(senderId, msg)
    local betChips   = msg.bet    or 0
    local result     = msg.result or "loss"
    local player     = msg.player or "Unknown"
    local mult       = PAYOUT_RATIOS[result] or 0

    local betSpurs    = betChips * CHIP_VALUE_SPURS
    local payoutChips = math.floor(betChips * mult)
    local payoutSpurs = payoutChips * CHIP_VALUE_SPURS

    local profitSpurs = betSpurs - payoutSpurs

    local profitStr
    if profitSpurs >= 0 then
        profitStr = "+" .. Currency.format(profitSpurs)
    else
        profitStr = "-" .. Currency.format(-profitSpurs)
    end
    Logger.info("BJ result from ID " .. senderId
        .. ": player=" .. player
        .. " result=" .. result
        .. " bet=" .. betChips .. " chips (" .. Currency.format(betSpurs) .. ")"
        .. " payout=" .. payoutChips .. " chips (" .. Currency.format(payoutSpurs) .. ")"
        .. " house profit=" .. profitStr)


    Leaderboard.recordHand(player, result, betChips, payoutChips)
    Leaderboard.broadcast(LEADERBOARD_RELAY_ID)

    Data.recordPlay(senderId, betSpurs, payoutSpurs, result == "win" or result == "blackjack")
    Data.setConfig(senderId, "online",   true)
    Data.setConfig(senderId, "lastSeen", os.time())

    local m     = Data.getMachine(senderId)
    local label = m and m.label or ("ID " .. senderId)
    UI.setStatus(label .. ": " .. player
        .. " " .. result
        .. " | bet " .. Currency.format(betSpurs)
        .. " | pay " .. Currency.format(payoutSpurs), 4)

    onPlayResult()
end

-- SLOTS RESULT HANDLER

local function handleSlotsResult(senderId, msg)
    local p = msg.payload or {}
    Logger.info("Slots result from ID " .. senderId
        .. " in=" .. tostring(p.amountIn) .. " out=" .. tostring(p.amountOut))
    Data.recordPlay(senderId, p.amountIn or 0, p.amountOut or 0, p.won or false)
    Data.setConfig(senderId, "online",   true)
    Data.setConfig(senderId, "lastSeen", os.time())

    onPlayResult()
end

-- FUTURE GAME RESULT HANDLERS 

local function handleRouletteResult(senderId, msg)
    -- TODO: implement roulette result recording
    Logger.info("Roulette result from ID " .. senderId .. " (not yet implemented)")
    onPlayResult()
end

local function handlePokerResult(senderId, msg)
    -- TODO: implement poker result recording
    Logger.info("Poker result from ID " .. senderId .. " (not yet implemented)")
    onPlayResult()
end

local function handleDiceResult(senderId, msg)
    -- TODO: implement dice result recording
    Logger.info("Dice result from ID " .. senderId .. " (not yet implemented)")
    onPlayResult()
end

local function handleCrashResult(senderId, msg)
    -- TODO: implement crash result recording
    Logger.info("Crash result from ID " .. senderId .. " (not yet implemented)")
    onPlayResult()
end

-- NET MESSAGE HANDLER

local function handleNetMessage(senderId, msg)
    if type(msg) ~= "table" then
        Logger.warn("NET: non-table message from ID " .. senderId)
        return
    end

    Logger.logNet(senderId, Net.PROTOCOL, msg)

    if msg.type == "register" then
        Logger.info("NET: register from ID " .. senderId
            .. " game=" .. tostring(msg.game)
            .. " label=" .. tostring(msg.label))

        local m = Data.registerMachine(senderId, {
            label      = msg.label,
            game       = msg.game,
            winPercent = msg.winPercent or 30,
        })

        local reply = {
            type         = "config",
            betAmount    = m.betAmount or 2,
            machineLabel = m.label,
            winPercent   = m.winPercent,
            enabled      = m.enabled,
        }
        rednet.send(senderId, reply, Net.PROTOCOL)
        Logger.logSend(senderId, Net.PROTOCOL, reply)
        Logger.info("NET: config sent to " .. m.label .. " (ID " .. senderId .. ")")
        UI.setStatus("Registered: " .. m.label .. " (ID " .. senderId .. ")", 5)

    elseif msg.type == "hand_result" then
        handleBlackjackResult(senderId, msg)

    elseif msg.type == "play_result" then
        handleSlotsResult(senderId, msg)

    elseif msg.type == "roulette_result" then
        handleRouletteResult(senderId, msg)

    elseif msg.type == "poker_result" then
        handlePokerResult(senderId, msg)

    elseif msg.type == "dice_result" then
        handleDiceResult(senderId, msg)

    elseif msg.type == "crash_result" then
        handleCrashResult(senderId, msg)

    elseif msg.type == Net.EVT.PONG then
        Logger.debug("NET: pong from ID " .. senderId)
        Data.setConfig(senderId, "online",   true)
        Data.setConfig(senderId, "lastSeen", os.time())

    elseif msg.type == Net.EVT.PLAY_RESULT then
        handleSlotsResult(senderId, msg)

    elseif msg.type == Net.EVT.STATS then
        local p = msg.payload or {}
        Logger.debug("NET: stats update from ID " .. senderId)
        if p.totalIn    ~= nil then Data.setConfig(senderId, "totalIn",    p.totalIn)    end
        if p.totalOut   ~= nil then Data.setConfig(senderId, "totalOut",   p.totalOut)   end
        if p.totalPlays ~= nil then Data.setConfig(senderId, "totalPlays", p.totalPlays) end

    elseif msg.type == Net.EVT.REGISTER then
        Logger.info("NET: legacy register from ID " .. senderId)
        local info = msg.payload or {}
        local m = Data.registerMachine(senderId, {
            label      = info.label,
            winPercent = info.winPercent or 30,
        })
        Net.sendConfig(senderId, {
            winPercent = m.winPercent,
            enabled    = m.enabled,
            label      = m.label,
        })
        UI.setStatus("Machine online: " .. m.label .. " (ID " .. senderId .. ")", 5)

    elseif msg.type == Net.EVT.ERROR then
        local m     = Data.getMachine(senderId)
        local label = m and m.label or ("ID " .. senderId)
        local errMsg = tostring((msg.payload or {}).msg)
        Logger.error("NET: error from " .. label .. ": " .. errMsg)
        UI.setStatus("ERR from " .. label .. ": " .. errMsg, 5)

    else
        Logger.warn("NET: unknown message type '" .. tostring(msg.type)
            .. "' from ID " .. senderId)
    end
end

-- KEY HANDLER

local function handleKey(key)
    local screen = UI.getScreen()

    if screen == "list" then
        if key == keys.up then
            UI.navigate(-1)
        elseif key == keys.down then
            UI.navigate(1)
        elseif key == keys.enter then
            UI.openDetail()
        elseif key == keys.r then
            pingAllMachines()
        elseif key == keys.a then
            term.setCursorPos(1, 19)
            local idStr = termPrompt("Machine rednet ID to register", "")
            local id = tonumber(idStr)
            if id then
                Logger.info("Manually registering machine ID " .. id)
                local m = Data.registerMachine(id, { label = "Machine #" .. id })
                Net.sendConfig(id, { winPercent = m.winPercent, enabled = m.enabled })
                UI.setStatus("Registered machine ID " .. id, 4)
            else
                Logger.warn("Manual register: invalid ID entered")
                UI.setStatus("Invalid ID.", 3)
            end
        elseif key == keys.q then
            Logger.info("Quit key pressed. Shutting down.")
            return "quit"
        end

    elseif screen == "detail" then
        if key == keys.escape then
            UI.backToList()
        elseif key == keys.c then
            UI.openConfig()
        elseif key == keys.t then
            local m = UI.getSelectedMachine()
            if m then
                local newVal = not m.enabled
                Data.setConfig(m.id, "enabled", newVal)
                Net.send(m.id, newVal and Net.MSG.ENABLE or Net.MSG.DISABLE, {})
                Logger.info((newVal and "Enabled" or "Disabled") .. " machine " .. m.label)
                UI.setStatus((newVal and "Enabled: " or "Disabled: ") .. m.label, 3)
            end
        elseif key == keys.p then
            local m = UI.getSelectedMachine()
            if m then
                Logger.info("Manual ping: " .. m.label .. " (ID " .. m.id .. ")")
                UI.setStatus("Pinging " .. m.label .. "...", 2)
                refreshUI()
                local alive = Net.ping(m.id, 3)
                Data.setConfig(m.id, "online", alive)
                Logger.info("Ping result: " .. m.label .. " -> " .. (alive and "online" or "no response"))
                UI.setStatus(m.label .. (alive and " is online" or " not responding"), 4)
            end
        elseif key == keys.r then
            local m = UI.getSelectedMachine()
            if m then
                term.setCursorPos(1, 19)
                local confirm = termPrompt("Reset stats for " .. m.label .. "? (yes/no)", "no")
                if confirm == "yes" then
                    Logger.info("Stats reset for " .. m.label .. " (ID " .. m.id .. ")")
                    Data.setConfig(m.id, "totalIn",    0)
                    Data.setConfig(m.id, "totalOut",   0)
                    Data.setConfig(m.id, "totalPlays", 0)
                    Net.send(m.id, Net.MSG.RESET_STATS, {})
                    UI.setStatus("Stats reset for " .. m.label, 3)
                end
            end
        end

    elseif screen == "config" then
        if key == keys.escape then
            UI.closeConfig()
        elseif key == keys.up then
            UI.configNav(-1)
        elseif key == keys.down then
            UI.configNav(1)
        elseif key == keys.enter then
            local field = UI.getCurrentConfigField()
            local draft = UI.getConfigDraft()
            term.setCursorPos(1, 19)
            local raw = termPrompt("Set " .. field.label, tostring(draft[field.key] or ""))
            if field.type == "number" then
                local n = tonumber(raw)
                if n then
                    if field.min then n = math.max(field.min, n) end
                    if field.max then n = math.min(field.max, n) end
                    UI.setConfigDraftValue(field.key, n)
                end
            elseif field.type == "bool" then
                UI.setConfigDraftValue(field.key,
                    raw:lower() == "true" or raw == "1" or raw:lower() == "yes")
            else
                UI.setConfigDraftValue(field.key, raw)
            end
        elseif key == keys.s then
            local m = UI.getSelectedMachine()
            local draft = UI.getConfigDraft()
            if m then
                Logger.info("Saving config for " .. m.label)
                for k, v in pairs(draft) do
                    Data.setConfig(m.id, k, v)
                end
                sendConfigToMachine(Data.getMachine(m.id))
                UI.closeConfig()
            end
        end
    end

    return nil
end

-- MAIN LOOP

refreshUI()
UI.setStatus("Manager online. ID: " .. os.getComputerID()
    .. " | 1 chip = " .. Currency.format(CHIP_VALUE_SPURS), 5)
Logger.info("Main loop starting. Ready. Chip value: 1 chip = "
    .. CHIP_VALUE_SPURS .. " spurs (" .. Currency.format(CHIP_VALUE_SPURS) .. ")")

local function mainLoop()
    while true do
        refreshUI()

        local now = os.time()
        if (now - lastPingTime) >= PING_INTERVAL then
            lastPingTime = now
            pingAllMachines()
        end

        local event, p1, p2, p3 = os.pullEventRaw()

        if event == "key" then
            local result = handleKey(p1)
            if result == "quit" then return end

        elseif event == "rednet_message" then
            Logger.debug("EVENT: rednet_message from=" .. tostring(p1)
                .. " protocol=" .. tostring(p3))
            if p3 == Net.PROTOCOL then
                handleNetMessage(p1, p2)
            elseif p3 == FS_PROTOCOL then
                handleFileRequest(p1, p2)
            elseif p3 == "CASINO_LOG" then
                if type(p2) == "table" and p2.line then
                    Logger.info("REMOTE: " .. tostring(p2.line))
                end
            else
                Logger.warn("EVENT: unknown protocol '" .. tostring(p3)
                    .. "' from ID " .. tostring(p1))
            end

        elseif event == "terminate" then
            Logger.info("Terminate signal received. Shutting down.")
            return
        end
    end
end

mainLoop()

Logger.info("Casino Manager shutdown.")
print("[Casino Manager] Shutdown.")