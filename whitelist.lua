local allowedIds = {
    "716FCC14-6490-418D-8A86-F95C17A8FC7B",
}

getgenv().WhitelistCheck = function()
    local clientId = game:GetService("RbxAnalyticsService"):GetClientId()
    for _, id in ipairs(allowedIds) do
        if id == clientId then
            return true
        end
    end
    return false
end
