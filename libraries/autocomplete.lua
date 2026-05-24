-- libraries/autocomplete.lua
-- Profile-based tab completion for any CLI.
--
-- Usage:
--   local AC = dofile("/libraries/autocomplete.lua")
--   AC.init({
--       commands  = { "help", "give", "take", ... },
--       resolvers = {
--           -- optional per-command argument resolvers
--           give = function(argIndex) return { "alice", "bob" } end,
--       },
--   })
--   local completed = AC.complete(inputBuf)
--
-- Returns the completed input string (same as inputBuf if nothing matched).

local M = {}

local _commands  = {}
local _resolvers = {}

function M.init(profile)
    _commands  = profile.commands  or {}
    _resolvers = profile.resolvers or {}
    table.sort(_commands)
end

-- Longest common prefix of a list of strings.
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

-- Tokenise input, preserving trailing-space awareness.
local function tokenise(input)
    local parts = {}
    for t in input:gmatch("%S+") do table.insert(parts, t) end
    local trailingSpace = input:match("%s$") ~= nil
    return parts, trailingSpace
end

function M.complete(inputBuf)
    local parts, trailingSpace = tokenise(inputBuf)

    -- empty input: nothing to complete
    if #parts == 0 then return inputBuf end

    -- completing the command name itself
    if #parts == 1 and not trailingSpace then
        local partial  = parts[1]
        local matches  = {}
        for _, cmd in ipairs(_commands) do
            if cmd:sub(1, #partial) == partial then
                table.insert(matches, cmd)
            end
        end
        if #matches == 0 then return inputBuf end
        if #matches == 1 then return matches[1] .. " " end
        local prefix = lcp(matches)
        if #prefix <= #partial then return inputBuf end
        return prefix
    end

    -- completing a command argument
    local cmd = parts[1]
    local resolver = _resolvers[cmd]
    if not resolver then return inputBuf end

    -- which argument index are we on?
    local argIndex = trailingSpace and (#parts) or (#parts - 1)
    local partial  = (not trailingSpace and parts[#parts]) or ""

    local candidates = resolver(argIndex) or {}
    local matches = {}
    for _, c in ipairs(candidates) do
        if c:sub(1, #partial) == partial then
            table.insert(matches, c)
        end
    end

    if #matches == 0 then return inputBuf end
    if #matches == 1 then
        -- rebuild: everything up to the completed token, then append
        local rebuilt = {}
        for i = 1, #parts - (trailingSpace and 0 or 1) do
            table.insert(rebuilt, parts[i])
        end
        table.insert(rebuilt, matches[1])
        return table.concat(rebuilt, " ") .. " "
    end

    local prefix = lcp(matches)
    if #prefix <= #partial then return inputBuf end
    local rebuilt = {}
    for i = 1, #parts - (trailingSpace and 0 or 1) do
        table.insert(rebuilt, parts[i])
    end
    table.insert(rebuilt, prefix)
    return table.concat(rebuilt, " ")
end

return M