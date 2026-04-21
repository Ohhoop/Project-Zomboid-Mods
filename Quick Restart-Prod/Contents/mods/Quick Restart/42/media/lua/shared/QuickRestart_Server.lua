if not isServer() then return end

print("[QuickRestart Server] server file loaded")

local function onClientCommand(module, command, player, args)
    print("[QuickRestart Server] onClientCommand module=" .. tostring(module) .. " command=" .. tostring(command))
    if module ~= "QuickRestart" then return end

    if command == "applySkills" then
        print("[QuickRestart Server] applySkills received for player=" .. tostring(player))
        local skills = args.skills
        if not skills or not player then return end

        local xp = player:getXp()
        if not xp then return end

        local levelPerkHandlers = Events.LevelPerk.handlers
        Events.LevelPerk.handlers = {}

        for perkIndexStr, targetXP in pairs(skills) do
            local perkIndex = tonumber(perkIndexStr)
            if perkIndex then
                local perkEnum = Perks.fromIndex(perkIndex)
                local perk = PerkFactory.getPerk(perkEnum)
                if perk then
                    if targetXP == 0 then
                        player:setPerkLevelDebug(perkEnum, 0)
                        xp:setXPToLevel(perkEnum, 0)
                    else
                        local level = 0
                        while level < 10 and perk:getTotalXpForLevel(level + 1) <= targetXP do
                            level = level + 1
                        end
                        player:setPerkLevelDebug(perkEnum, level)
                        xp:setXPToLevel(perkEnum, level)
                        local balance = targetXP - perk:getTotalXpForLevel(level)
                        if balance > 0 then
                            xp:AddXP(perkEnum, balance, false, false, false, false)
                        end
                    end
                end
            end
        end

        Events.LevelPerk.handlers = levelPerkHandlers
    end
end

Events.OnClientCommand.Add(onClientCommand)
