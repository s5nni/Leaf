local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

-- Ensure global tables
getgenv().VisitedServers = getgenv().VisitedServers or {}
getgenv().ServerHopConfig = getgenv().ServerHopConfig or {
    MaxPages = 3,
    RetryDelay = 5,
    Timeout = 30, -- seconds to consider teleport failed
}

local function log(...)
    if getgenv().sendLog then
        getgenv().sendLog(...)
    else
        print(...)
    end
end

local function fetchServers(cursor)
    local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?limit=100"
    if cursor then
        url = url .. "&cursor=" .. cursor
    end
    local success, response = pcall(HttpService.GetAsync, HttpService, url)
    if not success then return nil end
    local success, data = pcall(HttpService.JSONDecode, HttpService, response)
    if not success then return nil end
    return data
end

local function getServers()
    local allServers = {}
    local cursor = nil
    for page = 1, getgenv().ServerHopConfig.MaxPages do
        local data = fetchServers(cursor)
        if not data then break end
        for _, server in ipairs(data.data or {}) do
            table.insert(allServers, server)
        end
        cursor = data.nextPageCursor
        if not cursor then break end
        task.wait(0.5)
    end
    return allServers
end

local function filterServers(servers)
    local currentJobId = game.JobId
    local valid = {}
    for _, s in ipairs(servers) do
        if s.id ~= currentJobId and not getgenv().VisitedServers[s.id] then
            if s.playing < s.maxPlayers then
                table.insert(valid, s)
            end
        end
    end
    -- sort by playing count ascending
    table.sort(valid, function(a, b) return a.playing < b.playing end)
    return valid
end

local function performHop()
    log("HOP", "Searching for a new server...")
    local servers = getServers()
    local valid = filterServers(servers)
    if #valid == 0 then
        log("WARNING", "No eligible servers found. Will retry later.")
        return false
    end
    local target = valid[1] -- least populated
    log("HOP", "Attempting to teleport to server " .. target.id .. " (" .. target.playing .. "/" .. target.maxPlayers .. ")")
    getgenv().VisitedServers[target.id] = true
    getgenv().PendingTeleport = true -- flag for post-hop check
    local success, err = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, game.PlaceId, target.id, Players.LocalPlayer)
    if not success then
        log("ERROR", "Teleport failed: " .. tostring(err))
        getgenv().PendingTeleport = nil
        return false
    end
    -- Start a timeout check: if after 30 seconds we are still in the same server, try again.
    task.spawn(function()
        task.wait(getgenv().ServerHopConfig.Timeout)
        if game.JobId == currentJobId then
            log("WARNING", "Teleport timed out (still in same server). Retrying...")
            performHop()
        end
    end)
    return true
end

-- Function to be called after teleport to check for s5nni players
local function checkForS5nniAndHop()
    if not getgenv().PendingTeleport then return end
    getgenv().PendingTeleport = nil
    -- Wait for players to load
    repeat task.wait(1) until #Players:GetPlayers() > 0
    task.wait(2) -- extra buffer
    local found = false
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower():find("s5nni") then
            found = true
            break
        end
    end
    if found then
        log("HOP", "Found 's5nni' in player names. Hopping again...")
        task.wait(2)
        performHop()
    end
end

-- Export functions
getgenv().ServerHop = {
    Hop = performHop,
    CheckAfterTeleport = checkForS5nniAndHop,
}

print("✅ ServerHop module loaded.")
