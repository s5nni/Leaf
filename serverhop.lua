-- serverhop.lua
local ServerHop = {}

local MAX_PLAYERS = 5

local function getServerIP(placeId, serverId)
    local success, response = pcall(function()
        return request({
            Url = "https://gamejoin.roblox.com/v1/join-game-instance",
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["User-Agent"] = "Roblox/WinInet"
            },
            Body = game:GetService("HttpService"):JSONEncode({
                placeId = placeId,
                gameId = serverId,
                isTeleport = false,
                gameJoinAttemptId = serverId
            })
        })
    end)
    if not success then return nil end
    if response.StatusCode ~= 200 then return nil end
    local ok, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(response.Body)
    end)
    if not ok then return nil end
    if data.joinScript and data.joinScript.MachineAddress then
        return data.joinScript.MachineAddress
    end
    if data.joinScript and data.joinScript.UdmuxEndpoints and #data.joinScript.UdmuxEndpoints > 0 then
        return data.joinScript.UdmuxEndpoints[1].Address
    end
    return nil
end

local function isUSAServer(ipAddress)
    local usaPrefixes = {
        "104.", "128.116.", "162.", "199.", "66.", "72.", "192.",
    }
    for _, prefix in ipairs(usaPrefixes) do
        if ipAddress:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function getServerRegion(placeId, serverId)
    local cache = getgenv().ServerRegionCache
    if cache[serverId] then
        return cache[serverId]
    end
    local ip = getServerIP(placeId, serverId)
    if not ip then
        cache[serverId] = "unknown"
        return "unknown"
    end
    local region = isUSAServer(ip) and "US" or "other"
    cache[serverId] = region
    return region
end

local function getCandidateServers(placeId, currentJobId)
    local allServers = {}
    local cursor = nil
    local visited = getgenv().VisitedServers

    repeat
        local ok, result = pcall(function()
            return game:GetService("HttpService"):JSONDecode(
                request({
                    Url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100" .. (cursor and ("&cursor=" .. cursor) or ""),
                    Method = "GET"
                }).Body
            )
        end)
        if not ok or not result or not result.data then
            break
        end
        for _, server in ipairs(result.data) do
            local isCurrent = server.id == currentJobId
            local isVisited = visited[server.id] == true
            local playing = server.playing or 0
            local maxPlayers = server.maxPlayers or 0
            local hasSpace = playing < maxPlayers
            local underLimit = playing <= MAX_PLAYERS
            if not isCurrent and not isVisited and hasSpace and underLimit then
                table.insert(allServers, server)
            end
        end
        if #allServers > 0 then break end
        cursor = result.nextPageCursor
    until not cursor

    return allServers
end

local function selectTargetServer(placeId, currentJobId)
    local allServers = getCandidateServers(placeId, currentJobId)
    if #allServers == 0 then
        return nil
    end

    table.sort(allServers, function(a, b) return (a.playing or 0) < (b.playing or 0) end)

    local nonUSAServers = {}
    for _, server in ipairs(allServers) do
        local region = getServerRegion(placeId, server.id)
        if region ~= "US" then
            table.insert(nonUSAServers, server)
        end
        task.wait(0.1)
    end

    if #nonUSAServers == 0 then
        nonUSAServers = allServers
    end

    return nonUSAServers[1]
end

function ServerHop.hopToNewServer(player)
    local placeId = game.PlaceId
    local currentJobId = game.JobId
    getgenv().VisitedServers[currentJobId] = true

    local target = selectTargetServer(placeId, currentJobId)
    if not target then
        warn("No suitable server found. Clearing visited list and using random teleport.")
        getgenv().VisitedServers = {}
        pcall(function()
            game:GetService("TeleportService"):Teleport(placeId, player)
        end)
        return
    end

    local TeleportService = game:GetService("TeleportService")
    pcall(function() clear_teleport_queue() end)
    pcall(function() queue_on_teleport(getgenv()._ServerHopSource) end)

    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, target.id, player)
    end)

    if not success then
        warn("Teleport failed: " .. tostring(err) .. ". Retrying in 2 seconds.")
        task.wait(2)
        ServerHop.hopToNewServer(player) -- recursive retry
    end
end

function ServerHop.hasS5nniPlayer()
    for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
        if plr.Name:lower():find("s5nni") then
            return true
        end
    end
    return false
end

return ServerHop
