QuickRestartUtil = QuickRestartUtil or {}

function QuickRestartUtil.safeCall(label, fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then
        if QuickRestartLog and QuickRestartLog.debug then
            QuickRestartLog.debug("safeCall failed: " .. tostring(label) .. " -> " .. tostring(a))
        end
        return false, nil, nil, nil, nil
    end
    return true, a, b, c, d
end

function QuickRestartUtil.safeGet(label, defaultValue, fn, ...)
    local ok, value = QuickRestartUtil.safeCall(label, fn, ...)
    if not ok or value == nil then
        return defaultValue
    end
    return value
end

function QuickRestartUtil.copyScalarTable(source)
    local result = {}
    if type(source) ~= "table" then
        return result
    end

    for key, value in pairs(source) do
        local valueType = type(value)
        if valueType == "string" or valueType == "number" or valueType == "boolean" then
            result[key] = value
        end
    end

    return result
end

function QuickRestartUtil.sanitizeFileComponent(value)
    local text = tostring(value or "")
    text = string.gsub(text, "[\\/:*?\"<>|%c%s]+", "_")
    text = string.gsub(text, "_+", "_")
    text = string.gsub(text, "^_+", "")
    text = string.gsub(text, "_+$", "")
    if text == "" then
        return "unknown"
    end
    return text
end

function QuickRestartUtil.buildProfileKey(steamID, username)
    local cleanUsername = QuickRestartUtil.sanitizeFileComponent(username)
    local cleanSteamID = QuickRestartUtil.sanitizeFileComponent(steamID)

    if steamID and steamID ~= "" then
        return cleanSteamID .. "__" .. cleanUsername
    end

    return cleanUsername
end

return QuickRestartUtil
