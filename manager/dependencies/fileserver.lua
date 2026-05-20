-- fileserver.lua
-- Listens for file requests from machines and sends them back over rednet
local PROTOCOL = "CASINO_FS"
local FILES = {
    -- Slot machine files
    "slot_startup.lua",
    "slot_machine.lua",

    -- Blackjack machine files
    "blackjack.lua",
    "bj_ui.lua",
    "bj_machine.lua",
    "bj_startup.lua",

    -- Add more here if you want to send them over the rednet.

    -- Shared
    "currency.lua",
    "rednet_manager.lua",
}
local function serveFiles()
    print("[FileServer] Ready on protocol: " .. PROTOCOL)
    while true do
        local senderId, msg = rednet.receive(PROTOCOL)
        if type(msg) == "table" then
            if msg.type == "list" then
                rednet.send(senderId, { type = "list_response", files = FILES }, PROTOCOL)
                print("[FileServer] Sent file list to ID " .. senderId)
            elseif msg.type == "get" and type(msg.file) == "string" then
                local filename = msg.file
                filename = filename:gsub("[/\\%.%.]", "")
                if fs.exists(filename) then
                    local f = fs.open(filename, "r")
                    local content = f.readAll()
                    f.close()
                    rednet.send(senderId, {
                        type    = "file_response",
                        file    = filename,
                        content = content,
                        ok      = true,
                    }, PROTOCOL)
                    print("[FileServer] Sent: " .. filename .. " -> ID " .. senderId)
                else
                    rednet.send(senderId, {
                        type = "file_response",
                        file = filename,
                        ok   = false,
                        err  = "File not found: " .. filename,
                    }, PROTOCOL)
                    print("[FileServer] Missing file requested: " .. filename)
                end
            end
        end
    end
end
return serveFiles