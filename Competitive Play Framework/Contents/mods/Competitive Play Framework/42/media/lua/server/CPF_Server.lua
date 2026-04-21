if not isServer() then return end

local teams = {}
local maxImbalance = 2

local function countTeams()
    local red, blue = 0, 0
    for _, team in pairs(teams) do
        if team == "red" then red = red + 1
        elseif team == "blue" then blue = blue + 1
        end
    end
    return red, blue
end

local function isImbalanced(requestedTeam, redCount, blueCount)
    if requestedTeam == "red" then
        return (redCount - blueCount) >= maxImbalance
    elseif requestedTeam == "blue" then
        return (blueCount - redCount) >= maxImbalance
    end
    return true
end

local function onClientCommand(module, command, player, args)
    if module ~= "CPF" then return end

    local username = player:getUsername()

    if command == "requestState" then
        local red, blue = countTeams()
        sendServerCommand(player, "CPF", "stateSync", {
            team = teams[username],
            redCount = red,
            blueCount = blue,
            maxImbalance = maxImbalance,
        })

    elseif command == "requestTeam" then
        local requestedTeam = args and args.team
        if requestedTeam ~= "red" and requestedTeam ~= "blue" then return end

        local red, blue = countTeams()

        if isImbalanced(requestedTeam, red, blue) then
            sendServerCommand(player, "CPF", "teamDenied", { reason = "imbalance" })
            return
        end

        teams[username] = requestedTeam
        if requestedTeam == "red" then red = red + 1 else blue = blue + 1 end

        sendServerCommand(player, "CPF", "teamAssigned", {
            team = requestedTeam,
            redCount = red,
            blueCount = blue,
        })

    elseif command == "resetMatch" then
        if not player:isAdmin() then return end

        teams = {}
        sendServerCommand(nil, "CPF", "matchReset", {})

    elseif command == "setMaxImbalance" then
        if not player:isAdmin() then return end

        local value = args and tonumber(args.max)
        if not value or value < 0 then return end

        maxImbalance = value
        sendServerCommand(nil, "CPF", "configSync", { maxImbalance = maxImbalance })
    end
end

Events.OnClientCommand.Add(onClientCommand)
