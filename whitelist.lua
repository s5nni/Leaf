local allowedIds = {
    "716FCC14-6490-418D-8A86-F95C17A8FC7B",
    "9d5b53adf6fc8aa28c3e2734c0093da69f3cb79191994f613f7a324309fdbc61",
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
