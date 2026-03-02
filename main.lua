loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/webhook.lua"))()
loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/whitelist.lua"))()
loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/robberies.lua"))()

if not getgenv().VisitedServers then
    getgenv().VisitedServers = {}
end

-- Cache for server regions
if not getgenv().ServerRegionCache then
    getgenv().ServerRegionCache = {}
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

local MAX_PLAYERS = 5

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
    if bestDist <= 30 then return best end
    return nil
end

local function getDropPosition(drop)
    local ok, pivot = pcall(function() return drop:GetPivot() end)
    if ok and pivot then return pivot.Position end
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

-- =============================================
--          CROWN JEWEL CODE READER
-- =============================================

local POSITION_THRESHOLD = 5
local knownLocations = {
    {
        cframe = CFrame.new(-177.696777, 20.1733818, -4682.39795, 0.275480151, -0, -0.96130687, 0, 1, -0, 0.96130687, 0, 0.275480151),
        axis = "Z"
    },
    {
        cframe = CFrame.new(-177.696777, 20.1733818, -4682.39795, 0.275480151, -0, -0.96130687, 0, 1, -0, 0.96130687, 0, 0.275480151),
        axis = "Z"
    },
    {
        cframe = CFrame.new(-307.341309, 21.9233818, -4950.76709, -0.961297989, 0, -0.275510818, 0, 1, 0, 0.275510818, 0, -0.961297989),
        axis = "X"
    },
    {
        cframe = CFrame.new(205.143555, 20.1733818, -4240.87305, 0.961297989, 0, 0.275510818, 0, 1, 0, -0.275510818, 0, 0.961297989),
        axis = "Y"
    },
    {
        cframe = CFrame.new(381.288574, 20.1733818, -4885.12646, -0.275480509, 0, 0.96130687, 0, 1, 0, -0.96130687, 0, -0.275480509),
        axis = "Z"
    },
}

local function getAxisForHolder(holderModel)
    local pivot = holderModel:GetPivot()
    local pos = pivot.Position
    for _, loc in ipairs(knownLocations) do
        local locPos = loc.cframe.Position
        if (pos - locPos).Magnitude <= POSITION_THRESHOLD then
            return loc.axis
        end
    end
    return nil
end

local function getCrownJewelCode()
    -- Safety checks
    local casino = workspace:FindFirstChild("Casino")
    if not casino then
        sendLog(LogLevel.WARNING, "Crown Jewel Code", "Casino not found in workspace.")
        return nil
    end
    local robberyDoor = casino:FindFirstChild("RobberyDoor")
    if not robberyDoor then
        sendLog(LogLevel.WARNING, "Crown Jewel Code", "RobberyDoor not found in Casino.")
        return nil
    end
    local codesFolder = robberyDoor:FindFirstChild("Codes")
    if not codesFolder then
        sendLog(LogLevel.WARNING, "Crown Jewel Code", "Codes folder not found in RobberyDoor.")
        return nil
    end

    local digits = {}
    local detectedAxis = nil

    for _, v in ipairs(codesFolder:GetDescendants()) do
        if v:IsA("TextLabel") and v.Text ~= "" then
            local part = v.Parent.Parent         -- SurfaceGui -> Part
            local holder = v.Parent.Parent.Parent -- Part -> Codes Holder Model

            if part:IsA("BasePart") then
                if detectedAxis == nil then
                    detectedAxis = getAxisForHolder(holder)
                end
                table.insert(digits, {
                    text = v.Text,
                    part = part,
                })
            end
        end
    end

    if #digits == 0 then
        return nil  -- robbery closed or no digits
    end

    if detectedAxis == nil then
        sendLog(LogLevel.WARNING, "Crown Jewel Code", "Could not match holder to known location, defaulting to X axis.")
        detectedAxis = "X"
    end

    -- Sort digits based on axis
    table.sort(digits, function(a, b)
        if detectedAxis == "X" then
            return a.part.Position.X < b.part.Position.X
        elseif detectedAxis == "Z" then
            return a.part.Position.Z < b.part.Position.Z
        elseif detectedAxis == "Y" then
            return a.part.Position.Y < b.part.Position.Y
        end
    end)

    local fullCode = ""
    for _, data in ipairs(digits) do
        fullCode = fullCode .. data.text
    end
    return fullCode
end

-- =============================================
--          DISCORD EMBED FUNCTIONS
-- =============================================

local function sendDiscordEmbed(webhookUrl, storeName, status, jobId)
    local now = os.time()
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

    local roleId = getgenv().WebhookConfig.Roles[storeName]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil

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
                    { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
                },
                footer = { text = "Server ID: " .. jobId },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }
        }
    }

    if roleMention then
        embedPayload.content = roleMention
    end

    local ok, encoded = pcall(function()
        return game:GetService("HttpService"):JSONEncode(embedPayload)
    end)
    if not ok then return end
    pcall(function()
        request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = encoded })
    end)
end

local function sendAirdropEmbed(webhookUrl, drop, colorDef, locationName, jobId)
    local now = os.time()
    local joinLink = getJoinLink(jobId)
    local teamCounts = getTeamCounts()
    local criminals = teamCounts.Criminal
    local police = teamCounts.Police
    local prisoners = teamCounts.Prisoner
    local crimAndPris = criminals + prisoners
    local totalPlayers = crimAndPris + police

    local roleKey = colorDef.label:match("🔴") and "RedAirdrop" or
                    colorDef.label:match("🟤") and "BrownAirdrop" or
                    colorDef.label:match("🔵") and "BlueAirdrop" or nil
    local roleId = roleKey and getgenv().WebhookConfig.Roles[roleKey]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil

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
                    { name = "🦹 Criminals",             value = tostring(crimAndPris), inline = false },
                    { name = "🚔 Police",                value = tostring(police), inline = true  },
                    { name = "⏱️ Logged",                value = "<t:" .. now .. ":R>", inline = true },
                },
                footer = { text = "Server ID: " .. jobId },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }
        }
    }

    if roleMention then
        embedPayload.content = roleMention
    end

    local ok, encoded = pcall(function()
        return game:GetService("HttpService"):JSONEncode(embedPayload)
    end)
    if not ok then return end
    pcall(function()
        request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = encoded })
    end)
end

-- =============================================
--          MANSION TIME HELPER
-- =============================================

local function getGameTimeText()
    local success, label = pcall(function()
        return game:GetService("Players").LocalPlayer
                .PlayerGui.AppUI.Buttons.Minimap.Time.Time
    end)
    if success and label and label:IsA("TextLabel") then
        return label.Text
    end
    return nil
end

local function parseGameTime(timeStr)
    local hour, minute, period = timeStr:match("(%d+):(%d+)%s*(%a+)")
    if not hour then return nil end
    hour = tonumber(hour)
    minute = tonumber(minute)
    period = period:upper()
    if period == "PM" and hour ~= 12 then
        hour = hour + 12
    elseif period == "AM" and hour == 12 then
        hour = 0
    end
    return hour, minute, period
end

-- =============================================
--          REGION FILTERING FUNCTIONS
-- =============================================

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

-- =============================================
--          AIRDROP SCAN
-- =============================================

local function checkAirdrops(jobId)
    local webhook = getgenv().WebhookConfig.Webhooks.Airdrop
    if not webhook or webhook == "" then
        sendLog(LogLevel.WARNING, "Airdrop Webhook Missing", "Airdrop webhook URL has not been configured.")
        return
    end
    if getgenv().RobberyToggles and not getgenv().RobberyToggles.Airdrop then
        return
    end

    local dropsFound = 0
    local dropsLogged = 0
    local candidates = {}

    for _, drop in ipairs(workspace:GetChildren()) do
        if drop.Name == "Drop" and drop:IsA("Model") then
            table.insert(candidates, drop)
        end
    end

    if #candidates == 0 then
        sendLog(LogLevel.WARNING, "Airdrop Scan", "No models named 'Drop' found in workspace.")
    end

    for _, drop in ipairs(candidates) do
        dropsFound = dropsFound + 1
        sendLog(LogLevel.INFO, "Airdrop Candidate", "Found drop model: " .. drop:GetFullName())

        local wallPart = nil
        local wallsFolder = drop:FindFirstChild("Walls") or drop:FindFirstChild("walls")
        if wallsFolder then
            wallPart = wallsFolder:FindFirstChildWhichIsA("BasePart", true)
            if wallPart then
                sendLog(LogLevel.INFO, "Wall Found", "Found wall part inside Walls folder: " .. wallPart.Name)
            end
        end
        if not wallPart then
            for _, child in ipairs(drop:GetChildren()) do
                if child:IsA("BasePart") and child.Name:lower() == "wall" then
                    wallPart = child
                    sendLog(LogLevel.INFO, "Wall Found", "Found direct wall part: " .. child.Name)
                    break
                end
            end
        end
        if not wallPart then
            local parts = {}
            for _, desc in ipairs(drop:GetDescendants()) do
                if desc:IsA("BasePart") then
                    table.insert(parts, desc)
                end
            end
            if #parts == 1 then
                wallPart = parts[1]
                sendLog(LogLevel.INFO, "Wall Found", "Only one BasePart in model, assuming it's the wall: " .. wallPart.Name)
            elseif #parts > 1 then
                local partNames = {}
                for _, p in ipairs(parts) do
                    table.insert(partNames, p.Name)
                end
                sendLog(LogLevel.WARNING, "Airdrop — Multiple Parts", "Drop has multiple BaseParts, cannot determine wall.", {
                    { name = "Parts", value = table.concat(partNames, ", "), inline = false }
                })
                continue
            else
                sendLog(LogLevel.WARNING, "Airdrop — No BaseParts", "Drop model contains no BasePart descendants.")
                continue
            end
        end

        if not wallPart then
            sendLog(LogLevel.WARNING, "Airdrop — No Wall Part", "Could not identify any wall part in drop model.")
            continue
        end

        local col = wallPart.Color
        local r = math.round(col.R * 255)
        local g = math.round(col.G * 255)
        local b = math.round(col.B * 255)

        local colorDef = matchAirdropColor(r, g, b)
        if not colorDef then
            sendLog(LogLevel.WARNING, "Airdrop — Unknown Color", "Could not match drop color.", {
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
            { name = "RGB",         value = r..","..g..","..b, inline = true },
        })
    end

    if dropsFound == 0 then
        sendLog(LogLevel.WARNING, "Airdrop Scan", "No drop models found. Workspace structure may have changed.")
    else
        sendLog(LogLevel.INFO, "Airdrop Scan Complete", "Finished scanning for airdrops.", {
            { name = "Found",  value = tostring(dropsFound),  inline = true },
            { name = "Logged", value = tostring(dropsLogged), inline = true },
        })
    end
end

-- =============================================
--          STORE SCAN (WITH MANSION & CROWN JEWEL)
-- =============================================

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

                    local isOpen = (r == 0 and g == 255 and b == 0)
                    local isClosed = (r == 255 and g == 0 and b == 0)
                    local isRobbery = not isOpen and not isClosed

                    if isOpen then
                        openCount = openCount + 1
                    elseif isClosed then
                        closedCount = closedCount + 1
                    else
                        robberyCount = robberyCount + 1
                    end

                    -- =========================================
                    --          CROWN JEWEL (with code)
                    -- =========================================
                    if storeName == "Crown_Jewel" then
                        -- Skip if logging is toggled off
                        if getgenv().RobberyToggles and not getgenv().RobberyToggles[storeName] then
                            skippedCount = skippedCount + 1
                            break
                        end

                        -- Only log if open or under robbery
                        if not (isOpen or isRobbery) then
                            break
                        end

                        -- Get the robbery code
                        local code = getCrownJewelCode()
                        if not code then
                            code = "N/A"
                        end

                        local now = os.time()
                        local joinLink = getJoinLink(jobId)
                        local teamCounts = getTeamCounts()
                        local criminals = teamCounts.Criminal
                        local police = teamCounts.Police
                        local prisoners = teamCounts.Prisoner
                        local crimAndPris = criminals + prisoners
                        local totalPlayers = crimAndPris + police
                        local statusText = isOpen and "Open" or "Under Robbery"
                        local title = isOpen and "Crown Jewel is Open!" or "Crown Jewel is Under Robbery!"

                        local roleId = getgenv().WebhookConfig.Roles["Crown_Jewel"]
                        local roleMention = roleId and ("<@&" .. roleId .. ">") or nil

                        local embedPayload = {
                            embeds = {
                                {
                                    title = title,
                                    color = isOpen and 3066993 or 15105570,
                                    fields = {
                                        { name = "📍 Status",      value = statusText,          inline = true  },
                                        { name = "👥 Total Players", value = tostring(totalPlayers), inline = true  },
                                        { name = "🔢 Code",        value = code,                 inline = true  },
                                        { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
                                        { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
                                        { name = "🚔 Police",       value = tostring(police),    inline = true  },
                                        { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
                                    },
                                    footer = { text = "Server ID: " .. jobId },
                                    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                                }
                            }
                        }

                        if roleMention then
                            embedPayload.content = roleMention
                        end

                        local ok, encoded = pcall(function()
                            return game:GetService("HttpService"):JSONEncode(embedPayload)
                        end)
                        if ok then
                            pcall(function()
                                request({ Url = webhook, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = encoded })
                            end)
                            sendLog(LogLevel.SUCCESS, "Crown Jewel Logged", displayName .. " " .. statusText .. " — Code: " .. code, {
                                { name = "Code", value = code, inline = true }
                            })
                        end

                    -- =========================================
                    --          MANSION (with time predictor)
                    -- =========================================
                    elseif storeName == "Mansion" then
                        if getgenv().RobberyToggles and not getgenv().RobberyToggles.Mansion then
                            skippedCount = skippedCount + 1
                            break
                        end
                        if not isOpen then
                            break
                        end
                        local timeText = getGameTimeText()
                        if not timeText then
                            sendLog(LogLevel.WARNING, "Mansion Time Missing", "Could not read game time; mansion log skipped.")
                            break
                        end
                        local hour, minute, period = parseGameTime(timeText)
                        if not hour then
                            sendLog(LogLevel.WARNING, "Mansion Time Parse Failed", "Failed to parse time: " .. timeText)
                            break
                        end
                        if period == "AM" and hour >= 3 then
                            sendLog(LogLevel.INFO, "Mansion Skipped", "Time is " .. timeText .. " – mansion not logged.")
                            skippedCount = skippedCount + 1
                            break
                        end
                        local timeStatus
                        local timeColor
                        if hour >= 18 then
                            timeStatus = "Open"
                            timeColor = 3066993
                        elseif hour >= 16 then
                            timeStatus = "Ready to Open"
                            timeColor = 16753920
                        elseif hour == 0 then
                            timeStatus = "Closing Soon"
                            timeColor = 15158332
                        elseif hour < 3 and period == "AM" then
                            timeStatus = "Closing Soon"
                            timeColor = 15158332
                        else
                            timeStatus = "Unknown"
                            timeColor = 5793266
                        end

                        local roleId = getgenv().WebhookConfig.Roles["Mansion"]
                        local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
                        local now = os.time()
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
                                    title = "🏰 Mansion is Open (" .. timeStatus .. ")",
                                    color = timeColor,
                                    fields = {
                                        { name = "⏰ Game Time",   value = timeText,                     inline = true },
                                        { name = "📍 Status",      value = "Open",                       inline = true },
                                        { name = "👥 Total Players", value = tostring(totalPlayers),       inline = true },
                                        { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
                                        { name = "🏃 Criminals",    value = tostring(crimAndPris),        inline = true },
                                        { name = "🚔 Police",       value = tostring(police),             inline = true },
                                        { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>",        inline = true },
                                    },
                                    footer = { text = "Server ID: " .. jobId },
                                    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                                }
                            }
                        }
                        if roleMention then
                            embedPayload.content = roleMention
                        end
                        local ok, encoded = pcall(function()
                            return game:GetService("HttpService"):JSONEncode(embedPayload)
                        end)
                        if ok then
                            pcall(function()
                                request({ Url = webhook, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = encoded })
                            end)
                            sendLog(LogLevel.SUCCESS, "Mansion Logged", "Mansion Open at " .. timeText, {
                                { name = "Time Status", value = timeStatus, inline = true }
                            })
                        end

                    -- =========================================
                    --          ALL OTHER STORES
                    -- =========================================
                    else
                        if isOpen then
                            if webhook and webhook ~= "" then
                                if getgenv().RobberyToggles and getgenv().RobberyToggles[storeName] then
                                    sendDiscordEmbed(webhook, storeName, "open", jobId)
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
                        elseif isRobbery then
                            if webhook and webhook ~= "" then
                                if getgenv().RobberyToggles and getgenv().RobberyToggles[storeName] then
                                    sendDiscordEmbed(webhook, storeName, "robbery", jobId)
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

-- =============================================
--          SERVER HOP LOGIC (WITH REGION FILTER)
-- =============================================

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

    local nonUSAServers = {}
    for _, server in ipairs(allServers) do
        local region = getServerRegion(placeId, server.id)
        if region == "US" then
            sendLog(LogLevel.INFO, "Skipping USA Server", "Server " .. server.id .. " is in USA.")
        else
            table.insert(nonUSAServers, server)
        end
        task.wait(0.1)
    end

    if #nonUSAServers == 0 then
        sendLog(LogLevel.WARNING, "No Non‑USA Servers", "All candidate servers are in USA. Falling back to any server.")
        nonUSAServers = allServers
    end

    local best = nonUSAServers[1]
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
    getgenv()._ServerHopSource = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/main.lua"))()]]
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
