loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/webhook.lua"))()
loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/whitelist.lua"))()
loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/robberies.lua"))()
local ServerHop = loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/serverhop.lua"))()
if not getgenv().VisitedServers then getgenv().VisitedServers = {} end
if not getgenv().ServerRegionCache then getgenv().ServerRegionCache = {} end
if getgenv().WhitelistCheck and not getgenv().WhitelistCheck() then warn("Not whitelisted.") return end
local AIRDROP_LOCATION_RADIUS = 500
local AIRDROP_COLORS = {
    { r = 147, g = 44,  b = 53,  label = "🔴 Red",   embedColor = 15158332 },
    { r = 148, g = 96,  b = 69,  label = "🟤 Brown",  embedColor = 10180422 },
    { r = 49,  g = 98,  b = 149, label = "🔵 Blue",   embedColor = 3447003  },
}
local AIRDROP_LOCATIONS = {
    { name = "Dunes", getPosition = function()
        local tomb = workspace:FindFirstChild("RobberyTomb")
        if tomb then
            local inner = tomb:FindFirstChild("Tomb")
            if inner and inner:IsA("Model") then return inner:GetModelCFrame().Position
            elseif inner and inner:FindFirstChildWhichIsA("BasePart") then return inner:FindFirstChildWhichIsA("BasePart").Position end
        end return nil end },
    { name = "Cactus Valley", getPosition = function()
        local casino = workspace:FindFirstChild("Casino")
        if casino then
            if casino:IsA("Model") then return casino:GetModelCFrame().Position
            elseif casino:FindFirstChildWhichIsA("BasePart") then return casino:FindFirstChildWhichIsA("BasePart").Position end
        end return nil end },
}
local LogLevel = {
    INFO    = { label = "ℹ️ Info",       color = 5793266  },
    SUCCESS = { label = "✅ Success",    color = 3066993  },
    WARNING = { label = "⚠️ Warning",    color = 16776960 },
    ERROR   = { label = "❌ Error",      color = 15158332 },
    HOP     = { label = "🔀 Server Hop", color = 10181046 },
}
local function getJoinLink(jobId)
    local placeId = game.PlaceId
    return "https://s5nni.github.io/Leaf-Joiner/?placeId=" .. placeId .. "&jobId=" .. jobId:gsub("%W", function(c) return string.format("%%%02X", string.byte(c)) end)
end
local function sendLog(level, title, description, fields)
    local webhook = getgenv().WebhookConfig.Webhooks.Log
    if not webhook or webhook == "" then return end
    local player = game:GetService("Players").LocalPlayer
    local username = player and player.Name or "Unknown"
    local jobId = game.JobId or "N/A"
    local fieldsJson = ""
    if fields then
        for i, f in ipairs(fields) do
            if i > 1 then fieldsJson = fieldsJson .. "," end
            fieldsJson = fieldsJson .. string.format('{"name":"%s","value":"%s","inline":%s}', f.name, f.value, tostring(f.inline))
        end
    end
    local embedJson = string.format('{"title":"%s  |  %s","description":"%s","color":%d,"fields":[%s],"footer":{"text":"ServerHop Bot"},"timestamp":"%s"}',
        level.label, title, description or "", level.color, fieldsJson, os.date("!%Y-%m-%dT%H:%M:%SZ"))
    local payload = string.format('{"embeds":[%s]}', embedJson)
    pcall(function() request({Url = webhook, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = payload}) end)
end
local function waitForLoad()
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    if not player then Players.PlayerAdded:Wait() player = Players.LocalPlayer end
    if not player.Character then player.CharacterAdded:Wait() end
    repeat task.wait(0.3) until game:IsLoaded()
    task.wait(2)
    return player
end
local function formatName(name) return name:gsub("_", " ") end
local function getTeamCounts()
    local counts = { Criminal = 0, Police = 0, Prisoner = 0 }
    for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
        if plr.Team and counts[plr.Team.Name] then counts[plr.Team.Name] = counts[plr.Team.Name] + 1 end
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
    local best, bestDist = nil, math.huge
    for _, loc in ipairs(AIRDROP_LOCATIONS) do
        local ref = loc.getPosition()
        if ref then
            local d = (pos - ref).Magnitude
            if d < bestDist then bestDist = d; best = loc.name end
        end
    end
    if best and bestDist <= AIRDROP_LOCATION_RADIUS then return best end
    return "Unknown Location"
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
local function sendDiscordEmbed(webhookUrl, storeName, status, jobId)
    local now = os.time()
    local joinLink = getJoinLink(jobId)
    local tc = getTeamCounts()
    local crim = tc.Criminal; local pol = tc.Police; local pris = tc.Prisoner
    local crimAndPris = crim + pris; local total = crimAndPris + pol
    local isOpen = status == "open"
    local color = isOpen and 3066993 or 15105570
    local statusText = isOpen and "Open" or "Under Robbery"
    local title = isOpen and (storeName .. " is Open!") or (storeName .. " is Under Robbery!")
    local roleId = getgenv().WebhookConfig.Roles[storeName]
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
    local imageUrl = getgenv().WebhookConfig.Images[storeName]
    local fields = string.format('[{"name":"📍 Status","value":"%s","inline":true},{"name":"👥 Total Players","value":"%s","inline":true},{"name":"🔗 Join Server","value":"[Click to Join](%s)","inline":false},{"name":"🏃 Criminals","value":"%s","inline":true},{"name":"🚔 Police","value":"%s","inline":true},{"name":"⏱️ Logged","value":"<t:%d:R>","inline":true}]',
        statusText, total, joinLink, crimAndPris, pol, now)
    local embed = string.format('{"title":"%s","color":%d,"fields":%s,"footer":{"text":"Server ID: %s"},"timestamp":"%s"}', title, color, fields, jobId, os.date("!%Y-%m-%dT%H:%M:%SZ"))
    if imageUrl then embed = embed:sub(1,-2) .. ',"image":{"url":"' .. imageUrl .. '"}}' end
    local payload = '{"embeds":[' .. embed .. ']}'
    if roleMention then payload = '{"content":"' .. roleMention .. '","embeds":[' .. embed .. ']}' end
    pcall(function() request({Url = webhookUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = payload}) end)
end
local function sendAirdropEmbed(webhookUrl, drop, colorDef, locationName, jobId, timerText)
    local now = os.time()
    local joinLink = getJoinLink(jobId)
    local tc = getTeamCounts()
    local crim = tc.Criminal; local pol = tc.Police; local pris = tc.Prisoner
    local crimAndPris = crim + pris; local total = crimAndPris + pol
    local roleKey = colorDef.label:match("🔴") and "RedAirdrop" or colorDef.label:match("🟤") and "BrownAirdrop" or colorDef.label:match("🔵") and "BlueAirdrop" or nil
    local roleId = roleKey and getgenv().WebhookConfig.Roles[roleKey] or nil
    local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
    local imageUrl = roleKey and getgenv().WebhookConfig.Images[roleKey] or nil
    local fields = string.format('[{"name":"🎨 Drop Type","value":"%s","inline":true},{"name":"📍 Location","value":"%s","inline":true},{"name":"⏳ Time Left","value":"%s","inline":true},{"name":"👥 Total Players","value":"%s","inline":true},{"name":"🔗 Join Server","value":"[Click to Join](%s)","inline":false},{"name":"🦹 Criminals","value":"%s","inline":false},{"name":"🚔 Police","value":"%s","inline":true},{"name":"⏱️ Logged","value":"<t:%d:R>","inline":true}]',
        colorDef.label, locationName, timerText, total, joinLink, crimAndPris, pol, now)
    local embed = string.format('{"title":"📦 Airdrop Detected!","color":%d,"fields":%s,"footer":{"text":"Server ID: %s"},"timestamp":"%s"}', colorDef.embedColor, fields, jobId, os.date("!%Y-%m-%dT%H:%M:%SZ"))
    if imageUrl then embed = embed:sub(1,-2) .. ',"image":{"url":"' .. imageUrl .. '"}}' end
    local payload = '{"embeds":[' .. embed .. ']}'
    if roleMention then payload = '{"content":"' .. roleMention .. '","embeds":[' .. embed .. ']}' end
    pcall(function() request({Url = webhookUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = payload}) end)
end
local function getGameTimeText()
    local s, label = pcall(function() return game:GetService("Players").LocalPlayer.PlayerGui.AppUI.Buttons.Minimap.Time.Time end)
    if s and label and label:IsA("TextLabel") then return label.Text end
    return nil
end
local function parseGameTime(t)
    local h,m,per = t:match("(%d+):(%d+)%s*(%a+)")
    if not h then return nil end
    h = tonumber(h); per = per:upper()
    if per == "PM" and h ~= 12 then h = h + 12 elseif per == "AM" and h == 12 then h = 0 end
    return h, tonumber(m), per
end
local function checkAirdrops(jobId)
    local webhook = getgenv().WebhookConfig.Webhooks.Airdrop
    if not webhook or webhook == "" then sendLog(LogLevel.WARNING, "Airdrop Webhook Missing", "No webhook.") return end
    if getgenv().RobberyToggles and not getgenv().RobberyToggles.Airdrop then return end
    local found, logged = 0, 0
    local candidates = {}
    for _, drop in ipairs(workspace:GetChildren()) do if drop.Name == "Drop" and drop:IsA("Model") then table.insert(candidates, drop) end end
    if #candidates == 0 then sendLog(LogLevel.WARNING, "Airdrop Scan", "No 'Drop' models.") return end
    for _, drop in ipairs(candidates) do
        found = found + 1
        local wallPart = nil
        local walls = drop:FindFirstChild("Walls") or drop:FindFirstChild("walls")
        if walls then wallPart = walls:FindFirstChild("Wall") or walls:FindFirstChild("wall") or walls:FindFirstChildWhichIsA("BasePart", true) end
        if not wallPart then
            for _, child in ipairs(drop:GetChildren()) do if child:IsA("BasePart") and child.Name:lower() == "wall" then wallPart = child; break end end
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
        logged = logged + 1
        sendLog(LogLevel.SUCCESS, "Airdrop Logged", "Logged.", {{name="Type",value=colorDef.label},{name="Location",value=locName},{name="Timer",value=timerText}})
    end
    sendLog(LogLevel.INFO, "Airdrop Scan Complete", string.format("Found %d, Logged %d", found, logged))
end
local function checkForOpenStores(player)
    local pg = player and player:FindFirstChild("PlayerGui")
    if not pg then sendLog(LogLevel.ERROR, "Store Scan", "PlayerGui not found.") return end
    local wm = pg:FindFirstChild("WorldMarkersGui")
    if not wm then sendLog(LogLevel.ERROR, "Store Scan", "WorldMarkersGui not found.") return end
    local jobId = game.JobId
    local openCount, robberyCount, closedCount, missedCount, skippedCount = 0,0,0,0,0
    sendLog(LogLevel.INFO, "Store Scan Started", "Beginning scan.")
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
                    local isOpen = (r==0 and g==255 and b==0)
                    local isClosed = (r==255 and g==0 and b==0)
                    local isRobbery = not isOpen and not isClosed
                    if isOpen then openCount = openCount + 1 elseif isClosed then closedCount = closedCount + 1 else robberyCount = robberyCount + 1 end
                    if storeName == "Crown_Jewel" then
                        if getgenv().RobberyToggles and not getgenv().RobberyToggles[storeName] then skippedCount = skippedCount + 1; break end
                        if not (isOpen or isRobbery) then break end
                        local code = getCrownJewelCode() or "N/A"
                        local now = os.time()
                        local joinLink = getJoinLink(jobId)
                        local tc = getTeamCounts()
                        local crim = tc.Criminal; local pol = tc.Police; local pris = tc.Prisoner
                        local crimAndPris = crim + pris; local total = crimAndPris + pol
                        local statusText = isOpen and "Open" or "Under Robbery"
                        local title = isOpen and "Crown Jewel is Open!" or "Crown Jewel is Under Robbery!"
                        local roleId = getgenv().WebhookConfig.Roles["Crown_Jewel"]
                        local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
                        local imageUrl = getgenv().WebhookConfig.Images["Crown_Jewel"]
                        local fields = string.format('[{"name":"📍 Status","value":"%s","inline":true},{"name":"👥 Total Players","value":"%s","inline":true},{"name":"🔢 Code","value":"%s","inline":true},{"name":"🔗 Join Server","value":"[Click to Join](%s)","inline":false},{"name":"🏃 Criminals","value":"%s","inline":true},{"name":"🚔 Police","value":"%s","inline":true},{"name":"⏱️ Logged","value":"<t:%d:R>","inline":true}]',
                            statusText, total, code, joinLink, crimAndPris, pol, now)
                        local embed = string.format('{"title":"%s","color":%d,"fields":%s,"footer":{"text":"Server ID: %s"},"timestamp":"%s"}', title, isOpen and 3066993 or 15105570, fields, jobId, os.date("!%Y-%m-%dT%H:%M:%SZ"))
                        if imageUrl then embed = embed:sub(1,-2) .. ',"image":{"url":"' .. imageUrl .. '"}}' end
                        local payload = '{"embeds":[' .. embed .. ']}'
                        if roleMention then payload = '{"content":"' .. roleMention .. '","embeds":[' .. embed .. ']}' end
                        pcall(function() request({Url = webhook, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = payload}) end)
                        sendLog(LogLevel.SUCCESS, "Crown Jewel Logged", display .. " " .. statusText .. " — Code: " .. code, {{name="Code",value=code}})
                    elseif storeName == "Mansion" then
                        if getgenv().RobberyToggles and not getgenv().RobberyToggles.Mansion then skippedCount = skippedCount + 1; break end
                        if not isOpen then break end
                        local timeText = getGameTimeText()
                        if not timeText then sendLog(LogLevel.WARNING, "Mansion Time Missing", "Could not read time.") break end
                        local hour,_,period = parseGameTime(timeText)
                        if not hour then sendLog(LogLevel.WARNING, "Mansion Time Parse Failed", timeText) break end
                        if period == "AM" and hour >= 3 then sendLog(LogLevel.INFO, "Mansion Skipped", timeText); skippedCount = skippedCount + 1; break end
                        local timeStatus, timeColor
                        if hour >= 18 then timeStatus = "Open"; timeColor = 3066993
                        elseif hour >= 16 then timeStatus = "Ready to Open"; timeColor = 16753920
                        elseif hour == 0 then timeStatus = "Closing Soon"; timeColor = 15158332
                        elseif hour < 3 and period == "AM" then timeStatus = "Closing Soon"; timeColor = 15158332
                        else timeStatus = "Unknown"; timeColor = 5793266 end
                        local roleId = getgenv().WebhookConfig.Roles["Mansion"]
                        local roleMention = roleId and ("<@&" .. roleId .. ">") or nil
                        local now = os.time()
                        local joinLink = getJoinLink(jobId)
                        local tc = getTeamCounts()
                        local crim = tc.Criminal; local pol = tc.Police; local pris = tc.Prisoner
                        local crimAndPris = crim + pris; local total = crimAndPris + pol
                        local imageUrl = getgenv().WebhookConfig.Images["Mansion"]
                        local fields = string.format('[{"name":"⏰ Game Time","value":"%s","inline":true},{"name":"📍 Status","value":"Open","inline":true},{"name":"👥 Total Players","value":"%s","inline":true},{"name":"🔗 Join Server","value":"[Click to Join](%s)","inline":false},{"name":"🏃 Criminals","value":"%s","inline":true},{"name":"🚔 Police","value":"%s","inline":true},{"name":"⏱️ Logged","value":"<t:%d:R>","inline":true}]',
                            timeText, total, joinLink, crimAndPris, pol, now)
                        local embed = string.format('{"title":"🏰 Mansion is Open (%s)","color":%d,"fields":%s,"footer":{"text":"Server ID: %s"},"timestamp":"%s"}', timeStatus, timeColor, fields, jobId, os.date("!%Y-%m-%dT%H:%M:%SZ"))
                        if imageUrl then embed = embed:sub(1,-2) .. ',"image":{"url":"' .. imageUrl .. '"}}' end
                        local payload = '{"embeds":[' .. embed .. ']}'
                        if roleMention then payload = '{"content":"' .. roleMention .. '","embeds":[' .. embed .. ']}' end
                        pcall(function() request({Url = webhook, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = payload}) end)
                        sendLog(LogLevel.SUCCESS, "Mansion Logged", "Mansion Open at " .. timeText, {{name="Time Status",value=timeStatus}})
                    else
                        if isOpen then
                            if webhook and webhook ~= "" then
                                if getgenv().RobberyToggles and getgenv().RobberyToggles[storeName] then
                                    sendDiscordEmbed(webhook, storeName, "open", jobId)
                                    sendLog(LogLevel.SUCCESS, "Store Open", display .. " open.", {{name="Store",value=display}})
                                else skippedCount = skippedCount + 1; sendLog(LogLevel.INFO, "Store Open — Toggled Off", display .. " open but disabled.") end
                            else sendLog(LogLevel.WARNING, "Store Open — No Webhook", display .. " open but no webhook.") end
                        elseif isRobbery then
                            if storeName == "Cargo_Plane" then
                                sendLog(LogLevel.INFO, "Cargo Plane Robbery Skipped", "Cargo Plane robbery not logged.")
                            elseif webhook and webhook ~= "" then
                                if getgenv().RobberyToggles and getgenv().RobberyToggles[storeName] then
                                    sendDiscordEmbed(webhook, storeName, "robbery", jobId)
                                    sendLog(LogLevel.SUCCESS, "Robbery Logged", display .. " under robbery.", {{name="Store",value=display}})
                                else skippedCount = skippedCount + 1; sendLog(LogLevel.INFO, "Robbery — Toggled Off", display .. " robbery disabled.") end
                            else sendLog(LogLevel.WARNING, "Robbery — No Webhook", display .. " robbery but no webhook.") end
                        end
                    end
                else missedCount = missedCount + 1; sendLog(LogLevel.WARNING, "Store — Unexpected Parent", "Icon parent not ImageLabel for " .. display) end
                break
            end
        end
        if not found then missedCount = missedCount + 1; sendLog(LogLevel.WARNING, "Store Icon Missing", "Icon missing for " .. display) end
    end
    sendLog(LogLevel.INFO, "Store Scan Complete", "Finished.", {{name="✅ Open",value=openCount},{name="🔴 Robbery",value=robberyCount},{name="⚫ Closed",value=closedCount},{name="⚠️ Missed",value=missedCount},{name="⏭️ Skipped",value=skippedCount}})
end
if not getgenv()._ServerHopSource then
    getgenv()._ServerHopSource = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/s5nni/Leaf/refs/heads/main/main.lua"))()]]
end
pcall(function()
    local player = waitForLoad()
    local currentJobId = game.JobId
    sendLog(LogLevel.INFO, "Bot Started", "Script loaded.", {{name="Server ID",value=currentJobId}})
    if ServerHop.hasS5nniPlayer() then sendLog(LogLevel.INFO, "S5nni Player Detected", "Hopping without scan.") ServerHop.hopToNewServer(player) return end
    if getgenv().ServerId == currentJobId then sendLog(LogLevel.WARNING, "Duplicate Server Detected", "Hopping immediately.") ServerHop.hopToNewServer(player) return end
    getgenv().ServerId = currentJobId
    checkForOpenStores(player)
    checkAirdrops(currentJobId)
    getgenv().IsFinished = true
    sendLog(LogLevel.SUCCESS, "Cycle Complete", "All scans finished. Hopping in 2s.")
    task.wait(2)
    ServerHop.hopToNewServer(player)
end)
