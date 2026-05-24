-- libraries/autocomplete.lua
-- Profile-based tab completion for any CLI.
--
-- Usage:
--   local AC = dofile("/libraries/autocomplete.lua")
--   AC.init({
--       commands  = { "help", "give", "whitelist add", "whitelist remove", ... },
--       resolvers = {
--           give             = function(argIndex) return { "alice", "bob" } end,
--           ["whitelist remove"] = function(argIndex) return { "12", "45" } end,
--       },
--       hintColor = colours.grey,   -- optional, default colours.grey
--   })
--
--   -- In your readline key loop:
--   AC.preview(table.concat(buf), colours.grey)   -- draw ghost text after cursor
--   AC.clearPreview()                              -- erase ghost text before printing
--
--   local completed = AC.complete(table.concat(buf))
--
-- Two-word commands ("whitelist add", "account remove") are fully supported:
--   - Typing "white<TAB>"  completes to "whitelist " then on next tab shows subcommands
--   - Typing "whitelist <TAB>" offers "add", "remove", "list" as continuations
--   - Resolvers keyed by the full two-word string fire on the argument after it

local M = {}

local _commands  = {}   -- sorted list of full command strings (may contain spaces)
local _resolvers = {}   -- key = full command string, value = function(argIndex) -> list
local _hintColor = nil  -- colour for ghost text; set in init

--  Helpers 

local function lcp(list)
    if #list == 0 then return "" end
    local prefix = list[1]
    for i = 2, #list do
        while list[i]:sub(1, #prefix) ~= prefix do
            prefix = prefix:sub(1, -2)
            if prefix == "" then return "" end
        end
    end
    return prefix
end

local function tokenise(input)
    local parts = {}
    for t in input:gmatch("%S+") do table.insert(parts, t) end
    local trailingSpace = input:match("%s$") ~= nil
    return parts, trailingSpace
end

-- Return every unique first word across all registered commands.
local function rootWords()
    local seen = {}
    local roots = {}
    for _, cmd in ipairs(_commands) do
        local root = cmd:match("^(%S+)")
        if root and not seen[root] then
            seen[root] = true
            table.insert(roots, root)
        end
    end
    return roots
end

-- Given a root word already typed, return all valid second words for that root.
local function subWords(root)
    local subs = {}
    local prefix = root .. " "
    for _, cmd in ipairs(_commands) do
        if cmd:sub(1, #prefix) == prefix then
            local rest = cmd:sub(#prefix + 1)
            local sub  = rest:match("^(%S+)")
            if sub and sub ~= "" then
                table.insert(subs, sub)
            end
        end
    end
    return subs
end

-- Is this exact string a registered command?
local function isCommand(s)
    for _, cmd in ipairs(_commands) do
        if cmd == s then return true end
    end
    return false
end

--  Ghost text 

local _lastPreviewLen = 0

-- Draw ghost text after the cursor showing the completion hint.
-- Call this after every character is echoed in your readline loop.
function M.preview(inputBuf, color)
    if inputBuf == "" then
        M.clearPreview()
        return
    end

    local completed = M.complete(inputBuf)
    local suffix = completed:sub(#inputBuf + 1)

    -- strip trailing space from suffix so ghost text shows the token only
    suffix = suffix:match("^(.-)%s*$") or suffix

    M.clearPreview()
    if suffix == "" then return end

    local cx, cy = term.getCursorPos()
    term.setTextColor(color or _hintColor or colours.grey)
    term.write(suffix)
    term.setTextColor(colours.white)
    term.setCursorPos(cx, cy)   -- restore cursor to before the ghost text
    _lastPreviewLen = #suffix
end

-- Erase ghost text drawn by preview().
function M.clearPreview()
    if _lastPreviewLen == 0 then return end
    local cx, cy = term.getCursorPos()
    term.write(string.rep(" ", _lastPreviewLen))
    term.setCursorPos(cx, cy)
    _lastPreviewLen = 0
end

--  Init 

function M.init(profile)
    _commands  = profile.commands  or {}
    _resolvers = profile.resolvers or {}
    _hintColor = profile.hintColor or colours.grey
    table.sort(_commands)
end

--  Complete 

function M.complete(inputBuf)
    local parts, trailingSpace = tokenise(inputBuf)
    if #parts == 0 then return inputBuf end

    --  Stage 1: completing the first word 
    if #parts == 1 and not trailingSpace then
        local partial = parts[1]
        local roots   = rootWords()
        local matches = {}
        for _, r in ipairs(roots) do
            if r:sub(1, #partial) == partial then
                table.insert(matches, r)
            end
        end
        if #matches == 0 then return inputBuf end
        if #matches == 1 then return matches[1] .. " " end
        local prefix = lcp(matches)
        if #prefix <= #partial then return inputBuf end
        return prefix
    end

    --  Stage 2: first word is complete, check for subcommand 
    local root = parts[1]

    -- If a two-word command is fully typed, move to argument completion below.
    -- If only the root is typed (trailing space) or a partial second word,
    -- offer the matching subcommands.
    local twoWordCmd = nil
    if #parts >= 2 then
        local candidate = root .. " " .. parts[2]
        if isCommand(candidate) then
            twoWordCmd = candidate
        end
    end

    -- Second word is still being typed or root just got a trailing space.
    local subs = subWords(root)
    if #subs > 0 then
        -- We have subcommands for this root.
        local partial = (not trailingSpace and #parts == 2) and parts[2] or
                        (trailingSpace and #parts == 1) and "" or nil

        if partial ~= nil and not twoWordCmd then
            -- Still completing the subcommand word.
            local matches = {}
            for _, s in ipairs(subs) do
                if s:sub(1, #partial) == partial then
                    table.insert(matches, s)
                end
            end
            if #matches == 0 then return inputBuf end
            if #matches == 1 then return root .. " " .. matches[1] .. " " end
            local prefix = lcp(matches)
            if #prefix <= #partial then return inputBuf end
            return root .. " " .. prefix
        end
    end

    --  Stage 3: argument completion 
    -- Determine which command key to look up in resolvers.
    local cmdKey
    if twoWordCmd then
        cmdKey = twoWordCmd
    elseif isCommand(root) then
        cmdKey = root
    else
        return inputBuf
    end

    local resolver = _resolvers[cmdKey]
    if not resolver then return inputBuf end

    -- argIndex counts arguments after the command (1 = first arg after command).
    -- For a two-word command "whitelist remove 12", parts = {"whitelist","remove","12"},
    -- twoWordCmd is set, so argument starts at parts[3].
    local argStart  = twoWordCmd and 3 or 2
    local argIndex  = trailingSpace and (#parts - argStart + 2) or (#parts - argStart + 1)
    local partial   = (not trailingSpace) and parts[#parts] or ""

    -- Don't try to complete if we're still on the subcommand token itself.
    if twoWordCmd and #parts < argStart then return inputBuf end
    if twoWordCmd and not trailingSpace and #parts == 2 then return inputBuf end

    local candidates = resolver(argIndex) or {}
    local matches = {}
    for _, c in ipairs(candidates) do
        local cs = tostring(c)
        if cs:sub(1, #partial) == partial then
            table.insert(matches, cs)
        end
    end

    if #matches == 0 then return inputBuf end

    -- Rebuild everything before the token being completed.
    local rebuilt = {}
    for i = 1, #parts - (trailingSpace and 0 or 1) do
        table.insert(rebuilt, parts[i])
    end

    if #matches == 1 then
        table.insert(rebuilt, matches[1])
        return table.concat(rebuilt, " ") .. " "
    end

    local prefix = lcp(matches)
    if #prefix <= #partial then return inputBuf end
    table.insert(rebuilt, prefix)
    return table.concat(rebuilt, " ")
end

return M