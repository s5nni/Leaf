local allowedIds = {
    "716FCC14-6490-418D-8A86-F95C17A8FC7B",
    "8ff63035-bade-4332-9501-c5220da7cca7",
    "726c22f3-1669-493d-bc26-dadb0fa4fe4c",
    "f406d1ae-0c0b-4675-a0f5-74f587fef568",
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
