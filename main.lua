-- =============================================
-- LEAF ROBLOX ROBBERY LOGGER
-- Author: s5nni
-- Version: Loaded from version.lua
-- =============================================

loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/webhook.lua"))()
loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/whitelist.lua"))()
loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/robberies.lua"))()
local BOT_VERSION = loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/version.lua"))()

-- =============================================
-- CONFIGURATION SECTION – EDIT THESE VALUES
-- =============================================

-- Plane Waypoints (loaded externally)
local PLANE_WAYPOINTS = (function()
    local success, result = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/PlaneWaypoints.lua"))()
    end)
    if success and result then
        return result
    else
        warn("Failed to load plane waypoints. Plane detection disabled.")
        return {}
    end
end)()

-- Plane Phase Indices (set these based on your waypoint comments!)
local PLANE_INDICES = {
    SPAWN       = 21,   -- WP48 became WP21
    TURN_START  = 370,  -- original WP370
    TURN_END    = 395,  -- original WP395
    AIRPORT     = 327,  -- original WP327
}

-- Train Filtering Rules
local TRAIN_FILTERS = {
    Cargo = {
        BLOCKED_LOCATIONS = { "Gas", "Jewelry" },
        BLOCK_DISTANCE    = 700, -- block if location matches AND distance > this
    },
    Passenger = {
        BLOCKED_LOCATIONS = { "Casino", "Bank2" },
        -- Special: block Casino if distance < 500; block Bank2 always
    },
}

-- Minimum bounty to log (can be overridden by RobberyToggles.MinBounty)
local DEFAULT_MIN_BOUNTY = 5000

-- Server hop player limit
local MAX_PLAYERS = 5

-- =============================================
-- CORE CONSTANTS & HELPERS
-- =============================================

local AIRDROP_LOCATION_RADIUS = math.huge
local AIRDROP_COLORS = {
    { r = 147, g = 44,  b = 53,  label = "🔴 Red",   embedColor = 15158332 },
    { r = 148, g = 96,  b = 69,  label = "🟤 Brown",  embedColor = 10180422 },
    { r = 49,  g = 98,  b = 149, label = "🔵 Blue",   embedColor = 3447003  },
}
local CACTUS_VALLEY_CENTER = Vector3.new(945.572509765625, 32.46596145629883, -217.1789093017578)
local DUNES_CENTER = Vector3.new(962.0200805664062, 44.48336410522461, -159.24659729003906)

local LogLevel = {
    INFO    = { label = "ℹ️ Info",       color = 5793266  },
    SUCCESS = { label = "✅ Success",    color = 3066993  },
    WARNING = { label = "⚠️ Warning",    color = 16776960 },
    ERROR   = { label = "❌ Error",      color = 15158332 },
    HOP     = { label = "🔀 Server Hop", color = 10181046 },
}

-- =============================================
-- FILE SYSTEM (visited servers)
-- =============================================

local function getVisitedFilePath()
    local folder = "LeafBot_" .. game.PlaceId
    if not isfolder(folder) then makefolder(folder) end
    return folder .. "/visited_servers.json"
end

local function loadVisitedServers()
    local path = getVisitedFilePath()
    if isfile(path) then
        local success, data = pcall(function()
            return game:GetService("HttpService"):JSONDecode(readfile(path))
        end)
        if success and type(data) == "table" then return data end
    end
    return {}
end

local function saveVisitedServers(data)
    local path = getVisitedFilePath()
    local success, json = pcall(function()
        return game:GetService("HttpService"):JSONEncode(data)
    end)
    if success then writefile(path, json) end
end

local function cleanupOldServers()
    local visited = loadVisitedServers()
    local currentTime = os.time()
    local changed = false
    for serverId, timestamp in pairs(visited) do
        if currentTime - timestamp > 300 then
            visited[serverId] = nil
            changed = true
        end
    end
    if changed then saveVisitedServers(visited) end
    return visited
end

getgenv().VisitedServers = cleanupOldServers()
if not getgenv().ServerRegionCache then getgenv().ServerRegionCache = {} end

-- =============================================
-- WHITELIST CHECK
-- =============================================

if getgenv().WhitelistCheck and not getgenv().WhitelistCheck() then
    warn("Not whitelisted.")
    return
end

-- =============================================
-- UTILITY FUNCTIONS
-- =============================================

local function getJoinLink(jobId)
    local placeId = game.PlaceId
    local http = game:GetService("HttpService")
    return "https://s5nni.github.io/Leaf-Joiner/?placeId=" .. placeId .. "&jobId=" .. http:UrlEncode(jobId)
end

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
        for _, f in ipairs(fields) do table.insert(embedFields, f) end
    end

    local embedPayload = {
        embeds = {{
            title       = level.label .. "  |  " .. title,
            description = description or "",
            color       = level.color,
            fields      = embedFields,
            footer      = { text = "ServerHop Bot" },
            timestamp   = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }}
    }

    local ok, encoded = pcall(function()
        return game:GetService("HttpService"):JSONEncode(embedPayload)
    end)
    if not ok then return end

    pcall(function()
        request({ Url = webhook, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = encoded })
    end)
end

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
    repeat task.wait(0.3) until game:IsLoaded()
    task.wait(2)
    return player
end

local function formatName(name) return name:gsub("_", " ") end

local function getTeamCounts()
    local counts = { Criminal = 0, Police = 0, Prisoner = 0 }
    local localPlayer = game:GetService("Players").LocalPlayer
    for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
        if player ~= localPlayer and player.Team then
            local teamName = player.Team.Name
            if counts[teamName] ~= nil then
                counts[teamName] = counts[teamName] + 1
            end
        end
    end
    return counts
end

-- =============================================
-- AREA LOADING (at startup)
-- =============================================

local function loadAllMarkers()
    local player = game:GetService("Players").LocalPlayer
    if not player then return end
    local markers = workspace:FindFirstChild("RobberyMarkers")
    if not markers then
        sendLog(LogLevel.WARNING, "Area Load", "RobberyMarkers folder not found.")
        return
    end
    for _, child in ipairs(markers:GetChildren()) do
        if child:IsA("BasePart") then
            player:RequestStreamAroundAsync(child.Position)
            sendLog(LogLevel.INFO, "Area Load", "Requested streaming around " .. child.Name)
            task.wait(0.1)
        end
    end
    sendLog(LogLevel.INFO, "Area Load", "Finished loading all markers.")
end

-- =============================================
-- AIRDROP DETECTION
-- =============================================

local function colorDistance(r1,g1,b1,r2,g2,b2)
    return math.sqrt((r1-r2)^2 + (g1-g2)^2 + (b1-b2)^2)
end

local function matchAirdropColor(r,g,b)
    local best, bestDist = nil, math.huge
    for _, def in ipairs(AIRDROP_COLORS) do
        local dist = colorDistance(r,g,b, def.r,def.g,def.b)
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
    if not pos then return "Unknown Location" end
    local distToCactus = (pos - CACTUS_VALLEY_CENTER).Magnitude
    local distToDunes  = (pos - DUNES_CENTER).Magnitude
    if distToCactus < distToDunes then
        return "Cactus Valley"
    else
        return "Dunes"
    end
end

-- =============================================
-- CROWN JEWEL HELPERS
-- =============================================

local POSITION_THRESHOLD = 5
local knownLocations = {
    {cframe = CFrame.new(-177.696777, 20.1733818, -4682.39795, 0.275480151, -0, -0.96130687, 0, 1, -0, 0.96130687, 0, 0.275480151), axis = "Z"},
    {cframe = CFrame.new(-177.696777, 20.1733818, -4682.39795, 0.275480151, -0, -0.96130687, 0, 1, -0, 0.96130687, 0, 0.275480151), axis = "Z"},
    {cframe = CFrame.new(-307.341309, 21.9233818, -4950.76709, -0.961297989, 0, -0.275510818, 0, 1, 0, 0.275510818, 0, -0.961297989), axis = "X"},
    {cframe = CFrame.new(205.143555, 20.1733818, -4240.87305, 0.961297989, 0, 0.275510818, 0, 1, 0, -0.275510818, 0, 0.961297989), axis = "Y"},
    {cframe = CFrame.new(381.288574, 20.1733818, -4885.12646, -0.275480509, 0, 0.96130687, 0, 1, 0, -0.96130687, 0, -0.275480509), axis = "Z"},
}

local function getAxisForHolder(holderModel)
    local pos = holderModel:GetPivot().Position
    for _, loc in ipairs(knownLocations) do
        if (pos - loc.cframe.Position).Magnitude <= POSITION_THRESHOLD then
            return loc.axis
        end
    end
    return nil
end

local function getCrownJewelCode()
    local casino = workspace:FindFirstChild("Casino")
    if not casino then
        sendLog(LogLevel.WARNING, "Crown Jewel Code", "Casino not found.")
        return nil
    end
    local robberyDoor = casino:FindFirstChild("RobberyDoor")
    if not robberyDoor then
        sendLog(LogLevel.WARNING, "Crown Jewel Code", "RobberyDoor not found.")
        return nil
    end
    local codesFolder = robberyDoor:FindFirstChild("Codes")
    if not codesFolder then
        sendLog(LogLevel.WARNING, "Crown Jewel Code", "Codes folder not found.")
        return nil
    end

    local digits, detectedAxis = {}, nil
    for _, v in ipairs(codesFolder:GetDescendants()) do
        if v:IsA("TextLabel") and v.Text ~= "" then
            local part = v.Parent.Parent
            local holder = v.Parent.Parent.Parent
            if part:IsA("BasePart") then
                if not detectedAxis then
                    detectedAxis = getAxisForHolder(holder)
                end
                table.insert(digits, { text = v.Text, part = part })
            end
        end
    end

    if #digits == 0 then return nil end
    if not detectedAxis then
        sendLog(LogLevel.WARNING, "Crown Jewel Code", "Could not match holder, defaulting X axis.")
        detectedAxis = "X"
    end

    table.sort(digits, function(a,b)
        if detectedAxis == "X" then
            return a.part.Position.X < b.part.Position.X
        elseif detectedAxis == "Z" then
            return a.part.Position.Z < b.part.Position.Z
        elseif detectedAxis == "Y" then
            return a.part.Position.Y < b.part.Position.Y
        end
    end)

    local code = ""
    for _, d in ipairs(digits) do code = code .. d.text end
    return code
end

local function parseTimerString(timerStr)
    if not timerStr then return nil end
    local minutes, seconds = timerStr:match("(%d+):(%d+)")
    if minutes and seconds then
        return tonumber(minutes) * 60 + tonumber(seconds)
    end
    return nil
end

local function getCrownJewelTimer()
    local casino = workspace:FindFirstChild("Casino")
    if not casino then return nil end
    local clocks = casino:FindFirstChild("Clocks")
    if not clocks then return nil end
    for _, child in ipairs(clocks:GetChildren()) do
        local surfaceGui = child:FindFirstChild("SurfaceGui")
        if surfaceGui then
            local textLabel = surfaceGui:FindFirstChildWhichIsA("TextLabel")
            if textLabel and textLabel.Text and textLabel.Text ~= "" then
                local seconds = parseTimerString(textLabel.Text)
                if seconds then return seconds end
            end
        end
    end
    return nil
end

-- =============================================
-- PLANE DETECTION
-- =============================================

local function getPlanePart()
    local plane = workspace:FindFirstChild("Plane")
    if not plane then return nil end
    if plane:IsA("Model") then
        return plane:FindFirstChild("CargoPlane") or plane.PrimaryPart
    else
        return plane
    end
end

local function getClosestWaypointIndex(pos)
    local bestIdx, bestDist = nil, math.huge
    for i, wp in ipairs(PLANE_WAYPOINTS) do
        local dist = (pos - wp.cframe.Position).Magnitude
        if dist < bestDist then
            bestDist = dist
            bestIdx = i
        end
    end
    return bestIdx, bestDist
end

local function getPlaneSpeedAndETA()
    local part = getPlanePart()
    if not part then return nil, nil end
    local pos1 = part.Position
    task.wait(1)
    local pos2 = part.Position
    local speed = (pos2 - pos1).Magnitude
    if speed < 0.1 then return nil, nil end
    local airportPos = PLANE_WAYPOINTS[PLANE_INDICES.AIRPORT].cframe.Position
    local distToAirport = (pos2 - airportPos).Magnitude
    local eta = distToAirport / speed
    return speed, eta
end

local function getPlaneStatus()
    local part = getPlanePart()
    if not part then return nil end
    local pos = part.Position
    local forward = part.CFrame.LookVector
    local currentIdx, _ = getClosestWaypointIndex(pos)
    if not currentIdx then return nil end

    local airportPos = PLANE_WAYPOINTS[PLANE_INDICES.AIRPORT].cframe.Position
    local distToAirport = (pos - airportPos).Magnitude
    if distToAirport < 50 then return "Landed" end

    local dirToAirport = (airportPos - pos).Unit
    local dot = forward:Dot(dirToAirport)
    local movingToward = dot > 0.2

    if currentIdx < PLANE_INDICES.SPAWN then
        return nil
    elseif currentIdx >= PLANE_INDICES.SPAWN and currentIdx < PLANE_INDICES.TURN_START then
        return movingToward and "Just Spawned" or nil
    elseif currentIdx >= PLANE_INDICES.TURN_START and currentIdx <= PLANE_INDICES.TURN_END then
        return movingToward and "Turning" or nil
    elseif currentIdx > PLANE_INDICES.TURN_END and currentIdx < PLANE_INDICES.AIRPORT then
        if movingToward then
            return "Almost Arriving"
        elseif currentIdx > PLANE_INDICES.AIRPORT and dot < -0.2 then
            return "Taking Off"
        else
            return nil
        end
    elseif currentIdx >= PLANE_INDICES.AIRPORT then
        return (distToAirport < 50) and "Landed" or "Taking Off"
    end
    return nil
end

-- =============================================
-- TRAIN DETECTION
-- =============================================

local function getClosestMarkerWithDistance(pos)
    local markers = workspace:FindFirstChild("RobberyMarkers")
    if not markers then return "Unknown", math.huge end
    local closestName, minDist = "Unknown", math.huge
    for _, child in ipairs(markers:GetChildren()) do
        if child:IsA("BasePart") then
            local dist = (pos - child.Position).Magnitude
            if dist < minDist then
                minDist = dist
                closestName = child.Name
            end
        end
    end
    return closestName, minDist
end

local function getTrainPosition(storeName)
    local trains = workspace:FindFirstChild("Trains")
    if not trains then return nil end
    local trainModel = (storeName == "Cargo_Train") and trains:FindFirstChild("LocomotiveFront") or trains:FindFirstChild("SteamEngine")
    if not trainModel then return nil end
    if trainModel:IsA("Model") then
        if trainModel.PrimaryPart then
            return trainModel.PrimaryPart.Position
        else
            for _, part in ipairs(trainModel:GetDescendants()) do
                if part:IsA("BasePart") then return part.Position end
            end
        end
    elseif trainModel:IsA("BasePart") then
        return trainModel.Position
    end
    return nil
end

-- =============================================
-- OIL RIG TIMER
-- =============================================

local function getOilRigTimer()
    local oilRig = workspace:FindFirstChild("OilRig")
    if not oilRig then return nil end
    local tntPlants = oilRig:FindFirstChild("TNTPlantLocations")
    if not tntPlants then return nil end
    for _, child in ipairs(tntPlants:GetChildren()) do
        local tnt = child:FindFirstChild("TNT", true)
        if tnt then
            local surfaceGui = tnt:FindFirstChildWhichIsA("SurfaceGui", true)
            if surfaceGui then
                local textLabel = surfaceGui:FindFirstChildWhichIsA("TextLabel", true)
                if textLabel and textLabel.Text and textLabel.Text ~= "" then
                    local seconds = parseTimerString(textLabel.Text)
                    if seconds then return seconds end
                end
            end
        end
    end
    return nil
end

-- =============================================
-- MANSION TIME HELPERS
-- =============================================

local function getGameTimeText()
    local s, lbl = pcall(function()
        return game:GetService("Players").LocalPlayer.PlayerGui.AppUI.Buttons.Minimap.Time.Time
    end)
    if s and lbl and lbl:IsA("TextLabel") then return lbl.Text end
    return nil
end

local function parseGameTime(timeStr)
    local hour, minute, period = timeStr:match("(%d+):(%d+)%s*(%a+)")
    if not hour then return nil end
    hour = tonumber(hour); minute = tonumber(minute); period = period:upper()
    if period == "PM" and hour ~= 12 then hour = hour + 12
    elseif period == "AM" and hour == 12 then hour = 0 end
    return hour, minute, period
end

local function getMansionStatus()
    local timeText = getGameTimeText()
    if not timeText then return nil, nil, nil end
    local hour, minute, period = parseGameTime(timeText)
    if not hour then return nil, nil, nil end
    local totalMinutes = hour * 60 + (minute or 0)
    local status, display
    if totalMinutes >= 1080 or totalMinutes < 15 then
        status = "open"; display = "Open"
    elseif totalMinutes >= 960 and totalMinutes < 1080 then
        status = "opening_soon"; display = "Opening Soon"
    elseif totalMinutes >= 15 and totalMinutes < 120 then
        status = "closing_soon"; display = "Closing Soon"
    else
        status = "closed"; display = "Closed"
    end
    return status, display, timeText
end

-- =============================================
-- BOUNTY DETECTION
-- =============================================

local function checkBounties(jobId, loggedSpecials)
    if loggedSpecials.Bounty then return loggedSpecials end
    if getgenv().RobberyToggles and not getgenv().RobberyToggles.Bounty then return loggedSpecials end

    local webhook = getgenv().WebhookConfig.Webhooks["Bounty"]
    if not webhook or webhook == "" then
        sendLog(LogLevel.WARNING, "Bounty Webhook Missing", "No webhook configured for Bounty.")
        return loggedSpecials
    end

    local minBounty = DEFAULT_MIN_BOUNTY
    if getgenv().RobberyToggles and getgenv().RobberyToggles.MinBounty then
        minBounty = getgenv().RobberyToggles.MinBounty
    end

    local localPlayer = game:GetService("Players").LocalPlayer
    local hrp = localPlayer and localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        sendLog(LogLevel.WARNING, "Bounty Scan", "Could not get HumanoidRootPart. Skipping.")
        return loggedSpecials
    end

    -- Find closest BountyBoard
    local closestBoard, closestDist = nil, math.huge
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name == "BountyBoard" and obj:IsA("Model") then
            local pos
            if obj.PrimaryPart then
                pos = obj.PrimaryPart.Position
            else
                for _, part in ipairs(obj:GetDescendants()) do
                    if part:IsA("BasePart") then pos = part.Position; break end
                end
            end
            if pos then
                local dist = (pos - hrp.Position).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closestBoard = obj
                end
            end
        end
    end

    if not closestBoard then
        sendLog(LogLevel.INFO, "Bounty Scan", "No BountyBoard found.")
        return loggedSpecials
    end

    local bountyPlayers = {}
    local boardModel = closestBoard:FindFirstChild("Board")
    if boardModel then
        local mostWanted = boardModel:FindFirstChild("MostWanted")
        if mostWanted then
            local board2 = mostWanted:FindFirstChild("Board")
            if board2 then
                for _, playerFrame in ipairs(board2:GetChildren()) do
                    if playerFrame.Name == "PlayerFrame" then
                        local nameText = playerFrame:FindFirstChild("NameText")
                        local bountyText = playerFrame:FindFirstChild("BountyText")
                        if nameText and nameText:IsA("TextLabel") and bountyText and bountyText:IsA("TextLabel") then
                            local displayName = nameText.Text:gsub("^%s+", ""):gsub("%s+$", "")
                            local bountyStr = bountyText.Text:gsub("[$,]", "")
                            local bounty = tonumber(bountyStr)
                            if bounty and bounty >= minBounty then
                                local targetPlayer
                                for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
                                    if plr.DisplayName == displayName then
                                        targetPlayer = plr
                                        break
                                    end
                                end
                                if targetPlayer then
                                    table.insert(bountyPlayers, {
                                        username = targetPlayer.Name,
                                        userId   = targetPlayer.UserId,
                                        bounty   = bounty,
                                        displayName = displayName
                                    })
                                else
                                    table.insert(bountyPlayers, {
                                        username = displayName,
                                        userId   = nil,
                                        bounty   = bounty,
                                        displayName = displayName
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if #bountyPlayers > 0 then
        -- sendBountyEmbed will be called from the embed section
        loggedSpecials.BountyData = bountyPlayers
        loggedSpecials.Bounty = true
        sendLog(LogLevel.SUCCESS, "Bounty Scan", string.format("Found %d player(s) with bounty ≥ $%d.", #bountyPlayers, minBounty))
    else
        sendLog(LogLevel.INFO, "Bounty Scan", string.format("No players with bounty ≥ $%d found.", minBounty))
    end
    return loggedSpecials
end

-- =============================================
-- EMBED FUNCTIONS (Grouped by robbery)
-- =============================================

-- Base embed helper (used by many)
local function buildBaseEmbed(storeName, status, jobId, extraFields, colorOverride, imageOverride)
    local now = os.time()
    local joinLink = getJoinLink(jobId)
    local tc = getTeamCounts()
    local crim = tc.Criminal
    local pol = tc.Police
    local pris = tc.Prisoner
    local crimAndPris = crim + pris
    local total = crimAndPris + pol

    local roleId = getgenv().WebhookConfig.Roles[storeName]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
    local imageUrl = imageOverride or getgenv().WebhookConfig.Images[storeName]

    local fields = {
        { name = "📍 Status",      value = status,          inline = true },
        { name = "👥 Total Players", value = tostring(total), inline = true },
        { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
        { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
        { name = "🚔 Police",       value = tostring(pol),    inline = true },
        { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
    }
    if extraFields then
        for _, f in ipairs(extraFields) do
            table.insert(fields, f)
        end
    end

    local embed = {
        color = colorOverride or (status == "Open" and 3066993 or 15105570),
        fields = fields,
        footer = { text = "Leaf Logger " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    return embed, roleMention
end

-- Jewelry Store
local function sendJewelryStoreEmbed(webhookUrl, storeName, status, jobId, timerSeconds)
    local extra = timerSeconds and { { name = "⏳ Closes in", value = "<t:" .. (os.time() + timerSeconds) .. ":R>", inline = true } } or nil
    local embed, roleMention = buildBaseEmbed(storeName, status, jobId, extra)
    local payload = { embeds = { embed } }
    if roleMention then payload.content = roleMention end
    local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(payload) end)
    if ok then pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = enc }) end) end
end

-- Power Plant (same as Jewelry)
local function sendPowerPlantEmbed(webhookUrl, storeName, status, jobId, timerSeconds)
    sendJewelryStoreEmbed(webhookUrl, storeName, status, jobId, timerSeconds)
end

-- Museum
local function sendMuseumEmbed(webhookUrl, storeName, status, jobId, timerSeconds)
    sendJewelryStoreEmbed(webhookUrl, storeName, status, jobId, timerSeconds)
end

-- Rising Bank
local function sendRisingBankEmbed(webhookUrl, storeName, status, jobId, timerSeconds)
    sendJewelryStoreEmbed(webhookUrl, storeName, status, jobId, timerSeconds)
end

-- Crater Bank
local function sendCraterBankEmbed(webhookUrl, storeName, status, jobId, timerSeconds)
    sendJewelryStoreEmbed(webhookUrl, storeName, status, jobId, timerSeconds)
end

-- Tomb
local function sendTombEmbed(webhookUrl, storeName, status, jobId, timerSeconds)
    sendJewelryStoreEmbed(webhookUrl, storeName, status, jobId, timerSeconds)
end

-- Bank Truck
local function sendBankTruckEmbed(webhookUrl, storeName, status, jobId, timerSeconds)
    sendJewelryStoreEmbed(webhookUrl, storeName, status, jobId, timerSeconds)
end

-- Mansion (custom)
local function sendMansionEmbed(webhookUrl, storeName, status, displayStatus, timeText, jobId)
    local now = os.time()
    local joinLink = getJoinLink(jobId)
    local tc = getTeamCounts()
    local crim = tc.Criminal; local pol = tc.Police; local pris = tc.Prisoner
    local crimAndPris = crim + pris; local total = crimAndPris + pol
    local roleId = getgenv().WebhookConfig.Roles[storeName]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
    local imageUrl = getgenv().WebhookConfig.Images[storeName]

    local fields = {
        { name = "⏰ Game Time",   value = timeText,        inline = true },
        { name = "📍 Status",      value = displayStatus,   inline = true },
        { name = "👥 Total Players", value = tostring(total), inline = true },
        { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
        { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
        { name = "🚔 Police",       value = tostring(pol),    inline = true },
        { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
    }

    local color = (status == "open") and 3066993 or (status == "opening_soon") and 16753920 or 15158332
    local embed = {
        color = color,
        fields = fields,
        footer = { text = "Leaf Logger " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local payload = { embeds = { embed } }
    if roleMention then payload.content = roleMention end
    local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(payload) end)
    if ok then pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = enc }) end) end
end

-- Crown Jewel (custom)
local function sendCrownJewelEmbed(webhookUrl, storeName, status, jobId, code, timerSeconds)
    local now = os.time()
    local joinLink = getJoinLink(jobId)
    local tc = getTeamCounts()
    local crim = tc.Criminal; local pol = tc.Police; local pris = tc.Prisoner
    local crimAndPris = crim + pris; local total = crimAndPris + pol
    local roleId = getgenv().WebhookConfig.Roles[storeName]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
    local imageUrl = getgenv().WebhookConfig.Images[storeName]
    local isOpen = status == "open"
    local color = isOpen and 3066993 or 15105570
    local fields = {
        { name = "👥 Total Players", value = tostring(total), inline = true },
        { name = "🔢 Code",        value = code,             inline = true },
        { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
        { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
        { name = "🚔 Police",       value = tostring(pol),    inline = true },
        { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
    }
    if timerSeconds then
        table.insert(fields, 1, { name = "⏳ Closes in", value = "<t:" .. (now + timerSeconds) .. ":R>", inline = true })
    end
    local embed = {
        color = color,
        fields = fields,
        footer = { text = "Leaf Logger " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local payload = { embeds = { embed } }
    if roleMention then payload.content = roleMention end
    local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(payload) end)
    if ok then pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = enc }) end) end
end

-- Plane (custom)
local function sendPlaneEmbed(webhookUrl, status, jobId)
    local now = os.time()
    local joinLink = getJoinLink(jobId)
    local tc = getTeamCounts()
    local crim = tc.Criminal; local pol = tc.Police; local pris = tc.Prisoner
    local crimAndPris = crim + pris; local total = crimAndPris + pol
    local roleId = getgenv().WebhookConfig.Roles["Cargo_Plane"]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
    local imageUrl = getgenv().WebhookConfig.Images["Cargo_Plane"]
    local speed, eta = getPlaneSpeedAndETA()
    local etaField = eta and ("<t:" .. (now + eta) .. ":R>") or "Unknown"
    local fields = {
        { name = "📍 Status",   value = status,   inline = true },
        { name = "⏱️ ETA",      value = etaField, inline = true },
        { name = "👥 Total Players", value = tostring(total), inline = true },
        { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
        { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
        { name = "🚔 Police",       value = tostring(pol), inline = true },
        { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
    }
    local embed = {
        color = 3447003,
        fields = fields,
        footer = { text = "Leaf Logger " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local payload = { embeds = { embed } }
    if roleMention then payload.content = roleMention end
    local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(payload) end)
    if ok then pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = enc }) end) end
end

-- Train (custom, with location only)
local function sendTrainEmbed(webhookUrl, storeName, locationName, jobId)
    local now = os.time()
    local joinLink = getJoinLink(jobId)
    local tc = getTeamCounts()
    local crim = tc.Criminal; local pol = tc.Police; local pris = tc.Prisoner
    local crimAndPris = crim + pris; local total = crimAndPris + pol
    local roleId = getgenv().WebhookConfig.Roles[storeName]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
    local imageUrl = getgenv().WebhookConfig.Images[storeName]
    local isCargo = (storeName == "Cargo_Train")
    local fields = {
        { name = "📍 Location",    value = locationName,      inline = true },
        { name = "👥 Total Players", value = tostring(total), inline = true },
        { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
        { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
        { name = "🚔 Police",       value = tostring(pol),    inline = true },
        { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
    }
    local embed = {
        color = isCargo and 15105570 or 3066993,
        fields = fields,
        footer = { text = "Leaf Logger " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local payload = { embeds = { embed } }
    if roleMention then payload.content = roleMention end
    local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(payload) end)
    if ok then pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = enc }) end) end
end

-- Oil Rig (custom)
local function sendOilRigEmbed(webhookUrl, timeRemaining, jobId)
    local now = os.time()
    local joinLink = getJoinLink(jobId)
    local tc = getTeamCounts()
    local crim = tc.Criminal; local pol = tc.Police; local pris = tc.Prisoner
    local crimAndPris = crim + pris; local total = crimAndPris + pol
    local roleId = getgenv().WebhookConfig.Roles["Oil_Rig"]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
    local imageUrl = getgenv().WebhookConfig.Images["Oil_Rig"]
    local fields = {
        { name = "⏳ Closes in",   value = timeRemaining and ("<t:" .. (now + timeRemaining) .. ":R>") or "Not Started", inline = true },
        { name = "👥 Total Players", value = tostring(total), inline = true },
        { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
        { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
        { name = "🚔 Police",       value = tostring(pol),    inline = true },
        { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
    }
    local embed = {
        color = 16753920,
        fields = fields,
        footer = { text = "Leaf Logger " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local payload = { embeds = { embed } }
    if roleMention then payload.content = roleMention end
    local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(payload) end)
    if ok then pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = enc }) end) end
end

-- Airdrop (custom)
local function sendAirdropEmbed(webhookUrl, drop, colorDef, locationName, jobId, timerText)
    local now = os.time()
    local joinLink = getJoinLink(jobId)
    local tc = getTeamCounts()
    local crim = tc.Criminal; local pol = tc.Police; local pris = tc.Prisoner
    local crimAndPris = crim + pris; local total = crimAndPris + pol
    local roleKey = colorDef.label:match("🔴") and "RedAirdrop" or
                    colorDef.label:match("🟤") and "BrownAirdrop" or
                    colorDef.label:match("🔵") and "BlueAirdrop" or nil
    local roleId = roleKey and getgenv().WebhookConfig.Roles[roleKey]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
    local imageUrl = roleKey and getgenv().WebhookConfig.Images[roleKey]
    local fields = {
        { name = "⏳ Time Left",   value = timerText or "N/A",   inline = true },
        { name = "🎨 Drop Type",   value = colorDef.label,       inline = true },
        { name = "📍 Location",    value = locationName,         inline = true },
        { name = "👥 Total Players", value = tostring(total),    inline = true },
        { name = "🔗 Join Server", value = "[Click to Join](" .. joinLink .. ")", inline = false },
        { name = "🏃 Criminals",   value = tostring(crimAndPris), inline = false },
        { name = "🚔 Police",      value = tostring(pol),        inline = true },
        { name = "⏱️ Logged",      value = "<t:" .. now .. ":R>", inline = true },
    }
    local embed = {
        color = colorDef.embedColor,
        fields = fields,
        footer = { text = "Leaf Logger " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local payload = { embeds = { embed } }
    if roleMention then payload.content = roleMention end
    local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(payload) end)
    if ok then pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = enc }) end) end
end

-- Bounty (custom)
local function sendBountyEmbed(webhookUrl, bountyPlayers, jobId)
    table.sort(bountyPlayers, function(a,b) return a.bounty > b.bounty end)
    local top = bountyPlayers[1]
    local thumb = top and top.userId and ("https://www.roblox.com/headshot-thumbnail/image?userId=" .. top.userId .. "&width=420&height=420&format=png")
    local now = os.time()
    local joinLink = getJoinLink(jobId)
    local tc = getTeamCounts()
    local crim = tc.Criminal; local pol = tc.Police; local pris = tc.Prisoner
    local crimAndPris = crim + pris; local total = crimAndPris + pol
    local roleId = getgenv().WebhookConfig.Roles["Bounty"]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
    local imageUrl = getgenv().WebhookConfig.Images["Bounty"]
    local playerList = ""
    for _, p in ipairs(bountyPlayers) do
        playerList = playerList .. "**" .. (p.username or p.displayName) .. "**: $" .. p.bounty .. "\n"
    end
    local fields = {
        { name = "💰 Players with Bounties", value = playerList, inline = false },
        { name = "📊 Total Big Bounty Players", value = tostring(#bountyPlayers), inline = true },
        { name = "👥 Total Players", value = tostring(total), inline = true },
        { name = "🔗 Join Server", value = "[Click to Join](" .. joinLink .. ")", inline = false },
        { name = "🏃 Criminals", value = tostring(crimAndPris), inline = true },
        { name = "🚔 Police", value = tostring(pol), inline = true },
        { name = "⏱️ Logged", value = "<t:" .. now .. ":R>", inline = true },
    }
    local embed = {
        color = 16766720,
        fields = fields,
        footer = { text = "Leaf Logger " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if thumb then
        embed.thumbnail = { url = thumb }
    elseif imageUrl then
        embed.image = { url = imageUrl }
    end
    local payload = { embeds = { embed } }
    if roleMention then payload.content = roleMention end
    local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(payload) end)
    if ok then pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = enc }) end) end
end

-- =============================================
-- SCAN FUNCTIONS
-- =============================================

local function checkAirdrops(jobId, loggedDrops)
    local webhook = getgenv().WebhookConfig.Webhooks.Airdrop
    if not webhook or webhook == "" then
        sendLog(LogLevel.WARNING, "Airdrop Webhook Missing", "No webhook.")
        return loggedDrops
    end
    if getgenv().RobberyToggles and not getgenv().RobberyToggles.Airdrop then return loggedDrops end

    local found = {}
    for _, drop in ipairs(workspace:GetChildren()) do
        if drop.Name == "Drop" and drop:IsA("Model") and not loggedDrops[drop] then
            -- (Detection logic copied from earlier – unchanged)
            local wallPart = nil
            local walls = drop:FindFirstChild("Walls") or drop:FindFirstChild("walls")
            if walls then
                wallPart = walls:FindFirstChild("Wall") or walls:FindFirstChild("wall") or walls:FindFirstChildWhichIsA("BasePart", true)
            end
            if not wallPart then
                for _, child in ipairs(drop:GetChildren()) do
                    if child:IsA("BasePart") and child.Name:lower() == "wall" then
                        wallPart = child; break
                    end
                end
            end
            if not wallPart then
                local parts = {}
                for _, d in ipairs(drop:GetDescendants()) do
                    if d:IsA("BasePart") then table.insert(parts, d) end
                end
                if #parts == 1 then
                    wallPart = parts[1]
                elseif #parts > 1 then
                    wallPart = parts[1]
                end
            end
            if not wallPart then continue end

            local col = wallPart.Color
            local r,g,b = math.round(col.R*255), math.round(col.G*255), math.round(col.B*255)
            local colorDef = matchAirdropColor(r,g,b)
            if not colorDef then continue end

            local npcs = drop:FindFirstChild("NPCs")
            if npcs and #npcs:GetChildren() > 0 then continue end

            local countdown = drop:FindFirstChild("Countdown")
            local timerLabel, timerText = nil, nil
            if countdown then
                local billboard = countdown:FindFirstChildWhichIsA("BillboardGui", true)
                if billboard then timerLabel = billboard:FindFirstChildWhichIsA("TextLabel") end
                if timerLabel then timerText = timerLabel.Text end
            end
            if timerText then
                local initial = timerText
                task.wait(5)
                local new = timerLabel and timerLabel.Text
                timerText = (new and new ~= initial) and new or "Unopened"
            else
                timerText = "No timer"
            end

            local pos = getDropPosition(drop)
            local locName = pos and getNearestLocation(pos) or "Unknown Location"

            table.insert(found, {
                drop = drop,
                colorDef = colorDef,
                location = locName,
                timer = timerText
            })
            loggedDrops[drop] = true
        end
    end

    for _, data in ipairs(found) do
        sendAirdropEmbed(webhook, data.drop, data.colorDef, data.location, jobId, data.timer)
        sendLog(LogLevel.SUCCESS, "Airdrop Logged", "Logged.", {
            { name = "Type", value = data.colorDef.label },
            { name = "Location", value = data.location },
            { name = "Timer", value = data.timer }
        })
    end
    if #found > 0 then
        sendLog(LogLevel.INFO, "Airdrop Scan", string.format("Found %d airdrops.", #found))
    end
    return loggedDrops
end

local function scanStores(player, jobId, loggedStores)
    local pg = player and player:FindFirstChild("PlayerGui")
    if not pg then
        sendLog(LogLevel.ERROR, "Store Scan", "PlayerGui not found.")
        return loggedStores
    end
    local wm = pg:FindFirstChild("WorldMarkersGui")
    if not wm then
        sendLog(LogLevel.ERROR, "Store Scan", "WorldMarkersGui not found.")
        return loggedStores
    end

    local openCount, robberyCount, closedCount, missedCount = 0,0,0,0
    for storeName, iconId in pairs(getgenv().WebhookConfig.Icons) do
        local display = formatName(storeName)
        local found = false
        for _, img in ipairs(wm:GetDescendants()) do
            if img:IsA("ImageLabel") and img.Image == iconId then
                found = true
                local parent = img.Parent
                if parent and parent:IsA("ImageLabel") then
                    local col = parent.ImageColor3
                    local r,g,b = math.round(col.R*255), math.round(col.G*255), math.round(col.B*255)
                    local webhook = getgenv().WebhookConfig.Webhooks[storeName]
                    local isOpen   = (r==0 and g==255 and b==0)
                    local isClosed = (r==255 and g==0 and b==0)
                    local isRobbery = not isOpen and not isClosed

                    if isOpen then openCount = openCount + 1
                    elseif isClosed then closedCount = closedCount + 1
                    else robberyCount = robberyCount + 1 end

                    -- ========== CROWN JEWEL ==========
                    if storeName == "Crown_Jewel" then
                        if getgenv().RobberyToggles and not getgenv().RobberyToggles[storeName] then break end
                        if not (isOpen or isRobbery) then break end
                        if loggedStores[storeName] then break end

                        local code = nil
                        for _ = 1,30 do
                            code = getCrownJewelCode()
                            if code and code ~= "" then break end
                            task.wait(0.5)
                        end
                        if not code or code == "" then code = "Fail" end

                        local timer = isRobbery and getCrownJewelTimer() or nil
                        if timer and timer <= 60 then
                            sendLog(LogLevel.INFO, "Crown Jewel Skipped", "Timer too low: " .. timer .. "s")
                            break
                        end
                        sendCrownJewelEmbed(webhook, storeName, (isOpen and "open" or "robbery"), jobId, code, timer)
                        loggedStores[storeName] = true
                        sendLog(LogLevel.SUCCESS, "Crown Jewel Logged", display .. " " .. (isOpen and "Open" or "Under Robbery") .. " — Code: " .. code, {{ name = "Code", value = code }})

                    -- ========== MANSION ==========
                    elseif storeName == "Mansion" then
                        if getgenv().RobberyToggles and not getgenv().RobberyToggles.Mansion then break end
                        if loggedStores[storeName] then break end
                        if isRobbery then
                            sendLog(LogLevel.INFO, "Mansion Robbery Skipped", "Mansion is under robbery.")
                            break
                        end
                        if not isOpen then break end
                        local status, displayStatus, timeText = getMansionStatus()
                        if not status or status == "closed" then break end
                        sendMansionEmbed(webhook, storeName, status, displayStatus, timeText, jobId)
                        loggedStores[storeName] = true
                        sendLog(LogLevel.SUCCESS, "Mansion Logged", "Mansion " .. displayStatus .. " at " .. timeText, {{ name = "Status", value = displayStatus }})

                    -- ========== TRAINS ==========
                    elseif storeName == "Cargo_Train" or storeName == "Passenger_Train" then
                        if loggedStores[storeName] then break end
                        if not isClosed then
                            local pos = getTrainPosition(storeName)
                            if pos then
                                local locName, dist = getClosestMarkerWithDistance(pos)
                                local shouldLog = false
                                if storeName == "Cargo_Train" then
                                    local blocked = false
                                    for _, b in ipairs(TRAIN_FILTERS.Cargo.BLOCKED_LOCATIONS) do
                                        if locName == b and dist > TRAIN_FILTERS.Cargo.BLOCK_DISTANCE then
                                            blocked = true; break
                                        end
                                    end
                                    shouldLog = not blocked
                                else -- Passenger
                                    if locName == "Casino" and dist < 500 then
                                        shouldLog = false
                                    elseif locName == "Bank2" then
                                        shouldLog = false
                                    else
                                        shouldLog = true
                                    end
                                end
                                if shouldLog then
                                    if webhook and webhook ~= "" and getgenv().RobberyToggles and getgenv().RobberyToggles[storeName] then
                                        sendTrainEmbed(webhook, storeName, locName, jobId)
                                        loggedStores[storeName] = true
                                        sendLog(LogLevel.SUCCESS, "Train Logged", display .. " active near " .. locName, {{ name = "Store", value = display }})
                                    else
                                        sendLog(LogLevel.INFO, "Train — Toggled Off", display .. " active but disabled.")
                                    end
                                else
                                    sendLog(LogLevel.INFO, "Train Not Logged", display .. " at " .. locName .. " (dist " .. dist .. ") filtered.")
                                end
                            else
                                sendLog(LogLevel.WARNING, "Train Position Not Found", "Could not get position for " .. storeName)
                            end
                        else
                            sendLog(LogLevel.INFO, "Train Not Active", display .. " is closed.")
                        end

                    -- ========== BANK TRUCK ==========
                    elseif storeName == "Bank_Truck" then
                        if loggedStores[storeName] then break end
                        if isRobbery then
                            if webhook and webhook ~= "" and getgenv().RobberyToggles and getgenv().RobberyToggles[storeName] then
                                sendBankTruckEmbed(webhook, storeName, "robbery", jobId)
                                loggedStores[storeName] = true
                                sendLog(LogLevel.SUCCESS, "Robbery Logged", display .. " under robbery.", {{ name = "Store", value = display }})
                            else
                                sendLog(LogLevel.INFO, "Bank Truck — Toggled Off", display .. " robbery disabled.")
                            end
                        end

                    -- ========== OIL RIG ==========
                    elseif storeName == "Oil_Rig" then
                        sendLog(LogLevel.INFO, "Oil Rig Robbery", "Skipping store scan, will be logged by special robberies.")

                    -- ========== CARGO PLANE ==========
                    elseif storeName == "Cargo_Plane" then
                        sendLog(LogLevel.INFO, "Cargo Plane", "Skipping store scan, logged by special robberies.")

                    -- ========== BOUNTY ==========
                    elseif storeName == "Bounty" then
                        sendLog(LogLevel.INFO, "Bounty", "Skipping store scan, logged by special robberies.")

                    -- ========== ALL OTHER STORES ==========
                    else
                        if loggedStores[storeName] then break end
                        if isOpen then
                            if webhook and webhook ~= "" and getgenv().RobberyToggles and getgenv().RobberyToggles[storeName] then
                                if storeName == "Jewelry_Store" then
                                    sendJewelryStoreEmbed(webhook, storeName, "open", jobId)
                                elseif storeName == "Power_Plant" then
                                    sendPowerPlantEmbed(webhook, storeName, "open", jobId)
                                elseif storeName == "Museum" then
                                    sendMuseumEmbed(webhook, storeName, "open", jobId)
                                elseif storeName == "Rising_Bank" then
                                    sendRisingBankEmbed(webhook, storeName, "open", jobId)
                                elseif storeName == "Crater_Bank" then
                                    sendCraterBankEmbed(webhook, storeName, "open", jobId)
                                elseif storeName == "Tomb" then
                                    sendTombEmbed(webhook, storeName, "open", jobId)
                                else
                                    sendJewelryStoreEmbed(webhook, storeName, "open", jobId)
                                end
                                loggedStores[storeName] = true
                                sendLog(LogLevel.SUCCESS, "Store Open", display .. " open.", {{ name = "Store", value = display }})
                            else
                                sendLog(LogLevel.INFO, "Store Open — Toggled Off", display .. " open but disabled.")
                            end
                        elseif isRobbery then
                            if webhook and webhook ~= "" and getgenv().RobberyToggles and getgenv().RobberyToggles[storeName] then
                                if storeName == "Jewelry_Store" then
                                    sendJewelryStoreEmbed(webhook, storeName, "robbery", jobId)
                                elseif storeName == "Power_Plant" then
                                    sendPowerPlantEmbed(webhook, storeName, "robbery", jobId)
                                elseif storeName == "Museum" then
                                    sendMuseumEmbed(webhook, storeName, "robbery", jobId)
                                elseif storeName == "Rising_Bank" then
                                    sendRisingBankEmbed(webhook, storeName, "robbery", jobId)
                                elseif storeName == "Crater_Bank" then
                                    sendCraterBankEmbed(webhook, storeName, "robbery", jobId)
                                elseif storeName == "Tomb" then
                                    sendTombEmbed(webhook, storeName, "robbery", jobId)
                                else
                                    sendJewelryStoreEmbed(webhook, storeName, "robbery", jobId)
                                end
                                loggedStores[storeName] = true
                                sendLog(LogLevel.SUCCESS, "Robbery Logged", display .. " under robbery.", {{ name = "Store", value = display }})
                            else
                                sendLog(LogLevel.INFO, "Robbery — Toggled Off", display .. " robbery disabled.")
                            end
                        end
                    end
                else
                    missedCount = missedCount + 1
                end
                break
            end
        end
        if not found then missedCount = missedCount + 1 end
    end

    sendLog(LogLevel.INFO, "Store Scan", "Completed.", {
        { name = "✅ Open",    value = tostring(openCount) },
        { name = "🔴 Robbery", value = tostring(robberyCount) },
        { name = "⚫ Closed",  value = tostring(closedCount) },
        { name = "⚠️ Missed",  value = tostring(missedCount) },
    })
    return loggedStores
end

local function checkSpecialRobberies(jobId, loggedSpecials)
    local logged = loggedSpecials or {}
    -- Plane
    local planeStatus = getPlaneStatus()
    if planeStatus and not logged.Plane then
        local webhook = getgenv().WebhookConfig.Webhooks["Cargo_Plane"]
        if webhook and webhook ~= "" then
            sendPlaneEmbed(webhook, planeStatus, jobId)
            logged.Plane = true
            sendLog(LogLevel.SUCCESS, "Plane Logged", "Cargo plane status: " .. planeStatus)
        end
    end
    -- Oil Rig
    local oilTime = getOilRigTimer()
    if oilTime and oilTime > 60 and not logged.OilRig then
        local webhook = getgenv().WebhookConfig.Webhooks["Oil_Rig"]
        if webhook and webhook ~= "" then
            sendOilRigEmbed(webhook, oilTime, jobId)
            logged.OilRig = true
            sendLog(LogLevel.SUCCESS, "Oil Rig Logged", "Oil Rig under robbery.")
        elseif oilTime and oilTime <= 60 then
            sendLog(LogLevel.INFO, "Oil Rig Skipped", "Timer too low: " .. oilTime .. "s")
        end
    end
    -- Bounty
    logged = checkBounties(jobId, logged)
    if logged.BountyData then
        local webhook = getgenv().WebhookConfig.Webhooks["Bounty"]
        if webhook and webhook ~= "" then
            sendBountyEmbed(webhook, logged.BountyData, jobId)
            logged.BountyData = nil -- clear after sending
        end
    end
    return logged
end

-- =============================================
-- SERVER HOP LOGIC
-- =============================================

local function getServerIP(placeId, serverId)
    local ok, resp = pcall(function()
        return request({
            Url = "https://gamejoin.roblox.com/v1/join-game-instance",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json", ["User-Agent"] = "Roblox/WinInet" },
            Body = game:GetService("HttpService"):JSONEncode({
                placeId = placeId,
                gameId = serverId,
                isTeleport = false,
                gameJoinAttemptId = serverId
            })
        })
    end)
    if not ok or not resp or resp.StatusCode ~= 200 then return nil end
    local ok2, data = pcall(function() return game:GetService("HttpService"):JSONDecode(resp.Body) end)
    if not ok2 then return nil end
    if data.joinScript and data.joinScript.MachineAddress then
        return data.joinScript.MachineAddress
    end
    if data.joinScript and data.joinScript.UdmuxEndpoints and #data.joinScript.UdmuxEndpoints > 0 then
        return data.joinScript.UdmuxEndpoints[1].Address
    end
    return nil
end

local function isUSAServer(ip)
    local prefixes = { "104.", "128.116.", "162.", "199.", "66.", "72.", "192." }
    for _, p in ipairs(prefixes) do
        if ip:sub(1, #p) == p then return true end
    end
    return false
end

local function getServerRegion(placeId, serverId)
    local cache = getgenv().ServerRegionCache
    if cache[serverId] then return cache[serverId] end
    local ip = getServerIP(placeId, serverId)
    if not ip then
        cache[serverId] = "unknown"
        return "unknown"
    end
    local region = isUSAServer(ip) and "US" or "other"
    cache[serverId] = region
    return region
end

local function getTargetServer(placeId, currentJobId)
    local servers = {}
    local cursor = nil
    local visited = getgenv().VisitedServers
    repeat
        local ok, res = pcall(function()
            return game:GetService("HttpService"):JSONDecode(
                request({
                    Url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100" .. (cursor and ("&cursor=" .. cursor) or ""),
                    Method = "GET"
                }).Body
            )
        end)
        if not ok or not res or not res.data then
            sendLog(LogLevel.ERROR, "Server List Fetch Failed", "Could not fetch servers.")
            break
        end
        for _, s in ipairs(res.data) do
            if s.id ~= currentJobId and not visited[s.id] and (s.playing or 0) < (s.maxPlayers or 0) and (s.playing or 0) <= MAX_PLAYERS then
                table.insert(servers, s)
            end
        end
        if #servers > 0 then break end
        cursor = res.nextPageCursor
    until not cursor

    if #servers == 0 then
        sendLog(LogLevel.WARNING, "No Valid Servers", "No servers under player limit.")
        return nil
    end
    table.sort(servers, function(a,b) return (a.playing or 0) < (b.playing or 0) end)

    local nonUSA = {}
    for _, s in ipairs(servers) do
        local region = getServerRegion(placeId, s.id)
        if region ~= "US" then
            table.insert(nonUSA, s)
        end
        task.wait(0.1)
    end
    if #nonUSA == 0 then nonUSA = servers end
    sendLog(LogLevel.HOP, "Target Server Found", "Best server: " .. nonUSA[1].id, {
        { name = "Players", value = tostring(nonUSA[1].playing) .. "/" .. tostring(nonUSA[1].maxPlayers) }
    })
    return nonUSA[1].id
end

local function hasS5nniPlayer()
    local me = game:GetService("Players").LocalPlayer
    for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
        if plr ~= me and plr.Name:lower():find("s5nni") then
            return true
        end
    end
    return false
end

local function hopToNewServer(player)
    if getgenv().TeleportInProgress then
        sendLog(LogLevel.WARNING, "Teleport Already in Progress", "Skipping duplicate.")
        return
    end
    getgenv().TeleportInProgress = true

    local placeId = game.PlaceId
    local oldId = game.JobId
    local visited = loadVisitedServers()
    visited[oldId] = os.time()
    saveVisitedServers(visited)
    getgenv().VisitedServers = visited

    local targetId = getTargetServer(placeId, oldId)
    local tp = game:GetService("TeleportService")

    pcall(function() clear_teleport_queue() end)
    pcall(function() queue_on_teleport(getgenv()._ServerHopSource) end)
    task.wait(0.1)

    if targetId then
        sendLog(LogLevel.HOP, "Teleporting", "To " .. targetId)
        local ok, err = pcall(function() tp:TeleportToPlaceInstance(placeId, targetId, player) end)
        if not ok then
            sendLog(LogLevel.ERROR, "Teleport Failed", err)
            getgenv().TeleportInProgress = false
            pcall(function() tp:Teleport(placeId, player) end)
        end
        task.spawn(function()
            task.wait(30)
            if game.JobId == oldId then
                sendLog(LogLevel.WARNING, "Teleport Stuck", "Retrying.")
                getgenv().TeleportInProgress = false
                hopToNewServer(player)
            else
                getgenv().TeleportInProgress = false
            end
        end)
    else
        sendLog(LogLevel.WARNING, "No Target Server", "Random teleport.")
        getgenv().TeleportInProgress = false
        pcall(function() tp:Teleport(placeId, player) end)
    end
end

if not getgenv()._ServerHopSource then
    getgenv()._ServerHopSource = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/main.lua"))()]]
end

-- =============================================
-- MAIN EXECUTION
-- =============================================

pcall(function()
    local player = waitForLoad()
    local jobId = game.JobId
    sendLog(LogLevel.INFO, "Bot Started", "Script loaded.", { { name = "Server ID", value = jobId } })

    if hasS5nniPlayer() then
        sendLog(LogLevel.INFO, "S5nni Player Detected", "Hopping without scanning.")
        hopToNewServer(player)
        return
    end

    local visited = loadVisitedServers()
    if visited[jobId] then
        local elapsed = os.time() - visited[jobId]
        if elapsed < 300 then
            sendLog(LogLevel.INFO, "Server Recently Visited", string.format("%d seconds ago. Hopping.", elapsed))
            hopToNewServer(player)
            return
        else
            visited[jobId] = nil
            saveVisitedServers(visited)
        end
    end

    if getgenv().ServerId == jobId then
        sendLog(LogLevel.WARNING, "Duplicate Server", "Hopping immediately.")
        hopToNewServer(player)
        return
    end
    getgenv().ServerId = jobId

    -- Pre‑load all robbery areas
    loadAllMarkers()

    sendLog(LogLevel.INFO, "First Pass Started", "Scanning for open stores...")
    local loggedStores, loggedDrops, loggedSpecials = {}, {}, {}
    loggedStores   = scanStores(player, jobId, loggedStores)
    loggedDrops    = checkAirdrops(jobId, loggedDrops)
    loggedSpecials = checkSpecialRobberies(jobId, loggedSpecials)

    sendLog(LogLevel.INFO, "Waiting Period", "15 seconds for robberies to start...")
    task.wait(15)

    sendLog(LogLevel.INFO, "Second Pass Started", "Scanning for robberies that started...")
    loggedStores   = scanStores(player, jobId, loggedStores)
    loggedDrops    = checkAirdrops(jobId, loggedDrops)
    loggedSpecials = checkSpecialRobberies(jobId, loggedSpecials)

    getgenv().IsFinished = true
    sendLog(LogLevel.SUCCESS, "Cycle Complete", "Hopping in 2 seconds.")
    task.wait(2)
    hopToNewServer(player)
end)
