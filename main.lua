loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/webhook.lua"))()
loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/whitelist.lua"))()
loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/robberies.lua"))()

if not getgenv().VisitedServers then
    getgenv().VisitedServers = {}
end

if getgenv().WhitelistCheck and not getgenv().WhitelistCheck() then
    warn("You are not whitelisted to use this script.")
    return
end

local AIRDROP_LOCATION_RADIUS = 500

local AIRDROP_COLORS = {
    { r = 147, g = 44,  b = 53,  label = "🔴 Red",   embedColor = 15158332 },
    { r = 148, g = 96,  b = 69,  label = "🟤 Brown",  embedColor = 10180422 },
    { r = 49,  g = 98,  b = 149, label = "🔵 Blue",   embedColor = 3447003  },
}

local AIRDROP_LOCATIONS = {
    {
        name = "Dunes",
        getPosition = function()
            local tomb = workspace:FindFirstChild("RobberyTomb")
            if tomb then
                local inner = tomb:FindFirstChild("Tomb")
                if inner and inner:IsA("Model") then
                    return inner:GetModelCFrame().Position
                elseif inner and inner:FindFirstChildWhichIsA("BasePart") then
                    return inner:FindFirstChildWhichIsA("BasePart").Position
                end
            end
            return nil
        end
    },
    {
        name = "Cactus Valley",
        getPosition = function()
            local casino = workspace:FindFirstChild("Casino")
            if casino then
                if casino:IsA("Model") then
                    return casino:GetModelCFrame().Position
                elseif casino:FindFirstChildWhichIsA("BasePart") then
                    return casino:FindFirstChildWhichIsA("BasePart").Position
                end
            end
            return nil
        end
    },
}

local MAX_PLAYERS = 7

local LogLevel = {
    INFO    = { label = "ℹ️ Info",       color = 5793266  },
    SUCCESS = { label = "✅ Success",    color = 3066993  },
    WARNING = { label = "⚠️ Warning",    color = 16776960 },
    ERROR   = { label = "❌ Error",      color = 15158332 },
    HOP     = { label = "🔀 Server Hop", color = 10181046 },
}

-- =============================================
--           JOIN LINK BUILDER
-- =============================================

local _cachedJoinLink = nil
local function getJoinLink(jobId)
    local placeId = game.PlaceId
    if not _cachedJoinLink then
        local ok, info = pcall(function()
            return game:GetService("MarketplaceService"):GetProductInfo(placeId)
        end)
        local placeName = (ok and info and info.Name) and info.Name or "Game"
        local slug = placeName:gsub("[^%w%s%-]", ""):gsub("%s+", "-")
        _cachedJoinLink = "https://www.roblox.com/games/" .. placeId .. "/" .. slug
    end
    return _cachedJoinLink .. "?serverJobId=" .. jobId
end

-- =============================================
--              LOGGING SYSTEM
-- =============================================

local function sendLog(level, title, description, fields)
    local webhook = getgenv().WebhookConfig.Webhooks.Log
    if not webhook or webhook == "" then return end

    local player = game:GetService("Players").LocalPlayer
    local username = player and player.Name or "Unknown"
    local jobId = game.JobId or "N/A"

    local embedFields = {
        { name = "👤 Account",   value = username, inline = true },
        { name = "🌐 Server ID", value = jobId,    inline = true },
    }

    if fields then
        for _, f in ipairs(fields) do
            table.insert(embedFields, f)
        end
    end

    local embedPayload = {
        embeds = {
            {
                title       = level.label .. "  |  " .. title,
                description = description or "",
                color       = level.color,
                fields      = embedFields,
                footer      = { text = "ServerHop Bot" },
                timestamp   = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            }
        }
    }

    local ok, encoded = pcall(function()
        return game:GetService("HttpService"):JSONEncode(embedPayload)
    end)
    if not ok then return end

    pcall(function()
        request({ Url = webhook, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = encoded })
    end)
end

-- =============================================

local function waitForLoad()
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    if not player then
        Players.PlayerAdded:Wait()
        player = Players.LocalPlayer
    end
    if not player.Character then
        player.CharacterAdded:Wait()
    end
    repeat task.wait(0.5) until game:IsLoaded()
    task.wait(2)
    return player
end

local function formatName(name)
    return name:gsub("_", " ")
end

local function getTeamCounts()
    local counts = { Criminal = 0, Police = 0, Prisoner = 0 }
    for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
        if player.Team then
            local teamName = player.Team.Name
            if counts[teamName] ~= nil then
                counts[teamName] = counts[teamName] + 1
            end
        end
    end
    return counts
end

local function colorDistance(r1, g1, b1, r2, g2, b2)
    return math.sqrt((r1 - r2)^2 + (g1 - g2)^2 + (b1 - b2)^2)
end

local function matchAirdropColor(r, g, b)
    local best = nil
    local bestDist = math.huge
    for _, def in ipairs(AIRDROP_COLORS) do
        local dist = colorDistance(r, g, b, def.r, def.g, def.b)
        if dist < bestDist then
            bestDist = dist
            best = def
        end
    end
    if bestDist <= 20 then return best end
    return nil
end

local function getDropPosition(drop)
    local ok, cf = pcall(function() return drop:GetModelCFrame() end)
    if ok and cf then return cf.Position end
    local part = drop:FindFirstChildWhichIsA("BasePart", true)
    if part then return part.Position end
    return nil
end

local function getNearestLocation(pos)
    local best = nil
    local bestDist = math.huge
    for _, loc in ipairs(AIRDROP_LOCATIONS) do
        local refPos = loc.getPosition()
        if refPos then
            local dist = (pos - refPos).Magnitude
            if dist < bestDist then
                bestDist = dist
                best = { name = loc.name, distance = dist }
            end
        end
    end
    if best and best.distance <= AIRDROP_LOCATION_RADIUS then
        return best.name
    end
    return "Unknown Location"
end

local function sendDiscordEmbed(webhookUrl, storeName, status, jobId)
    local joinLink = getJoinLink(jobId)
    local teamCounts = getTeamCounts()
    local criminals = teamCounts.Criminal
    local police = teamCounts.Police
    local prisoners = teamCounts.Prisoner
    local crimAndPris = criminals + prisoners
    local totalPlayers = crimAndPris + police
    local isOpen = status == "open"
    local color = isOpen and 3066993 or 15105570
    local statusText = isOpen and "Open" or "Under Robbery"
    local title = isOpen and storeName .. " is Open!" or storeName .. " is Under Robbery!"
    local embedPayload = {
        embeds = {
            {
                title = title,
                color = color,
                fields = {
                    { name = "📍 Status",      value = statusText,          inline = true  },
                    { name = "👥 Total Players", value = tostring(totalPlayers), inline = true  },
                    { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
                    { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
                    { name = "🚔 Police",       value = tostring(police),    inline = true  },
                },
                footer = { text = "Server ID: " .. jobId },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }
        }
    }
    local ok, encoded = pcall(function()
        return game:GetService("HttpService"):JSONEncode(embedPayload)
    end)
    if not ok then return end
    pcall(function()
        request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = encoded })
    end)
end

local function sendAirdropEmbed(webhookUrl, drop, colorDef, locationName, jobId)
    local joinLink = getJoinLink(jobId)
    local teamCounts = getTeamCounts()
    local criminals = teamCounts.Criminal
    local police = teamCounts.Police
    local prisoners = teamCounts.Prisoner
    local crimAndPris = criminals + prisoners
    local totalPlayers = crimAndPris + police
    local embedPayload = {
        embeds = {
            {
                title = "📦 Airdrop Detected!",
                color = colorDef.embedColor,
                fields = {
                    { name = "🎨 Drop Type",             value = colorDef.label,   inline = true  },
                    { name = "📍 Location",              value = locationName,     inline = true  },
                    { name = "👥 Total Players",         value = tostring(totalPlayers), inline = true },
                    { name = "🔗 Join Server",           value = "[Click to Join](" .. joinLink .. ")", inline = false },
                    { name = "🦹 Criminals", value = tostring(crimAndPris), inline = false },
                    { name = "🚔 Police",                value = tostring(police), inline = true  },
                },
                footer = { text = "Server ID: " .. jobId },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }
        }
    }
    local ok, encoded = pcall(function()
        return game:GetService("HttpService"):JSONEncode(embedPayload)
    end)
    if not ok then return end
    pcall(function()
        request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = encoded })
    end)
end

local function checkAirdrops(jobId)
    local webhook = getgenv().WebhookConfig.Webhooks.Airdrop
    if not webhook or webhook == "" then
        sendLog(LogLevel.WARNING, "Airdrop Webhook Missing", "Airdrop webhook URL has not been configured.")
        return
    end

    -- Respect toggle
    if getgenv().RobberyToggles and not getgenv().RobberyToggles.Airdrop then
        sendLog(LogLevel.INFO, "Airdrop — Toggled Off", "Airdrop logging is disabled via robberies.lua.")
        return
    end

    local dropsFound = 0
    local dropsLogged = 0

    for _, drop in ipairs(workspace:GetChildren()) do
        if drop.Name == "Drop" and drop:IsA("Model") then
            dropsFound = dropsFound + 1

            local walls = drop:FindFirstChild("Walls")
            if not walls then
                sendLog(LogLevel.WARNING, "Airdrop — No Walls", "A Drop model has no 'Walls' child.", {
                    { name = "Drop", value = drop:GetFullName(), inline = true }
                })
                continue
            end

            local wall = walls:FindFirstChild("Wall")
            if not wall or not wall:IsA("BasePart") then
                sendLog(LogLevel.WARNING, "Airdrop — No Wall Part", "Walls folder has no valid 'Wall' BasePart.", {
                    { name = "Drop", value = drop:GetFullName(), inline = true }
                })
                continue
            end

            local col = wall.Color
            local r = math.round(col.R * 255)
            local g = math.round(col.G * 255)
            local b = math.round(col.B * 255)

            local colorDef = matchAirdropColor(r, g, b)
            if not colorDef then
                sendLog(LogLevel.WARNING, "Airdrop — Unknown Color", "Could not match drop color to any known type.", {
                    { name = "RGB",  value = r .. ", " .. g .. ", " .. b, inline = true },
                    { name = "Drop", value = drop:GetFullName(),          inline = true },
                })
                continue
            end

            local dropPos = getDropPosition(drop)
            if not dropPos then
                sendLog(LogLevel.WARNING, "Airdrop — No Position", "Could not determine drop world position.", {
                    { name = "Drop", value = drop:GetFullName(), inline = true }
                })
                continue
            end

            local locationName = getNearestLocation(dropPos)

            sendAirdropEmbed(webhook, drop, colorDef, locationName, jobId)
            dropsLogged = dropsLogged + 1

            sendLog(LogLevel.SUCCESS, "Airdrop Logged", "Successfully logged an airdrop.", {
                { name = "🎨 Type",     value = colorDef.label, inline = true },
                { name = "📍 Location", value = locationName,   inline = true },
            })
        end
    end

    if dropsFound == 0 then
        sendLog(LogLevel.INFO, "Airdrop Scan Complete", "No active Drop models found in workspace.")
    else
        sendLog(LogLevel.INFO, "Airdrop Scan Complete", "Finished scanning for airdrops.", {
            { name = "Found",  value = tostring(dropsFound),  inline = true },
            { name = "Logged", value = tostring(dropsLogged), inline = true },
        })
    end
end

local function checkForOpenStores(player)
    local playerGui = player and player:FindFirstChild("PlayerGui")
    if not playerGui then
        sendLog(LogLevel.ERROR, "Store Scan Failed", "PlayerGui not found on player.")
        return
    end

    local worldMarkers = playerGui:FindFirstChild("WorldMarkersGui")
    if not worldMarkers then
        sendLog(LogLevel.ERROR, "Store Scan Failed", "WorldMarkersGui not found in PlayerGui.")
        return
    end

    local jobId = game.JobId
    local openCount = 0
    local robberyCount = 0
    local closedCount = 0
    local missedCount = 0
    local skippedCount = 0

    sendLog(LogLevel.INFO, "Store Scan Started", "Beginning robbery/store status scan.")

    for storeName, iconAssetId in pairs(getgenv().WebhookConfig.Icons) do
        local displayName = formatName(storeName)
        local found = false

        for _, imageLabel in ipairs(worldMarkers:GetDescendants()) do
            if imageLabel:IsA("ImageLabel") and imageLabel.Image == iconAssetId then
                found = true
                local parent = imageLabel.Parent
                if parent and parent:IsA("ImageLabel") then
                    local col = parent.ImageColor3
                    local r = math.round(col.R * 255)
                    local g = math.round(col.G * 255)
                    local b = math.round(col.B * 255)
                    local webhook = getgenv().WebhookConfig.Webhooks[storeName]

                    if r == 0 and g == 255 and b == 0 then
                        openCount = openCount + 1
                        if webhook and webhook ~= "" then
                            if getgenv().RobberyToggles and getgenv().RobberyToggles[storeName] then
                                sendDiscordEmbed(webhook, displayName, "open", jobId)
                                sendLog(LogLevel.SUCCESS, "Store Open", displayName .. " is open — embed sent.", {
                                    { name = "Store", value = displayName, inline = true }
                                })
                            else
                                skippedCount = skippedCount + 1
                                sendLog(LogLevel.INFO, "Store Open — Toggled Off", displayName .. " is open but logging is disabled.", {
                                    { name = "Store", value = displayName, inline = true }
                                })
                            end
                        else
                            sendLog(LogLevel.WARNING, "Store Open — No Webhook", displayName .. " is open but has no webhook configured.", {
                                { name = "Store", value = displayName, inline = true }
                            })
                        end
                    elseif r == 255 and g == 0 and b == 0 then
                        closedCount = closedCount + 1
                    else
                        robberyCount = robberyCount + 1
                        if webhook and webhook ~= "" then
                            if getgenv().RobberyToggles and getgenv().RobberyToggles[storeName] then
                                sendDiscordEmbed(webhook, displayName, "robbery", jobId)
                                sendLog(LogLevel.SUCCESS, "Robbery Logged", displayName .. " is under robbery — embed sent.", {
                                    { name = "Store", value = displayName, inline = true }
                                })
                            else
                                skippedCount = skippedCount + 1
                                sendLog(LogLevel.INFO, "Robbery — Toggled Off", displayName .. " is under robbery but logging is disabled.", {
                                    { name = "Store", value = displayName, inline = true }
                                })
                            end
                        else
                            sendLog(LogLevel.WARNING, "Robbery — No Webhook", displayName .. " is under robbery but has no webhook.", {
                                { name = "Store", value = displayName, inline = true }
                            })
                        end
                    end
                else
                    missedCount = missedCount + 1
                    sendLog(LogLevel.WARNING, "Store — Unexpected Parent", "Icon parent was not an ImageLabel for " .. displayName .. ".", {
                        { name = "Store", value = displayName, inline = true }
                    })
                end
                break
            end
        end

        if not found then
            missedCount = missedCount + 1
            sendLog(LogLevel.WARNING, "Store Icon Missing", "Could not find icon in WorldMarkersGui for " .. displayName .. ".", {
                { name = "Store", value = displayName, inline = true }
            })
        end
    end

    sendLog(LogLevel.INFO, "Store Scan Complete", "Finished scanning all stores.", {
        { name = "✅ Open",    value = tostring(openCount),    inline = true },
        { name = "🔴 Robbery", value = tostring(robberyCount), inline = true },
        { name = "⚫ Closed",  value = tostring(closedCount),  inline = true },
        { name = "⚠️ Missed",  value = tostring(missedCount),  inline = true },
        { name = "⏭️ Skipped", value = tostring(skippedCount), inline = true },
    })
end

local function getTargetServer(placeId, currentJobId)
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
            sendLog(LogLevel.ERROR, "Server List Fetch Failed", "Failed to retrieve server list from Roblox API.")
            break
        end
        for _, server in ipairs(result.data) do
            local isCurrentServer = server.id == currentJobId
            local isVisited = visited[server.id] == true
            local playing = server.playing or 0
            local maxPlayers = server.maxPlayers or 0
            local hasSpace = playing < maxPlayers
            local underLimit = playing <= MAX_PLAYERS
            if not isCurrentServer and not isVisited and hasSpace and underLimit then
                table.insert(allServers, server)
            end
        end
        if #allServers > 0 then break end
        cursor = result.nextPageCursor
    until not cursor

    if #allServers == 0 then
        sendLog(LogLevel.WARNING, "No Valid Servers", "No servers found under player limit. Clearing visited list and retrying.")
        getgenv().VisitedServers = {}
        return nil
    end

    table.sort(allServers, function(a, b) return (a.playing or 0) < (b.playing or 0) end)
    local best = allServers[1]
    sendLog(LogLevel.HOP, "Target Server Found", "Identified best server to hop to.", {
        { name = "Target ID", value = best.id, inline = false },
        { name = "Players",   value = tostring(best.playing) .. "/" .. tostring(best.maxPlayers), inline = true },
    })
    return best.id
end

local function hopToNewServer(player)
    local placeId = game.PlaceId
    local currentJobId = game.JobId
    getgenv().VisitedServers[currentJobId] = true

    local targetJobId = getTargetServer(placeId, currentJobId)
    local TeleportService = game:GetService("TeleportService")

    pcall(function() clear_teleport_queue() end)
    pcall(function() queue_on_teleport(getgenv()._ServerHopSource) end)

    if targetJobId then
        sendLog(LogLevel.HOP, "Teleporting", "Attempting teleport to target server.", {
            { name = "Target", value = targetJobId, inline = false }
        })
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(placeId, targetJobId, player)
        end)
        if not ok then
            sendLog(LogLevel.ERROR, "Teleport Failed", "TeleportToPlaceInstance failed. Falling back to random server.", {
                { name = "Error", value = tostring(err), inline = false }
            })
            pcall(function() TeleportService:Teleport(placeId, player) end)
        end
    else
        sendLog(LogLevel.WARNING, "No Target Server", "No valid server found. Falling back to random server teleport.")
        pcall(function() TeleportService:Teleport(placeId, player) end)
    end
end

if not getgenv()._ServerHopSource then
    getgenv()._ServerHopSource = [[loadstring(game:HttpGet("raw code here"))()]] -- replace with your hop script if needed
end

-- =============================================
--              MAIN EXECUTION
-- =============================================
pcall(function()
    local player = waitForLoad()
    local currentJobId = game.JobId

    sendLog(LogLevel.INFO, "Bot Started", "Script loaded and game is ready.", {
        { name = "Server ID", value = currentJobId, inline = false }
    })

    if getgenv().ServerId == currentJobId then
        sendLog(LogLevel.WARNING, "Duplicate Server Detected", "Current server matches stored ServerId. Skipping scan and hopping immediately.", {
            { name = "Server ID", value = currentJobId, inline = false }
        })
        hopToNewServer(player)
        return
    end

    getgenv().ServerId = currentJobId

    checkForOpenStores(player)
    checkAirdrops(currentJobId)

    getgenv().IsFinished = true
    sendLog(LogLevel.SUCCESS, "Cycle Complete", "All scans finished. IsFinished set. Hopping in 2 seconds.")
    task.wait(2)

    hopToNewServer(player)
end)
