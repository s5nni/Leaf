local Whitelist = {
    ["716FCC14-6490-418D-8A86-F95C17A8FC7B"] = true,
}

local function IsWhitelisted()
    local clientId = game:GetService("RbxAnalyticsService"):GetClientId()
    return Whitelist[clientId] == true
end

return IsWhitelisted
