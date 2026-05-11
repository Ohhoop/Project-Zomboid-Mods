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

local function normalizeSpawnPointCoords(spawnPoint)
    if type(spawnPoint) ~= "table" then
        return nil, nil, nil
    end

    local posZ = tonumber(spawnPoint.posZ) or 0
    if spawnPoint.worldX ~= nil then
        return (tonumber(spawnPoint.worldX) or 0) * 300 + (tonumber(spawnPoint.posX) or 0),
               (tonumber(spawnPoint.worldY) or 0) * 300 + (tonumber(spawnPoint.posY) or 0),
               posZ
    end

    return tonumber(spawnPoint.posX), tonumber(spawnPoint.posY), posZ
end

function QuickRestartUtil.findRegionMatchingPlayerCoords(playerX, playerY, playerZ, regions)
    if type(regions) ~= "table"
        or type(playerX) ~= "number"
        or type(playerY) ~= "number"
        or type(playerZ) ~= "number" then
        return nil, false, nil
    end

    local floorX = math.floor(playerX)
    local floorY = math.floor(playerY)
    local floorZ = math.floor(playerZ)

    local bestRegion = nil
    local bestDistanceSq = math.huge

    for _, region in ipairs(regions) do
        if type(region) == "table" and region.name and type(region.points) == "table" then
            for _, professionPoints in pairs(region.points) do
                if type(professionPoints) == "table" then
                    for _, spawnPoint in ipairs(professionPoints) do
                        local nx, ny, nz = normalizeSpawnPointCoords(spawnPoint)
                        if nx and ny and nz then
                            if nx == floorX and ny == floorY and nz == floorZ then
                                return region, true, 0
                            end

                            local dx = nx - playerX
                            local dy = ny - playerY
                            local dz = nz - playerZ
                            local distanceSq = dx * dx + dy * dy + dz * dz
                            if distanceSq < bestDistanceSq then
                                bestDistanceSq = distanceSq
                                bestRegion = region
                            end
                        end
                    end
                end
            end
        end
    end

    if not bestRegion then
        return nil, false, nil
    end

    return bestRegion, false, math.sqrt(bestDistanceSq)
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
