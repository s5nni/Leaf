local allowedIds = {
    "716FCC14-6490-418D-8A86-F95C17A8FC7B",
    "3d9c16d6-c4ce-401e-9236-d9d025334012",
    "8ff63035-bade-4332-9501-c5220da7cca7",
    "3d9c16d6-c4ce-401e-9236-d9d025334012",
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
