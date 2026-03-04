loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/webhook.lua"))()
loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/whitelist.lua"))()
loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/robberies.lua"))()
local BOT_VERSION = loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/version.lua"))()
local function getVisitedFilePath()
    local folder = "LeafBot_" .. game.PlaceId
    if not isfolder(folder) then makefolder(folder) end
    return folder .. "/visited_servers.json"
end
local function loadVisitedServers()
    local path = getVisitedFilePath()
    if isfile(path) then
        local success, data = pcall(function() return game:GetService("HttpService"):JSONDecode(readfile(path)) end)
        if success and type(data) == "table" then return data end
    end
    return {}
end
local function saveVisitedServers(data)
    local path = getVisitedFilePath()
    local success, json = pcall(function() return game:GetService("HttpService"):JSONEncode(data) end)
    if success then writefile(path, json) end
end
local function cleanupOldServers()
    local visited = loadVisitedServers()
    local currentTime = os.time()
    local changed = false
    for serverId, timestamp in pairs(visited) do
        if currentTime - timestamp > 300 then visited[serverId] = nil; changed = true end
    end
    if changed then saveVisitedServers(visited) end
    return visited
end
getgenv().VisitedServers = cleanupOldServers()
if not getgenv().ServerRegionCache then getgenv().ServerRegionCache = {} end
if getgenv().WhitelistCheck and not getgenv().WhitelistCheck() then warn("Not whitelisted.") return end
local AIRDROP_LOCATION_RADIUS = math.huge
local AIRDROP_COLORS = {
    { r = 147, g = 44,  b = 53,  label = "🔴 Red",   embedColor = 15158332 },
    { r = 148, g = 96,  b = 69,  label = "🟤 Brown",  embedColor = 10180422 },
    { r = 49,  g = 98,  b = 149, label = "🔵 Blue",   embedColor = 3447003  },
}
local LOCATIONS = { Tomb = nil, Casino = nil }
local function updateLocationPositions()
    local tomb = workspace:FindFirstChild("RobberyTomb")
    if tomb then
        local inner = tomb:FindFirstChild("Tomb")
        if inner then
            if inner:IsA("Model") then LOCATIONS.Tomb = inner:GetModelCFrame().Position
            elseif inner:FindFirstChildWhichIsA("BasePart") then LOCATIONS.Tomb = inner:FindFirstChildWhichIsA("BasePart").Position end
        end
    end
    local casino = workspace:FindFirstChild("Casino")
    if casino then
        if casino:IsA("Model") then LOCATIONS.Casino = casino:GetModelCFrame().Position
        elseif casino:FindFirstChildWhichIsA("BasePart") then LOCATIONS.Casino = casino:FindFirstChildWhichIsA("BasePart").Position end
    end
end
local MAX_PLAYERS = 5
local LogLevel = {
    INFO    = { label = "ℹ️ Info",       color = 5793266  },
    SUCCESS = { label = "✅ Success",    color = 3066993  },
    WARNING = { label = "⚠️ Warning",    color = 16776960 },
    ERROR   = { label = "❌ Error",      color = 15158332 },
    HOP     = { label = "🔀 Server Hop", color = 10181046 },
}
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
    if fields then for _, f in ipairs(fields) do table.insert(embedFields, f) end end
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
    local ok, encoded = pcall(function() return game:GetService("HttpService"):JSONEncode(embedPayload) end)
    if not ok then return end
    pcall(function() request({ Url = webhook, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = encoded }) end)
end
local function waitForLoad()
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    if not player then Players.PlayerAdded:Wait(); player = Players.LocalPlayer end
    if not player.Character then player.CharacterAdded:Wait() end
    repeat task.wait(0.3) until game:IsLoaded()
    task.wait(2)
    updateLocationPositions()
    return player
end
local function formatName(name) return name:gsub("_", " ") end
local function getTeamCounts()
    local counts = { Criminal = 0, Police = 0, Prisoner = 0 }
    local localPlayer = game:GetService("Players").LocalPlayer
    for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
        if player ~= localPlayer and player.Team then
            local teamName = player.Team.Name
            if counts[teamName] ~= nil then counts[teamName] = counts[teamName] + 1 end
        end
    end
    return counts
end
local function colorDistance(r1,g1,b1,r2,g2,b2) return math.sqrt((r1-r2)^2+(g1-g2)^2+(b1-b2)^2) end
local function matchAirdropColor(r,g,b)
    local best, bestDist = nil, math.huge
    for _, def in ipairs(AIRDROP_COLORS) do
        local dist = colorDistance(r,g,b, def.r,def.g,def.b)
        if dist < bestDist then bestDist = dist; best = def end
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
    local distToTomb = LOCATIONS.Tomb and (pos - LOCATIONS.Tomb).Magnitude or math.huge
    local distToCasino = LOCATIONS.Casino and (pos - LOCATIONS.Casino).Magnitude or math.huge
    if distToTomb < distToCasino then return "Dunes"
    elseif distToCasino < distToTomb then return "Cactus Valley"
    else return "Unknown Location" end
end
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
        if (pos - loc.cframe.Position).Magnitude <= POSITION_THRESHOLD then return loc.axis end
    end
    return nil
end
local function getCrownJewelCode()
    local casino = workspace:FindFirstChild("Casino")
    if not casino then sendLog(LogLevel.WARNING, "Crown Jewel Code", "Casino not found.") return nil end
    local robberyDoor = casino:FindFirstChild("RobberyDoor")
    if not robberyDoor then sendLog(LogLevel.WARNING, "Crown Jewel Code", "RobberyDoor not found.") return nil end
    local codesFolder = robberyDoor:FindFirstChild("Codes")
    if not codesFolder then sendLog(LogLevel.WARNING, "Crown Jewel Code", "Codes folder not found.") return nil end
    local digits, detectedAxis = {}, nil
    for _, v in ipairs(codesFolder:GetDescendants()) do
        if v:IsA("TextLabel") and v.Text ~= "" then
            local part = v.Parent.Parent
            local holder = v.Parent.Parent.Parent
            if part:IsA("BasePart") then
                if not detectedAxis then detectedAxis = getAxisForHolder(holder) end
                table.insert(digits, {text = v.Text, part = part})
            end
        end
    end
    if #digits == 0 then return nil end
    if not detectedAxis then sendLog(LogLevel.WARNING, "Crown Jewel Code", "Could not match holder, defaulting X axis.") detectedAxis = "X" end
    table.sort(digits, function(a,b)
        if detectedAxis == "X" then return a.part.Position.X < b.part.Position.X
        elseif detectedAxis == "Z" then return a.part.Position.Z < b.part.Position.Z
        elseif detectedAxis == "Y" then return a.part.Position.Y < b.part.Position.Y end
    end)
    local code = ""
    for _, d in ipairs(digits) do code = code .. d.text end
    return code
end
local function parseTimerString(timerStr)
    if not timerStr then return nil end
    local minutes, seconds = timerStr:match("(%d+):(%d+)")
    if minutes and seconds then return tonumber(minutes) * 60 + tonumber(seconds) end
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
local PLANE_SPAWN = Vector3.new(3727.843, 594.45, -509.572)
local PLANE_TURN = Vector3.new(-3145.715, 333.56, 2331.847)
local AIRPORT = Vector3.new(-0.208, -54.296, -0.231)
local APPROACH_RADIUS = 2000
local function isPlaneActive()
    local plane = workspace:FindFirstChild("Plane")
    if not plane then return false end
    local pos
    if plane:IsA("Model") then
        local primary = plane.PrimaryPart
        if primary then pos = primary.Position else return false end
    else
        pos = plane.Position
    end
    local distToAirport = (pos - AIRPORT).Magnitude
    local distToTurn = (pos - PLANE_TURN).Magnitude
    return distToAirport <= APPROACH_RADIUS and distToAirport < distToTurn
end
local function getPlaneETA()
    local plane = workspace:FindFirstChild("Plane")
    if not plane then return nil end
    local pos, velocity
    if plane:IsA("Model") then
        local primary = plane.PrimaryPart
        if primary then
            pos = primary.Position
            velocity = primary.Velocity
        else
            return nil
        end
    else
        pos = plane.Position
        velocity = plane.Velocity
    end
    if not pos or not velocity then return nil end
    local speed = velocity.Magnitude
    if speed < 0.1 then return nil end
    local distToAirport = (pos - AIRPORT).Magnitude
    local etaSeconds = distToAirport / speed
    return etaSeconds
end
local CARGO_START = Vector3.new(-374.895, -1.093, -6000.34)
local CARGO_END = Vector3.new(-1659.279, 31.59, 268.128)
local PASSENGER_START = CARGO_END
local PASSENGER_END = CARGO_START
local TRAIN_SPEED = 50
local function getTrainTimes()
    local trains = workspace:FindFirstChild("Trains")
    if not trains then return nil, nil end
    local cargoTime, passengerTime = nil, nil
    for _, loco in ipairs(trains:GetChildren()) do
        if loco.Name:find("LocomotiveFront") then
            local model = loco:FindFirstChild("Model")
            if model then
                local body = model:FindFirstChild("Body")
                if body and body:IsA("BasePart") then
                    local color = body.Color
                    local r = math.round(color.R * 255)
                    local g = math.round(color.G * 255)
                    local b = math.round(color.B * 255)
                    local pos = body.Position
                    -- Cargo color: (255,144,78)
                    if r == 255 and g == 144 and b == 78 then
                        local totalPath = (CARGO_START - CARGO_END).Magnitude * 1.2
                        local traveled = (pos - CARGO_START).Magnitude
                        local remaining = math.max(totalPath - traveled, 0)
                        cargoTime = remaining / TRAIN_SPEED
                    else
                        -- Passenger (any other color)
                        local totalPath = (PASSENGER_START - PASSENGER_END).Magnitude * 1.2
                        local traveled = (pos - PASSENGER_START).Magnitude
                        local remaining = math.max(totalPath - traveled, 0)
                        passengerTime = remaining / TRAIN_SPEED
                    end
                end
            end
        end
    end
    return cargoTime, passengerTime
end
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
local function sendDiscordEmbed(webhookUrl, storeName, status, jobId, timerSeconds)
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
    local displayName = formatName(storeName)
    local roleId = getgenv().WebhookConfig.Roles[storeName]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
    local imageUrl = getgenv().WebhookConfig.Images[storeName]
    local fields = {
        { name = "📍 Status",      value = statusText,          inline = true  },
        { name = "👥 Total Players", value = tostring(totalPlayers), inline = true  },
        { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
        { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
        { name = "🚔 Police",       value = tostring(police),    inline = true  },
        { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
    }
    if timerSeconds then
        table.insert(fields, 4, { name = "⏳ Closes in", value = "<t:" .. (now + timerSeconds) .. ":R>", inline = true })
    end
    local embed = {
        color = color,
        fields = fields,
        footer = { text = "Leaf Logger " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local embedPayload = { embeds = { embed } }
    if roleMention then embedPayload.content = roleMention end
    local ok, encoded = pcall(function() return game:GetService("HttpService"):JSONEncode(embedPayload) end)
    if not ok then return end
    pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = encoded }) end)
end
local function sendAirdropEmbed(webhookUrl, drop, colorDef, locationName, jobId, timerText)
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
    local imageUrl = roleKey and getgenv().WebhookConfig.Images[roleKey]
    local embed = {
        color = colorDef.embedColor,
        fields = {
            { name = "🎨 Drop Type",             value = colorDef.label,   inline = true  },
            { name = "📍 Location",              value = locationName,     inline = true  },
            { name = "⏳ Time Left",             value = timerText or "N/A", inline = true },
            { name = "👥 Total Players",         value = tostring(totalPlayers), inline = true },
            { name = "🔗 Join Server",           value = "[Click to Join](" .. joinLink .. ")", inline = false },
            { name = "🦹 Criminals",             value = tostring(crimAndPris), inline = false },
            { name = "🚔 Police",                value = tostring(police), inline = true  },
            { name = "⏱️ Logged",                value = "<t:" .. now .. ":R>", inline = true },
        },
        footer = { text = "Leaf Logger " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local embedPayload = { embeds = { embed } }
    if roleMention then embedPayload.content = roleMention end
    local ok, encoded = pcall(function() return game:GetService("HttpService"):JSONEncode(embedPayload) end)
    if not ok then return end
    pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = encoded }) end)
end
local function sendPlaneEmbed(webhookUrl, jobId)
    local now = os.time()
    local joinLink = getJoinLink(jobId)
    local teamCounts = getTeamCounts()
    local criminals = teamCounts.Criminal
    local police = teamCounts.Police
    local prisoners = teamCounts.Prisoner
    local crimAndPris = criminals + prisoners
    local totalPlayers = crimAndPris + police
    local roleId = getgenv().WebhookConfig.Roles["Cargo_Plane"]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
    local imageUrl = getgenv().WebhookConfig.Images["Cargo_Plane"]
    local eta = getPlaneETA()
    local fields = {
        { name = "👥 Total Players", value = tostring(totalPlayers), inline = true },
        { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
        { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
        { name = "🚔 Police",       value = tostring(police),    inline = true  },
        { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
    }
    if eta then
        table.insert(fields, 1, { name = "✈️ Arrives in", value = "<t:" .. (now + eta) .. ":R>", inline = true })
    else
        table.insert(fields, 1, { name = "✈️ Arrives in", value = "Unknown", inline = true })
    end
    local embed = {
        color = 3447003,
        fields = fields,
        footer = { text = "Leaf Logger " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local embedPayload = { embeds = { embed } }
    if roleMention then embedPayload.content = roleMention end
    local ok, encoded = pcall(function() return game:GetService("HttpService"):JSONEncode(embedPayload) end)
    if not ok then return end
    pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = encoded }) end)
end
local function sendTrainEmbed(webhookUrl, trainType, timeRemaining, jobId)
    local now = os.time()
    local joinLink = getJoinLink(jobId)
    local teamCounts = getTeamCounts()
    local criminals = teamCounts.Criminal
    local police = teamCounts.Police
    local prisoners = teamCounts.Prisoner
    local crimAndPris = criminals + prisoners
    local totalPlayers = crimAndPris + police
    local roleKey = (trainType == "cargo") and "Cargo_Train" or "Passenger_Train"
    local roleId = getgenv().WebhookConfig.Roles[roleKey]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
    local imageUrl = getgenv().WebhookConfig.Images[roleKey]
    local title = (trainType == "cargo") and "🚂 Cargo Train Robbery!" or "🚆 Passenger Train Robbery!"
    local fields = {
        { name = "⏳ Closes in",   value = "<t:" .. (now + timeRemaining) .. ":R>", inline = true },
        { name = "👥 Total Players", value = tostring(totalPlayers), inline = true  },
        { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
        { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
        { name = "🚔 Police",       value = tostring(police),    inline = true  },
        { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
    }
    local embed = {
        color = (trainType == "cargo") and 15105570 or 3066993,
        fields = fields,
        footer = { text = "Leaf Logger " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local embedPayload = { embeds = { embed } }
    if roleMention then embedPayload.content = roleMention end
    local ok, encoded = pcall(function() return game:GetService("HttpService"):JSONEncode(embedPayload) end)
    if not ok then return end
    pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = encoded }) end)
end
local function sendOilRigEmbed(webhookUrl, timeRemaining, jobId)
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
    local fields = {
        { name = "⏳ Closes in",   value = "<t:" .. (now + timeRemaining) .. ":R>", inline = true },
        { name = "👥 Total Players", value = tostring(totalPlayers), inline = true  },
        { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
        { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
        { name = "🚔 Police",       value = tostring(police),    inline = true  },
        { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
    }
    local embed = {
        color = 16753920,
        fields = fields,
        footer = { text = "Leaf Logger " .. BOT_VERSION },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    if imageUrl then embed.image = { url = imageUrl } end
    local embedPayload = { embeds = { embed } }
    if roleMention then embedPayload.content = roleMention end
    local ok, encoded = pcall(function() return game:GetService("HttpService"):JSONEncode(embedPayload) end)
    if not ok then return end
    pcall(function() request({ Url = webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = encoded }) end)
end
local function getGameTimeText()
    local success, label = pcall(function() return game:GetService("Players").LocalPlayer.PlayerGui.AppUI.Buttons.Minimap.Time.Time end)
    if success and label and label:IsA("TextLabel") then return label.Text end
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
    local status, displayStatus
    if totalMinutes >= 1080 or totalMinutes < 15 then
        status = "open"; displayStatus = "Open"
    elseif totalMinutes >= 960 and totalMinutes < 1080 then
        status = "opening_soon"; displayStatus = "Opening Soon"
    elseif totalMinutes >= 15 and totalMinutes < 120 then
        status = "closing_soon"; displayStatus = "Closing Soon"
    else
        status = "closed"; displayStatus = "Closed"
    end
    return status, displayStatus, timeText
end
local function checkAirdrops(jobId, loggedDrops)
    local webhook = getgenv().WebhookConfig.Webhooks.Airdrop
    if not webhook or webhook == "" then
        sendLog(LogLevel.WARNING, "Airdrop Webhook Missing", "No webhook.")
        return loggedDrops
    end
    if getgenv().RobberyToggles and not getgenv().RobberyToggles.Airdrop then return loggedDrops end
    local found, logged = 0, 0
    local candidates = {}
    for _, drop in ipairs(workspace:GetChildren()) do
        if drop.Name == "Drop" and drop:IsA("Model") then table.insert(candidates, drop) end
    end
    if #candidates == 0 then
        sendLog(LogLevel.WARNING, "Airdrop Scan", "No 'Drop' models.")
        return loggedDrops
    end
    for _, drop in ipairs(candidates) do
        if loggedDrops[drop] then continue end
        found = found + 1
        sendLog(LogLevel.INFO, "Airdrop Candidate", "Examining drop: " .. drop:GetFullName())
        local wallPart = nil
        local walls = drop:FindFirstChild("Walls") or drop:FindFirstChild("walls")
        if walls then wallPart = walls:FindFirstChild("Wall") or walls:FindFirstChild("wall") or walls:FindFirstChildWhichIsA("BasePart", true) end
        if not wallPart then
            for _, child in ipairs(drop:GetChildren()) do
                if child:IsA("BasePart") and child.Name:lower() == "wall" then wallPart = child; break end
            end
        end
        if not wallPart then
            local parts = {}
            for _, d in ipairs(drop:GetDescendants()) do if d:IsA("BasePart") then table.insert(parts, d) end end
            if #parts == 1 then wallPart = parts[1] elseif #parts > 1 then wallPart = parts[1] end
        end
        if not wallPart then sendLog(LogLevel.WARNING, "Airdrop — No Wall Part", "Skipping.") continue end
        local col = wallPart.Color
        local r,g,b = math.round(col.R*255), math.round(col.G*255), math.round(col.B*255)
        local colorDef = matchAirdropColor(r,g,b)
        if not colorDef then sendLog(LogLevel.WARNING, "Airdrop — Unknown Color", string.format("RGB: %d,%d,%d",r,g,b)) continue end
        local npcs = drop:FindFirstChild("NPCs")
        if npcs and #npcs:GetChildren() > 0 then sendLog(LogLevel.INFO, "Airdrop — Opened", "Has NPCs, skipping.") continue end
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
            if new and new ~= initial then timerText = new else timerText = "Unopened" end
        else
            timerText = "No timer"
        end
        local pos = getDropPosition(drop)
        local locName = pos and getNearestLocation(pos) or "Unknown Location"
        sendAirdropEmbed(webhook, drop, colorDef, locName, jobId, timerText)
        loggedDrops[drop] = true
        logged = logged + 1
        sendLog(LogLevel.SUCCESS, "Airdrop Logged", "Logged.", {
            {name="Type",value=colorDef.label},
            {name="Location",value=locName},
            {name="Timer",value=timerText}
        })
    end
    if found > 0 then
        sendLog(LogLevel.INFO, "Airdrop Scan", string.format("Found %d, Logged %d", found, logged))
    end
    return loggedDrops
end
local function scanStores(player, jobId, loggedStores)
    local pg = player and player:FindFirstChild("PlayerGui")
    if not pg then sendLog(LogLevel.ERROR, "Store Scan", "PlayerGui not found.") return loggedStores end
    local wm = pg:FindFirstChild("WorldMarkersGui")
    if not wm then sendLog(LogLevel.ERROR, "Store Scan", "WorldMarkersGui not found.") return loggedStores end
    local openCount, robberyCount, closedCount, missedCount = 0,0,0,0
    for storeName, iconId in pairs(getgenv().WebhookConfig.Icons) do
        local display = formatName(storeName)
        -- Skip trains entirely; they are handled by special robberies
        if storeName == "Cargo_Train" or storeName == "Passenger_Train" then
            sendLog(LogLevel.INFO, "Train Skipped", "Trains handled by special robberies.")
            continue
        end
        local found = false
        for _, img in ipairs(wm:GetDescendants()) do
            if img:IsA("ImageLabel") and img.Image == iconId then
                found = true
                local parent = img.Parent
                if parent and parent:IsA("ImageLabel") then
                    local col = parent.ImageColor3
                    local r,g,b = math.round(col.R*255), math.round(col.G*255), math.round(col.B*255)
                    local webhook = getgenv().WebhookConfig.Webhooks[storeName]
                    local isOpen = (r==0 and g==255 and b==0)
                    local isClosed = (r==255 and g==0 and b==0)
                    local isRobbery = not isOpen and not isClosed
                    if isOpen then openCount = openCount + 1
                    elseif isClosed then closedCount = closedCount + 1
                    else robberyCount = robberyCount + 1 end
                    if storeName == "Crown_Jewel" then
                        if getgenv().RobberyToggles and not getgenv().RobberyToggles[storeName] then break end
                        if not (isOpen or isRobbery) then break end
                        if loggedStores[storeName] then break end
                        local code = getCrownJewelCode() or "N/A"
                        local timer = getCrownJewelTimer()
                        -- Skip if timer <= 60 seconds (1 minute)
                        if timer and timer <= 60 then
                            sendLog(LogLevel.INFO, "Crown Jewel Skipped", "Timer too low: " .. timer .. "s")
                            break
                        end
                        local now = os.time()
                        local joinLink = getJoinLink(jobId)
                        local tc = getTeamCounts()
                        local crim = tc.Criminal; local pol = tc.Police; local pris = tc.Prisoner
                        local crimAndPris = crim + pris; local total = crimAndPris + pol
                        local statusText = isOpen and "Open" or "Under Robbery"
                        local roleId = getgenv().WebhookConfig.Roles["Crown_Jewel"]
                        local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
                        local imageUrl = getgenv().WebhookConfig.Images["Crown_Jewel"]
                        local fields = {
                            { name = "👥 Total Players", value = tostring(total),   inline = true  },
                            { name = "🔢 Code",        value = code,                inline = true  },
                            { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
                            { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
                            { name = "🚔 Police",       value = tostring(pol),      inline = true  },
                            { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
                        }
                        if timer then
                            table.insert(fields, 1, { name = "⏳ Closes in", value = "<t:" .. (now + timer) .. ":R>", inline = true })
                        end
                        local embed = {
                            color = isOpen and 3066993 or 15105570,
                            fields = fields,
                            footer = { text = "Leaf Logger " .. BOT_VERSION },
                            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                        }
                        if imageUrl then embed.image = { url = imageUrl } end
                        local embedPayload = { embeds = { embed } }
                        if roleMention then embedPayload.content = roleMention end
                        local ok, encoded = pcall(function() return game:GetService("HttpService"):JSONEncode(embedPayload) end)
                        if ok then
                            pcall(function() request({ Url = webhook, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = encoded }) end)
                            sendLog(LogLevel.SUCCESS, "Crown Jewel Logged", display .. " " .. statusText .. " — Code: " .. code, {{name="Code",value=code}})
                            loggedStores[storeName] = true
                        end
                    elseif storeName == "Mansion" then
                        if getgenv().RobberyToggles and not getgenv().RobberyToggles.Mansion then break end
                        if loggedStores[storeName] then break end
                        if isRobbery then sendLog(LogLevel.INFO, "Mansion Robbery Skipped", "Mansion is under robbery, not logging.") break end
                        if not isOpen then break end
                        local status, displayStatus, timeText = getMansionStatus()
                        if not status then sendLog(LogLevel.WARNING, "Mansion Time Missing", "Could not determine mansion status.") break end
                        if status == "closed" then break end
                        local now = os.time()
                        local joinLink = getJoinLink(jobId)
                        local tc = getTeamCounts()
                        local crim = tc.Criminal; local pol = tc.Police; local pris = tc.Prisoner
                        local crimAndPris = crim + pris; local total = crimAndPris + pol
                        local roleId = getgenv().WebhookConfig.Roles["Mansion"]
                        local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
                        local imageUrl = getgenv().WebhookConfig.Images["Mansion"]
                        local embed = {
                            color = status == "open" and 3066993 or (status == "opening_soon" and 16753920 or 15158332),
                            fields = {
                                { name = "⏰ Game Time",   value = timeText,            inline = true },
                                { name = "📍 Status",      value = displayStatus,       inline = true },
                                { name = "👥 Total Players", value = tostring(total),   inline = true },
                                { name = "🔗 Join Server",  value = "[Click to Join](" .. joinLink .. ")", inline = false },
                                { name = "🏃 Criminals",    value = tostring(crimAndPris), inline = true },
                                { name = "🚔 Police",       value = tostring(pol),      inline = true  },
                                { name = "⏱️ Logged",       value = "<t:" .. now .. ":R>", inline = true },
                            },
                            footer = { text = "Leaf Logger " .. BOT_VERSION },
                            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                        }
                        if imageUrl then embed.image = { url = imageUrl } end
                        local embedPayload = { embeds = { embed } }
                        if roleMention then embedPayload.content = roleMention end
                        local ok, encoded = pcall(function() return game:GetService("HttpService"):JSONEncode(embedPayload) end)
                        if ok then
                            pcall(function() request({ Url = webhook, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = encoded }) end)
                            sendLog(LogLevel.SUCCESS, "Mansion Logged", "Mansion " .. displayStatus .. " at " .. timeText, {{name="Status",value=displayStatus}})
                            loggedStores[storeName] = true
                        end
                    else
                        if loggedStores[storeName] then break end
                        if isOpen then
                            if webhook and webhook ~= "" then
                                if getgenv().RobberyToggles and getgenv().RobberyToggles[storeName] then
                                    sendDiscordEmbed(webhook, storeName, "open", jobId)
                                    sendLog(LogLevel.SUCCESS, "Store Open", display .. " open.", {{name="Store",value=display}})
                                    loggedStores[storeName] = true
                                else
                                    sendLog(LogLevel.INFO, "Store Open — Toggled Off", display .. " open but disabled.")
                                end
                            else
                                sendLog(LogLevel.WARNING, "Store Open — No Webhook", display .. " open but no webhook.")
                            end
                        elseif isRobbery then
                            if storeName == "Cargo_Plane" then
                                sendLog(LogLevel.INFO, "Cargo Plane Robbery Skipped", "Cargo Plane robbery not logged.")
                            elseif storeName == "Oil_Rig" then
                                -- Skip Oil Rig; it will be logged by special robberies with timer
                                sendLog(LogLevel.INFO, "Oil Rig Robbery", "Skipping store scan, will be logged by special robberies.")
                            elseif webhook and webhook ~= "" then
                                if getgenv().RobberyToggles and getgenv().RobberyToggles[storeName] then
                                    sendDiscordEmbed(webhook, storeName, "robbery", jobId)
                                    sendLog(LogLevel.SUCCESS, "Robbery Logged", display .. " under robbery.", {{name="Store",value=display}})
                                    loggedStores[storeName] = true
                                else
                                    sendLog(LogLevel.INFO, "Robbery — Toggled Off", display .. " robbery disabled.")
                                end
                            else
                                sendLog(LogLevel.WARNING, "Robbery — No Webhook", display .. " robbery but no webhook.")
                            end
                        end
                    end
                else missedCount = missedCount + 1 end
                break
            end
        end
        if not found then missedCount = missedCount + 1 end
    end
    sendLog(LogLevel.INFO, "Store Scan", "Completed.", {
        {name="✅ Open",value=openCount},
        {name="🔴 Robbery",value=robberyCount},
        {name="⚫ Closed",value=closedCount},
        {name="⚠️ Missed",value=missedCount}
    })
    return loggedStores
end
local function checkSpecialRobberies(jobId, loggedSpecials)
    local logged = loggedSpecials or {}
    -- Trains (individual embeds)
    local cargoTime, passengerTime = getTrainTimes()
    if cargoTime and not logged.CargoTrain then
        local webhook = getgenv().WebhookConfig.Webhooks["Cargo_Train"]
        if webhook and webhook ~= "" then
            sendTrainEmbed(webhook, "cargo", cargoTime, jobId)
            logged.CargoTrain = true
            sendLog(LogLevel.SUCCESS, "Cargo Train Logged", "Cargo train active.")
        end
    end
    if passengerTime and not logged.PassengerTrain then
        local webhook = getgenv().WebhookConfig.Webhooks["Passenger_Train"]
        if webhook and webhook ~= "" then
            sendTrainEmbed(webhook, "passenger", passengerTime, jobId)
            logged.PassengerTrain = true
            sendLog(LogLevel.SUCCESS, "Passenger Train Logged", "Passenger train active.")
        end
    end
    if isPlaneActive() and not logged.Plane then
        local webhook = getgenv().WebhookConfig.Webhooks["Cargo_Plane"]
        if webhook and webhook ~= "" then
            sendPlaneEmbed(webhook, jobId)
            logged.Plane = true
            sendLog(LogLevel.SUCCESS, "Plane Logged", "Cargo plane is on approach.")
        end
    end
    local oilTime = getOilRigTimer()
    -- Skip if oilTime <= 60 seconds
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
    return logged
end
local function getServerIP(placeId, serverId)
    local success, response = pcall(function()
        return request({
            Url = "https://gamejoin.roblox.com/v1/join-game-instance",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json", ["User-Agent"] = "Roblox/WinInet" },
            Body = game:GetService("HttpService"):JSONEncode({ placeId = placeId, gameId = serverId, isTeleport = false, gameJoinAttemptId = serverId })
        })
    end)
    if not success or not response or response.StatusCode ~= 200 then return nil end
    local ok, data = pcall(function() return game:GetService("HttpService"):JSONDecode(response.Body) end)
    if not ok then return nil end
    if data.joinScript and data.joinScript.MachineAddress then return data.joinScript.MachineAddress end
    if data.joinScript and data.joinScript.UdmuxEndpoints and #data.joinScript.UdmuxEndpoints > 0 then return data.joinScript.UdmuxEndpoints[1].Address end
    return nil
end
local function isUSAServer(ipAddress)
    local prefixes = {"104.", "128.116.", "162.", "199.", "66.", "72.", "192."}
    for _, p in ipairs(prefixes) do if ipAddress:sub(1, #p) == p then return true end end
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
        if not ok or not result or not result.data then sendLog(LogLevel.ERROR, "Server List Fetch Failed", "Failed to retrieve server list from Roblox API.") break end
        for _, server in ipairs(result.data) do
            local isCurrent = server.id == currentJobId
            local isVisited = visited[server.id] == true
            local playing = server.playing or 0
            local maxPlayers = server.maxPlayers or 0
            local hasSpace = playing < maxPlayers
            local underLimit = playing <= MAX_PLAYERS
            if not isCurrent and not isVisited and hasSpace and underLimit then table.insert(allServers, server) end
        end
        if #allServers > 0 then break end
        cursor = result.nextPageCursor
    until not cursor
    if #allServers == 0 then sendLog(LogLevel.WARNING, "No Valid Servers", "No servers found under player limit.") return nil end
    table.sort(allServers, function(a, b) return (a.playing or 0) < (b.playing or 0) end)
    local nonUSA = {}
    for _, s in ipairs(allServers) do
        local region = getServerRegion(placeId, s.id)
        if region == "US" then sendLog(LogLevel.INFO, "Skipping USA Server", "Server " .. s.id .. " is in USA.")
        else table.insert(nonUSA, s) end
        task.wait(0.1)
    end
    if #nonUSA == 0 then sendLog(LogLevel.WARNING, "No Non‑USA Servers", "All candidate servers are in USA. Falling back to any server.") nonUSA = allServers end
    local best = nonUSA[1]
    sendLog(LogLevel.HOP, "Target Server Found", "Identified best server to hop to.", {
        { name = "Target ID", value = best.id, inline = false },
        { name = "Players",   value = tostring(best.playing) .. "/" .. tostring(best.maxPlayers), inline = true },
    })
    return best.id
end
local function hasS5nniPlayer()
    local localPlayer = game:GetService("Players").LocalPlayer
    for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
        if plr ~= localPlayer and plr.Name:lower():find("s5nni") then return true end
    end
    return false
end
local function hopToNewServer(player)
    if getgenv().TeleportInProgress then sendLog(LogLevel.WARNING, "Teleport Already in Progress", "Skipping duplicate teleport request.") return end
    getgenv().TeleportInProgress = true
    local placeId = game.PlaceId
    local oldJobId = game.JobId
    local visited = loadVisitedServers()
    visited[oldJobId] = os.time()
    saveVisitedServers(visited)
    getgenv().VisitedServers = visited
    local targetJobId = getTargetServer(placeId, oldJobId)
    local TeleportService = game:GetService("TeleportService")
    pcall(function() clear_teleport_queue() end)
    pcall(function() queue_on_teleport(getgenv()._ServerHopSource) end)
    if targetJobId then
        sendLog(LogLevel.HOP, "Teleporting", "Attempting teleport to target server.", { { name = "Target", value = targetJobId, inline = false } })
        local success, err = pcall(function() TeleportService:TeleportToPlaceInstance(placeId, targetJobId, player) end)
        if not success then
            sendLog(LogLevel.ERROR, "Teleport Failed", "TeleportToPlaceInstance failed. Falling back to random server.", { { name = "Error", value = tostring(err), inline = false } })
            getgenv().TeleportInProgress = false
            pcall(function() TeleportService:Teleport(placeId, player) end)
            return
        end
        task.spawn(function()
            task.wait(30)
            if game.JobId == oldJobId then
                sendLog(LogLevel.WARNING, "Teleport Stuck", "No server change after 30 seconds. Re‑attempting hop.")
                getgenv().TeleportInProgress = false
                hopToNewServer(player)
            else
                getgenv().TeleportInProgress = false
            end
        end)
    else
        sendLog(LogLevel.WARNING, "No Target Server", "No valid server found. Falling back to random server teleport.")
        getgenv().TeleportInProgress = false
        pcall(function() TeleportService:Teleport(placeId, player) end)
    end
end
if not getgenv()._ServerHopSource then
    getgenv()._ServerHopSource = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/main.lua"))()]]
end
pcall(function()
    local player = waitForLoad()
    local currentJobId = game.JobId
    sendLog(LogLevel.INFO, "Bot Started", "Script loaded and game is ready.", { { name = "Server ID", value = currentJobId, inline = false } })
    if hasS5nniPlayer() then
        sendLog(LogLevel.INFO, "S5nni Player Detected", "Hopping to another server without scanning.")
        hopToNewServer(player)
        return
    end
    local visited = loadVisitedServers()
    if visited[currentJobId] then
        local timeSince = os.time() - visited[currentJobId]
        if timeSince < 300 then
            sendLog(LogLevel.INFO, "Server Recently Visited", string.format("This server was visited %d seconds ago. Hopping immediately.", timeSince))
            hopToNewServer(player)
            return
        else
            visited[currentJobId] = nil
            saveVisitedServers(visited)
        end
    end
    if getgenv().ServerId == currentJobId then
        sendLog(LogLevel.WARNING, "Duplicate Server Detected", "Current server matches stored ServerId. Skipping scan and hopping immediately.", { { name = "Server ID", value = currentJobId, inline = false } })
        hopToNewServer(player)
        return
    end
    getgenv().ServerId = currentJobId
    sendLog(LogLevel.INFO, "First Pass Started", "Scanning for open stores...")
    local loggedStores = {}
    local loggedDrops = {}
    local loggedSpecials = {}
    loggedStores = scanStores(player, currentJobId, loggedStores)
    loggedDrops = checkAirdrops(currentJobId, loggedDrops)
    loggedSpecials = checkSpecialRobberies(currentJobId, loggedSpecials)
    sendLog(LogLevel.INFO, "Waiting Period", "Waiting 15 seconds for robberies to start...")
    task.wait(15)
    sendLog(LogLevel.INFO, "Second Pass Started", "Scanning for robberies that started during wait...")
    updateLocationPositions()
    loggedStores = scanStores(player, currentJobId, loggedStores)
    loggedDrops = checkAirdrops(currentJobId, loggedDrops)
    loggedSpecials = checkSpecialRobberies(currentJobId, loggedSpecials)
    getgenv().IsFinished = true
    sendLog(LogLevel.SUCCESS, "Cycle Complete", "All scans finished. IsFinished set. Hopping in 2 seconds.")
    task.wait(2)
    hopToNewServer(player)
end)
