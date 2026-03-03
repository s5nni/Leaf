local ServerHop = {}
local MAX_PLAYERS = 5
local function getServerIP(placeId, serverId)
    local body = string.format('{"placeId":%d,"gameId":"%s","isTeleport":false,"gameJoinAttemptId":"%s"}', placeId, serverId, serverId)
    local success, response = pcall(function()
        return request({
            Url = "https://gamejoin.roblox.com/v1/join-game-instance",
            Method = "POST",
            Headers = {["Content-Type"] = "application/json", ["User-Agent"] = "Roblox/WinInet"},
            Body = body
        })
    end)
    if not success or not response or response.StatusCode ~= 200 then return nil end
    local bodyText = response.Body
    local machineAddr = bodyText:match('"MachineAddress":"([^"]+)"')
    if machineAddr then return machineAddr end
    local udmuxAddr = bodyText:match('"Address":"([^"]+)"')
    if udmuxAddr then return udmuxAddr end
    return nil
end
local function isUSAServer(ipAddress)
    local prefixes = {"104.", "128.116.", "162.", "199.", "66.", "72.", "192."}
    for _, p in ipairs(prefixes) do
        if ipAddress:sub(1, #p) == p then return true end
    end
    return false
end
local function getServerRegion(placeId, serverId)
    local cache = getgenv().ServerRegionCache
    if cache[serverId] then return cache[serverId] end
    local ip = getServerIP(placeId, serverId)
    if not ip then cache[serverId] = "unknown"; return "unknown" end
    local region = isUSAServer(ip) and "US" or "other"
    cache[serverId] = region
    return region
end
local function getCandidateServers(placeId, currentJobId)
    local servers = {}
    local cursor = nil
    local visited = getgenv().VisitedServers
    repeat
        local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"
        if cursor then url = url .. "&cursor=" .. cursor end
        local response = request({Url = url, Method = "GET"})
        if not response or response.StatusCode ~= 200 then break end
        local body = response.Body
        for id, playing, maxPlayers in body:gmatch('"id":"([^"]+)","maxPlayers":(%d+),"playing":(%d+),') do
            playing = tonumber(playing)
            maxPlayers = tonumber(maxPlayers)
            if not visited[id] and id ~= currentJobId and playing < maxPlayers and playing <= MAX_PLAYERS then
                table.insert(servers, {id = id, playing = playing, maxPlayers = maxPlayers})
            end
        end
        if #servers > 0 then break end
        cursor = body:match('"nextPageCursor":"([^"]+)"')
    until not cursor
    return servers
end
local function selectTargetServer(placeId, currentJobId)
    local servers = getCandidateServers(placeId, currentJobId)
    if #servers == 0 then return nil end
    table.sort(servers, function(a, b) return a.playing < b.playing end)
    local nonUSA = {}
    for _, s in ipairs(servers) do
        local region = getServerRegion(placeId, s.id)
        if region ~= "US" then table.insert(nonUSA, s) end
        task.wait(0.1)
    end
    if #nonUSA == 0 then nonUSA = servers end
    return nonUSA[1]
end
function ServerHop.hopToNewServer(player)
    local placeId = game.PlaceId
    local currentId = game.JobId
    getgenv().VisitedServers[currentId] = true
    local target = selectTargetServer(placeId, currentId)
    if not target then
        warn("No suitable server found, clearing visited and random teleport.")
        getgenv().VisitedServers = {}
        pcall(function() game:GetService("TeleportService"):Teleport(placeId, player) end)
        return
    end
    local TeleportService = game:GetService("TeleportService")
    pcall(function() clear_teleport_queue() end)
    pcall(function() queue_on_teleport(getgenv()._ServerHopSource) end)
    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, target.id, player)
    end)
    if not success then
        warn("Teleport failed: " .. tostring(err) .. ", retrying in 2s.")
        task.wait(2)
        ServerHop.hopToNewServer(player)
    end
end
function ServerHop.hasS5nniPlayer()
    local localPlayer = game:GetService("Players").LocalPlayer
    for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
        if plr ~= localPlayer and plr.Name:lower():find("s5nni") then
            return true
        end
    end
    return false
end
return ServerHop
