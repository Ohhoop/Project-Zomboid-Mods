QuickRestartSandbox = QuickRestartSandbox or {}

local function isSupportedSandboxScalar(key, value)
    local valueType = type(value)
    return (valueType == "number" or valueType == "boolean" or valueType == "string")
        and key ~= "Version"
        and key ~= "VERSION"
end

function QuickRestartSandbox.captureCurrent()
    if not SandboxVars then
        return nil
    end

    local snapshot = {}
    for key, value in pairs(SandboxVars) do
        if isSupportedSandboxScalar(key, value) then
            snapshot[key] = value
        elseif type(value) == "table" then
            local tableCopy = {}
            for subKey, subValue in pairs(value) do
                if isSupportedSandboxScalar(subKey, subValue) then
                    tableCopy[subKey] = subValue
                end
            end
            snapshot[key] = tableCopy
        end
    end

    return snapshot
end

function QuickRestartSandbox.extractFromSnapshot(data)
    return data and data.sandbox or nil
end

function QuickRestartSandbox.differs(creationVars, currentVars)
    if not creationVars or not currentVars then
        return false
    end

    for key, value in pairs(creationVars) do
        local valueType = type(value)
        if isSupportedSandboxScalar(key, value) then
            if currentVars[key] ~= value then
                return true
            end
        elseif valueType == "table" then
            local other = currentVars[key]
            if type(other) ~= "table" then
                return true
            end

            for subKey, subValue in pairs(value) do
                if isSupportedSandboxScalar(subKey, subValue) and other[subKey] ~= subValue then
                    return true
                end
            end

            for subKey, subValue in pairs(other) do
                if isSupportedSandboxScalar(subKey, subValue) and value[subKey] ~= subValue then
                    return true
                end
            end
        end
    end

    for key, value in pairs(currentVars) do
        local valueType = type(value)
        if isSupportedSandboxScalar(key, value) and creationVars[key] ~= value then
            return true
        elseif valueType == "table" and type(creationVars[key]) ~= "table" then
            return true
        end
    end

    return false
end

return QuickRestartSandbox
