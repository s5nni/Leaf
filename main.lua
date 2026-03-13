-- =============================================
-- LEAF ROBLOX ROBBERY LOGGER – WAYPOINT TIME LEFT
-- Author: s5nni
-- Version: Loaded from version.lua
-- =============================================

loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/webhook.lua"))()
loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/whitelist.lua"))()
loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/robberies.lua"))()
local BOT_VERSION = loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/version.lua"))()

-- =============================================
-- LOAD WAYPOINT DATA
-- =============================================
local WAYPOINTS = (function()
    local success, result = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/waypoint.lua"))()
    end)
    if success and result then
        return result
    else
        warn("Failed to load waypoint data. Time‑left estimation disabled.")
        return { CargoTrain = {}, PassengerTrain = {}, CargoPlane = {} }
    end
end)()

local CARGO_TRAIN_WAYPOINTS = WAYPOINTS.CargoTrain or {}
local PASSENGER_TRAIN_WAYPOINTS = WAYPOINTS.PassengerTrain or {}
local PLANE_WAYPOINTS = WAYPOINTS.CargoPlane or {}

-- Limit waypoints after which the robbery is considered expired
local LIMITS = {
    CargoPlane = 50,
    CargoTrain = 150,
    PassengerTrain = 155,
}

-- =============================================
-- CONFIGURATION
-- =============================================
local DEFAULT_MIN_BOUNTY = 5000
local MAX_PLAYERS = 5
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

local function sendPrivateLog(level, title, description, fields)
    local webhook = "https://ptb.discord.com/api/webhooks/1479893109688107211/jaSR938vkn0zEcOLN0FmxI3YtiVRmcHTrIuIQzIC68Kpc4-DbvYaXGlNy7Ytn80-Drd_"
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
-- AREA LOADING
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
            for i = 1,math.random(5,7) do
                 player:RequestStreamAroundAsync(child.Position)
                 wait()
            end
        end
    end
    sendLog(LogLevel.INFO, "Area Load", "All marker streaming requested.")
end

-- =============================================
-- AIRDROP DETECTION (unchanged)
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
-- CROWN JEWEL HELPERS (unchanged)
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
-- WAYPOINT-BASED TIME LEFT FUNCTIONS
-- =============================================
local function findClosestWaypoint(pos, waypoints)
    local bestIdx, bestDist = nil, math.huge
    for i, wp in ipairs(waypoints) do
        local dist = (pos - wp.cframe.Position).Magnitude
        if dist < bestDist then
            bestDist = dist
            bestIdx = i
        end
    end
    return bestIdx, bestDist
end

local function getWaypointTimeLeft(pos, waypoints, limitWaypoint)
    if #waypoints == 0 then return nil end
    local idx = findClosestWaypoint(pos, waypoints)
    if not idx then return nil end
    if idx >= limitWaypoint then
        return nil -- already past limit, do not log
    end
    -- time left = time at limit waypoint - time at current closest
    local currentTime = waypoints[idx].time
    local limitTime = waypoints[limitWaypoint].time
    if not currentTime or not limitTime then return nil end
    return limitTime - currentTime
end

-- =============================================
-- PLANE DETECTION (using waypoints)
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

local function getPlaneTimeLeft()
    local part = getPlanePart()
    if not part then return nil end
    return getWaypointTimeLeft(part.Position, PLANE_WAYPOINTS, LIMITS.CargoPlane)
end

-- =============================================
-- TRAIN DETECTION (using waypoints)
-- =============================================
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

local function getTrainTimeLeft(storeName)
    local pos = getTrainPosition(storeName)
    if not pos then return nil end
    if storeName == "Cargo_Train" then
        return getWaypointTimeLeft(pos, CARGO_TRAIN_WAYPOINTS, LIMITS.CargoTrain)
    else
        return getWaypointTimeLeft(pos, PASSENGER_TRAIN_WAYPOINTS, LIMITS.PassengerTrain)
    end
end

-- =============================================
-- OIL RIG (unchanged)
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

local function getOilRigStatus()
    local player = game:GetService("Players").LocalPlayer
    if not player then return nil end
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local wm = pg:FindFirstChild("WorldMarkersGui")
    if not wm then return nil end
    local iconId = getgenv().WebhookConfig.Icons["Oil_Rig"]
    for _, img in ipairs(wm:GetDescendants()) do
        if img:IsA("ImageLabel") and img.Image == iconId then
            local parent = img.Parent
            if parent and parent:IsA("ImageLabel") then
                local col = parent.ImageColor3
                local r = math.round(col.R * 255)
                local g = math.round(col.G * 255)
                local b = math.round(col.B * 255)
                if r == 0 and g == 255 and b == 0 then
                    return "open"
                elseif r == 255 and g == 0 and b == 0 then
                    return "closed"
                else
                    return "robbery"
                end
            end
        end
    end
    return nil
end

-- =============================================
-- MANSION TIME HELPERS (unchanged)
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
-- BOUNTY DETECTION (unchanged)
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
        loggedSpecials.BountyData = bountyPlayers
        loggedSpecials.Bounty = true
        sendLog(LogLevel.SUCCESS, "Bounty Scan", string.format("Found %d player(s) with bounty ≥ $%d.", #bountyPlayers, minBounty))
    else
        sendLog(LogLevel.INFO, "Bounty Scan", string.format("No players with bounty ≥ $%d found.", minBounty))
    end
    return loggedSpecials
end

-- =============================================
-- EMBED FUNCTIONS
-- =============================================
local function buildBaseEmbed(storeName, statusText, isOpen, jobId, extraFields, colorOverride, imageOverride)
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
        { name = "📍 Status",      value = statusText,      inline = true },
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

    local color = colorOverride or (isOpen and 3066993 or 15105570)
    local embed = {
        color = color,
        fields = fields,
        footer = { text = "Build: " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    return embed, roleMention
end

-- Regular store embeds (unchanged)
local function sendJewelryStoreEmbed(webhookUrl, storeName, isOpen, jobId, timerSeconds)
    local statusText = isOpen and "Open" or "Under Robbery"
    local extra = timerSeconds and { { name = "⏳ Closes in", value = "<t:" .. (os.time() + timerSeconds) .. ":R>", inline = true } } or nil
    local embed, roleMention = buildBaseEmbed(storeName, statusText, isOpen, jobId, extra)
    local payload = { embeds = { embed } }
    if roleMention then payload.content = roleMention end
    local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(payload) end)
    if ok then pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = enc }) end) end
end

local function sendPowerPlantEmbed(webhookUrl, storeName, isOpen, jobId, timerSeconds)
    sendJewelryStoreEmbed(webhookUrl, storeName, isOpen, jobId, timerSeconds)
end
local function sendMuseumEmbed(webhookUrl, storeName, isOpen, jobId, timerSeconds)
    sendJewelryStoreEmbed(webhookUrl, storeName, isOpen, jobId, timerSeconds)
end
local function sendRisingBankEmbed(webhookUrl, storeName, isOpen, jobId, timerSeconds)
    sendJewelryStoreEmbed(webhookUrl, storeName, isOpen, jobId, timerSeconds)
end
local function sendCraterBankEmbed(webhookUrl, storeName, isOpen, jobId, timerSeconds)
    sendJewelryStoreEmbed(webhookUrl, storeName, isOpen, jobId, timerSeconds)
end
local function sendTombEmbed(webhookUrl, storeName, isOpen, jobId, timerSeconds)
    sendJewelryStoreEmbed(webhookUrl, storeName, isOpen, jobId, timerSeconds)
end
local function sendBankTruckEmbed(webhookUrl, storeName, isOpen, jobId, timerSeconds)
    sendJewelryStoreEmbed(webhookUrl, storeName, isOpen, jobId, timerSeconds)
end

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
        footer = { text = "Build: " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local payload = { embeds = { embed } }
    if roleMention then payload.content = roleMention end
    local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(payload) end)
    if ok then pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = enc }) end) end
end

local function sendCrownJewelEmbed(webhookUrl, storeName, isOpen, jobId, code, timerSeconds)
    local now = os.time()
    local joinLink = getJoinLink(jobId)
    local tc = getTeamCounts()
    local crim = tc.Criminal; local pol = tc.Police; local pris = tc.Prisoner
    local crimAndPris = crim + pris; local total = crimAndPris + pol
    local roleId = getgenv().WebhookConfig.Roles[storeName]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
    local imageUrl = getgenv().WebhookConfig.Images[storeName]
    local statusText = isOpen and "Open" or "Under Robbery"
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
        color = isOpen and 3066993 or 15105570,
        fields = fields,
        footer = { text = "Build: " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local payload = { embeds = { embed } }
    if roleMention then payload.content = roleMention end
    local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(payload) end)
    if ok then pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = enc }) end) end
end

-- Plane embed with time left
local function sendPlaneEmbed(webhookUrl, timeLeft, jobId)
    local now = os.time()
    local joinLink = getJoinLink(jobId)
    local tc = getTeamCounts()
    local crim = tc.Criminal; local pol = tc.Police; local pris = tc.Prisoner
    local crimAndPris = crim + pris; local total = crimAndPris + pol
    local roleId = getgenv().WebhookConfig.Roles["Cargo_Plane"]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
    local imageUrl = getgenv().WebhookConfig.Images["Cargo_Plane"]

    local fields = {
        { name = "⏳ Time Left",   value = "<t:" .. (now + timeLeft) .. ":R>", inline = true },
        { name = "👥 Total Players", value = tostring(total), inline = true },
        { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
        { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
        { name = "🚔 Police",       value = tostring(pol), inline = true },
        { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
    }
    local embed = {
        color = 3447003,
        fields = fields,
        footer = { text = "Build: " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local payload = { embeds = { embed } }
    if roleMention then payload.content = roleMention end
    local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(payload) end)
    if ok then pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = enc }) end) end
end

-- Train embed with time left
local function sendTrainEmbed(webhookUrl, storeName, timeLeft, jobId)
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
        { name = "⏳ Time Left",   value = "<t:" .. (now + timeLeft) .. ":R>", inline = true },
        { name = "👥 Total Players", value = tostring(total), inline = true },
        { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
        { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
        { name = "🚔 Police",       value = tostring(pol),    inline = true },
        { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
    }
    local embed = {
        color = isCargo and 15105570 or 3066993,
        fields = fields,
        footer = { text = "Build: " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local payload = { embeds = { embed } }
    if roleMention then payload.content = roleMention end
    local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(payload) end)
    if ok then pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = enc }) end) end
end

-- Oil Rig embed (unchanged)
local function sendOilRigEmbed(webhookUrl, timeRemaining, jobId, isUnderRobbery)
    local now = os.time()
    local joinLink = getJoinLink(jobId)
    local teamCounts = getTeamCounts()
    local criminals = teamCounts.Criminal
    local police = teamCounts.Police
    local prisoners = teamCounts.Prisoner
    local crimAndPris = criminals + prisoners
    local totalPlayers = crimAndPris + police
    local roleId = getgenv().WebhookConfig.Roles["Oil_Rig"]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
    local imageUrl = getgenv().WebhookConfig.Images["Oil_Rig"]
    
    local fields
    if isUnderRobbery then
        fields = {
            { name = "⏳ Closes in",   value = "<t:" .. (now + timeRemaining) .. ":R>", inline = true },
            { name = "👥 Total Players", value = tostring(totalPlayers), inline = true  },
            { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
            { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
            { name = "🚔 Police",       value = tostring(police),    inline = true  },
            { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
        }
    else
        fields = {
            { name = "📍 Status",      value = "Open",          inline = true },
            { name = "👥 Total Players", value = tostring(totalPlayers), inline = true  },
            { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
            { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
            { name = "🚔 Police",       value = tostring(police),    inline = true  },
            { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
        }
    end

    local embed = {
        color = isUnderRobbery and 16753920 or 3066993,
        fields = fields,
        footer = { text = "Build: " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local payload = { embeds = { embed } }
    if roleMention then payload.content = roleMention end
    local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(payload) end)
    if ok then pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = enc }) end) end
end

-- Airdrop embed (unchanged)
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
        { name = "🏃 Criminals",   value = tostring(crimAndPris), inline = true },
        { name = "🚔 Police",      value = tostring(pol),        inline = true },
        { name = "⏱️ Logged",      value = "<t:" .. now .. ":R>", inline = true },
    }
    local embed = {
        color = colorDef.embedColor,
        fields = fields,
        footer = { text = "Build: " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local payload = { embeds = { embed } }
    if roleMention then payload.content = roleMention end
    local ok, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(payload) end)
    if ok then pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = enc }) end) end
end

-- Bounty embed (unchanged)
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
        footer = { text = "Build: " .. BOT_VERSION },
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
            -- (detection code unchanged)
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
        return loggedStores, false
    end
    local wm = pg:FindFirstChild("WorldMarkersGui")
    if not wm then
        sendLog(LogLevel.ERROR, "Store Scan", "WorldMarkersGui not found.")
        return loggedStores, false
    end

    local openCount, robberyCount, closedCount, missedCount = 0,0,0,0
    local hasUnderRobbery = false
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
                    else
                        robberyCount = robberyCount + 1
                        hasUnderRobbery = true
                    end

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
                        sendCrownJewelEmbed(webhook, storeName, isOpen, jobId, code, timer)
                        loggedStores[storeName] = true
                        sendLog(LogLevel.SUCCESS, "Crown Jewel Logged", display .. " " .. (isOpen and "Open" or "Under Robbery") .. " — Code: " .. code, {{ name = "Code", value = code }})

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

                    elseif storeName == "Cargo_Train" or storeName == "Passenger_Train" then
                        if loggedStores[storeName] then break end
                        local timeLeft = getTrainTimeLeft(storeName)
                        if timeLeft and timeLeft > 0 then
                            if webhook and webhook ~= "" and getgenv().RobberyToggles and getgenv().RobberyToggles[storeName] then
                                sendTrainEmbed(webhook, storeName, timeLeft, jobId)
                                loggedStores[storeName] = true
                                sendLog(LogLevel.SUCCESS, "Train Logged", display .. " time left: " .. timeLeft .. "s", {{ name = "Store", value = display }})
                            else
                                sendLog(LogLevel.INFO, "Train — Toggled Off", display .. " active but disabled.")
                            end
                        else
                            sendLog(LogLevel.INFO, "Train Not Logged", display .. " past limit or no data.")
                        end

                    elseif storeName == "Bank_Truck" then
                        if loggedStores[storeName] then break end
                        if isOpen then
                            if webhook and webhook ~= "" and getgenv().RobberyToggles and getgenv().RobberyToggles[storeName] then
                                sendBankTruckEmbed(webhook, storeName, true, jobId)
                                loggedStores[storeName] = true
                                sendLog(LogLevel.SUCCESS, "Bank Truck Logged", display .. " is open.", {{ name = "Store", value = display }})
                            else
                                sendLog(LogLevel.INFO, "Bank Truck — Toggled Off", display .. " open but disabled.")
                            end
                        end

                    elseif storeName == "Oil_Rig" then
                        -- handled in special robberies
                    elseif storeName == "Cargo_Plane" then
                        -- handled in special robberies
                    elseif storeName == "Bounty" then
                        -- handled in special robberies
                    else
                        if loggedStores[storeName] then break end
                        if isOpen then
                            if webhook and webhook ~= "" and getgenv().RobberyToggles and getgenv().RobberyToggles[storeName] then
                                if storeName == "Jewelry_Store" then
                                    sendJewelryStoreEmbed(webhook, storeName, true, jobId)
                                elseif storeName == "Power_Plant" then
                                    sendPowerPlantEmbed(webhook, storeName, true, jobId)
                                elseif storeName == "Museum" then
                                    sendMuseumEmbed(webhook, storeName, true, jobId)
                                elseif storeName == "Rising_Bank" then
                                    sendRisingBankEmbed(webhook, storeName, true, jobId)
                                elseif storeName == "Crater_Bank" then
                                    sendCraterBankEmbed(webhook, storeName, true, jobId)
                                elseif storeName == "Tomb" then
                                    sendTombEmbed(webhook, storeName, true, jobId)
                                else
                                    sendJewelryStoreEmbed(webhook, storeName, true, jobId)
                                end
                                loggedStores[storeName] = true
                                sendLog(LogLevel.SUCCESS, "Store Open", display .. " open.", {{ name = "Store", value = display }})
                            else
                                sendLog(LogLevel.INFO, "Store Open — Toggled Off", display .. " open but disabled.")
                            end
                        elseif isRobbery then
                            if webhook and webhook ~= "" and getgenv().RobberyToggles and getgenv().RobberyToggles[storeName] then
                                if storeName == "Jewelry_Store" then
                                    sendJewelryStoreEmbed(webhook, storeName, false, jobId)
                                elseif storeName == "Power_Plant" then
                                    sendPowerPlantEmbed(webhook, storeName, false, jobId)
                                elseif storeName == "Museum" then
                                    sendMuseumEmbed(webhook, storeName, false, jobId)
                                elseif storeName == "Rising_Bank" then
                                    sendRisingBankEmbed(webhook, storeName, false, jobId)
                                elseif storeName == "Crater_Bank" then
                                    sendCraterBankEmbed(webhook, storeName, false, jobId)
                                elseif storeName == "Tomb" then
                                    sendTombEmbed(webhook, storeName, false, jobId)
                                else
                                    sendJewelryStoreEmbed(webhook, storeName, false, jobId)
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
    return loggedStores, hasUnderRobbery
end

local function checkSpecialRobberies(jobId, loggedSpecials)
    local logged = loggedSpecials or {}
    -- Plane
    local timeLeft = getPlaneTimeLeft()
    if timeLeft and timeLeft > 0 and not logged.Plane then
        local webhook = getgenv().WebhookConfig.Webhooks["Cargo_Plane"]
        if webhook and webhook ~= "" then
            sendPlaneEmbed(webhook, timeLeft, jobId)
            logged.Plane = true
            sendLog(LogLevel.SUCCESS, "Plane Logged", "Time left: " .. timeLeft .. "s")
        end
    end
    -- Oil Rig
    if not logged.OilRig then
        local status = getOilRigStatus()
        if status == "open" or status == "robbery" then
            local webhook = getgenv().WebhookConfig.Webhooks["Oil_Rig"]
            if webhook and webhook ~= "" then
                if status == "robbery" then
                    local oilTime = getOilRigTimer()
                    if oilTime and oilTime > 60 then
                        sendOilRigEmbed(webhook, oilTime, jobId, true)
                        logged.OilRig = true
                        sendLog(LogLevel.SUCCESS, "Oil Rig Logged", "Oil Rig under robbery.")
                    elseif oilTime and oilTime <= 60 then
                        sendLog(LogLevel.INFO, "Oil Rig Skipped", "Timer too low: " .. oilTime .. "s")
                    else
                        sendOilRigEmbed(webhook, nil, jobId, false)
                        logged.OilRig = true
                        sendLog(LogLevel.SUCCESS, "Oil Rig Logged", "Oil Rig is open (no timer).")
                    end
                else -- open
                    sendOilRigEmbed(webhook, nil, jobId, false)
                    logged.OilRig = true
                    sendLog(LogLevel.SUCCESS, "Oil Rig Logged", "Oil Rig is open.")
                end
            end
        end
    end
    -- Bounty
    logged = checkBounties(jobId, logged)
    if logged.BountyData then
        local webhook = getgenv().WebhookConfig.Webhooks["Bounty"]
        if webhook and webhook ~= "" then
            sendBountyEmbed(webhook, logged.BountyData, jobId)
            logged.BountyData = nil
        end
    end
    return logged
end

-- =============================================
-- SERVER HOP (unchanged)
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
    if getgenv()._ServerHopSource then
        pcall(function() queue_on_teleport(getgenv()._ServerHopSource) end)
        task.wait(0.1)
    end

    if targetId then
        local failConnection
        failConnection = tp.TeleportInitFailed:Connect(function(plr, result, message)
            if plr == player then
                sendLog(LogLevel.WARNING, "Teleport Init Failed", message)
                local newVisited = loadVisitedServers()
                newVisited[targetId] = os.time()
                saveVisitedServers(newVisited)
                getgenv().VisitedServers = newVisited
                sendLog(LogLevel.HOP, "Falling back to random teleport")
                pcall(function() tp:Teleport(placeId, player) end)
                failConnection:Disconnect()
                getgenv().TeleportInProgress = false
            end
        end)

        sendLog(LogLevel.HOP, "Teleporting", "To " .. targetId)
        local ok, err = pcall(function()
            tp:TeleportToPlaceInstance(placeId, targetId, player)
        end)
        if not ok then
            sendLog(LogLevel.ERROR, "Teleport Failed", err)
            failConnection:Disconnect()
            getgenv().TeleportInProgress = false
            pcall(function() tp:Teleport(placeId, player) end)
        else
            task.wait(1)
            failConnection:Disconnect()
        end
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
    local sessionStart = os.time()
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

    loadAllMarkers()

    sendLog(LogLevel.INFO, "First Pass Started", "Scanning for open stores...")
    local loggedStores, loggedDrops, loggedSpecials = {}, {}, {}
    local hasUnderRobbery = false
    loggedStores, hasUnderRobbery = scanStores(player, jobId, loggedStores)
    loggedDrops = checkAirdrops(jobId, loggedDrops)
    loggedSpecials = checkSpecialRobberies(jobId, loggedSpecials)

    if hasUnderRobbery then
        sendLog(LogLevel.INFO, "Under‑robbery detected", "Waiting 30 seconds for new robberies...")
        task.wait(30)
        sendLog(LogLevel.INFO, "Second Pass Started", "Scanning for new robberies...")
        loggedStores, _ = scanStores(player, jobId, loggedStores)
        loggedDrops = checkAirdrops(jobId, loggedDrops)
        loggedSpecials = checkSpecialRobberies(jobId, loggedSpecials)
    else
        sendLog(LogLevel.INFO, "No under‑robbery", "Hopping immediately.")
    end

    getgenv().IsFinished = true

    local elapsed = os.time() - sessionStart
    local durationStr = (elapsed < 60) and string.format("%d seconds", elapsed) or string.format("%d minutes %d seconds", math.floor(elapsed/60), elapsed%60)
    sendPrivateLog(LogLevel.SUCCESS, "Cycle Complete", string.format("Scan finished in %s. Hopping now.", durationStr))
    sendLog(LogLevel.SUCCESS, "Cycle Complete", string.format("Scan finished in %s. Hopping now.", durationStr))

    hopToNewServer(player)
end)
