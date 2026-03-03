-- serverhop.lua
-- Server Hop functionality for Leaf (Jailbreak Robbery Logger)
-- Adds region filtering and max player controls.

-- Ensure required global tables exist
getgenv().VisitedServers = getgenv().VisitedServers or {}
getgenv().ServerRegionCache = getgenv().ServerRegionCache or {} -- Optional: for caching region mappings

-- =============================================
--          CONFIGURATION (USER TOGGLES)
-- =============================================
getgenv().ServerHopConfig = {
    -- Region Toggles: Set to true to ALLOW hopping to that region
    AllowedRegions = {
        US = true,      -- United States (default)
        EU = true,      -- Europe
        AS = true,      -- Asia
        AU = true,      -- Australia
        SA = true,      -- South America
        -- Add more regions if needed
    },
    -- Player Filter: Maximum players allowed in target server (0 = no limit)
    MaxPlayers = 30,    -- Typical Jailbreak server max is ~30, adjust as needed
    -- Hop Delay: Seconds to wait before attempting another hop
    HopDelay = 5,
    -- Logging: Send Discord log when hopping?
    LogHops = true,
}

-- =============================================
--          HELPER FUNCTIONS
-- =============================================
local function getLogger()
    -- Accesses the logging function from main.lua if available
    return getgenv().sendLog or function() end
end

local function getJoinLink(jobId)
    -- Replicates the join link builder from main.lua
    local placeId = game.PlaceId
    local http = game:GetService("HttpService")
    return "https://s5nni.github.io/Leaf-Joiner/?placeId=" .. placeId .. "&jobId=" .. http:UrlEncode(jobId)
end

-- =============================================
--          REGION DETECTION (SIMULATED)
-- =============================================
-- Roblox does NOT expose server region to scripts.
-- This is a SIMULATED approach using server IP ping as a proxy.
-- For a real implementation, you'd need a backend service mapping IPs to regions.

local function getServerRegionFromPing(jobId, serverIp)
    -- This is a placeholder. In reality, you'd query a database or external service.
    -- Here we simulate based on the server's IP address prefix (if available).
    -- Returns: string region code (e.g., "US", "EU") or "Unknown"
    
    -- OPTION 1: If you have a way to get server IP (advanced executors), you could map it.
    -- Example (pseudo-code):
    -- local ip = getServerIp(jobId) -- Not a real Roblox function
    -- if ip:match("^192\.168") then return "US" end -- Fake example
    
    -- OPTION 2: Default to "US" as fallback
    return "US" -- Default region
end

-- =============================================
--          FETCH PUBLIC SERVERS
-- =============================================
local function fetchServers(cursor)
    local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?limit=100"
    if cursor then
        url = url .. "&cursor=" .. cursor
    end
    
    local success, response = pcall(function()
        return game:HttpGet(url)
    end)
    
    if not success then
        return nil, "HTTP request failed"
    end
    
    local success, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(response)
    end)
    
    if not success then
        return nil, "JSON decode failed"
    end
    
    return data, nil
end

-- =============================================
--          FILTER SERVERS
-- =============================================
local function filterServers(servers)
    local config = getgenv().ServerHopConfig
    local visited = getgenv().VisitedServers
    local validServers = {}
    
    for _, server in ipairs(servers) do
        -- Skip if already visited
        if not visited[server.id] then
            -- Check player count
            local playing = server.playing or 0
            local maxPlayers = server.maxPlayers or 30
            local isJoinable = (playing < maxPlayers) and (config.MaxPlayers == 0 or playing <= config.MaxPlayers)
            
            if isJoinable then
                -- Determine server region (simulated)
                local region = getServerRegionFromPing(server.id, server.ip) -- server.ip may not exist
                -- If region detection fails, try to infer from server name or other data
                if region == "Unknown" then
                    region = "US" -- Default fallback
                end
                
                -- Check if region is allowed
                if config.AllowedRegions[region] then
                    table.insert(validServers, {
                        id = server.id,
                        playing = playing,
                        maxPlayers = maxPlayers,
                        region = region,
                        ping = server.ping or 0
                    })
                end
            end
        end
    end
    
    -- Sort by player count (least populated first) for better hopping
    table.sort(validServers, function(a, b)
        return a.playing < b.playing
    end)
    
    return validServers
end

-- =============================================
--          MAIN HOP FUNCTION
-- =============================================
local function performHop()
    local logger = getLogger()
    local config = getgenv().ServerHopConfig
    local visited = getgenv().VisitedServers
    
    logger("HOP", "Starting server hop search", "Scanning for eligible servers...")
    
    local cursor = nil
    local allValidServers = {}
    
    -- Fetch up to 3 pages of servers (adjust as needed)
    for page = 1, 3 do
        local data, err = fetchServers(cursor)
        if not data then
            logger("ERROR", "Server fetch failed", err)
            break
        end
        
        local valid = filterServers(data.data or {})
        for _, v in ipairs(valid) do
            table.insert(allValidServers, v)
        end
        
        if data.nextPageCursor then
            cursor = data.nextPageCursor
            task.wait(0.5) -- Be polite to API
        else
            break
        end
    end
    
    if #allValidServers == 0 then
        logger("WARNING", "No eligible servers found", "Check region toggles or max player setting.")
        return false
    end
    
    -- Pick the first (least populated) valid server
    local target = allValidServers[1]
    local joinLink = getJoinLink(target.id)
    
    -- Mark as visited to avoid future hops
    visited[target.id] = true
    
    -- Log the hop
    if config.LogHops then
        local fields = {
            { name = "🎯 Target Server", value = "`" .. target.id .. "`", inline = false },
            { name = "🌍 Region", value = target.region, inline = true },
            { name = "👥 Players", value = target.playing .. "/" .. target.maxPlayers, inline = true },
            { name = "🔗 Join Link", value = "[Click to Join](" .. joinLink .. ")", inline = false },
        }
        logger("HOP", "Server Hop Initiated", "Moving to new server", fields)
    end
    
    -- Execute the teleport
    local TeleportService = game:GetService("TeleportService")
    local player = game:GetService("Players").LocalPlayer
    
    if player then
        TeleportService:TeleportToPlaceInstance(game.PlaceId, target.id, player)
    end
    
    return true
end

-- =============================================
--          EXPOSED API
-- =============================================
getgenv().ServerHop = {
    Hop = performHop,
    Config = getgenv().ServerHopConfig,
    -- Utility to clear visited servers (if needed)
    ClearVisited = function()
        getgenv().VisitedServers = {}
        print("Visited servers list cleared.")
    end,
}

-- Optional: Auto-hop loop if you want continuous hopping
-- (Commented out by default - enable if needed)
--[[
task.spawn(function()
    while true do
        local success = performHop()
        if success then
            break -- Stop after successful hop
        end
        task.wait(getgenv().ServerHopConfig.HopDelay)
    end
end)
--]]

print("✅ ServerHop module loaded. Use getgenv().ServerHop.Hop() to hop.")
