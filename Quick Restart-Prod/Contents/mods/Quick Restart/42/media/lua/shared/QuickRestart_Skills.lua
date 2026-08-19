QuickRestartSkills = QuickRestartSkills or {}

function QuickRestartSkills.applyToPlayer(player, skills, options)
    if not player or type(skills) ~= "table" then
        return false
    end

    local xp = player:getXp()
    if not xp then
        return false
    end

    options = options or {}

    local restoreLevelPerkHandlers = nil
    if Events.LevelPerk and Events.LevelPerk.handlers then
        restoreLevelPerkHandlers = Events.LevelPerk.handlers
        Events.LevelPerk.handlers = {}
    end

    local restoreAddXPHandlers = nil
    if Events.AddXP and Events.AddXP.handlers then
        restoreAddXPHandlers = Events.AddXP.handlers
        Events.AddXP.handlers = {}
    end

    local ok, applyError = pcall(function()
        for perkIndexStr, targetXP in pairs(skills) do
            local perkIndex = tonumber(perkIndexStr)
            if perkIndex then
                local perkEnum = Perks.fromIndex(perkIndex)
                local perk = PerkFactory.getPerk(perkEnum)
                if perk then
                    if targetXP == 0 then
                        player:setPerkLevelDebug(perkEnum, 0)
                        xp:setXPToLevel(perkEnum, 0)
                        if options.logProgress then
                            if QuickRestartLog and QuickRestartLog.info then
                                QuickRestartLog.info("skill perkIndex=" .. tostring(perkIndexStr) .. " set to 0")
                            elseif QRDebugLogging == true then
                                print("[QuickRestart] INFO skill perkIndex=" .. tostring(perkIndexStr) .. " set to 0")
                            end
                        end
                    else
                        local level = 0
                        while level < 10 and perk:getTotalXpForLevel(level + 1) <= targetXP do
                            level = level + 1
                        end

                        player:setPerkLevelDebug(perkEnum, level)
                        xp:setXPToLevel(perkEnum, level)

                        local xpForThisLevel = perk:getTotalXpForLevel(level)
                        local balance = targetXP - xpForThisLevel

                        if balance > 0 then
                            xp:AddXP(perkEnum, balance, false, false, false, false)
                        end

                        if options.logProgress then
                            if QuickRestartLog and QuickRestartLog.info then
                                QuickRestartLog.info("skill perkIndex=" .. tostring(perkIndexStr) .. " level=" .. tostring(level) .. " xp=" .. tostring(targetXP))
                            elseif QRDebugLogging == true then
                                print("[QuickRestart] INFO skill perkIndex=" .. tostring(perkIndexStr) .. " level=" .. tostring(level) .. " xp=" .. tostring(targetXP))
                            end
                        end
                    end
                end
            end
        end
    end)

    if restoreLevelPerkHandlers ~= nil then
        Events.LevelPerk.handlers = restoreLevelPerkHandlers
    end

    if restoreAddXPHandlers ~= nil then
        Events.AddXP.handlers = restoreAddXPHandlers
    end

    if not ok then
        error(applyError, 0)
    end

    return true
end

return QuickRestartSkills
