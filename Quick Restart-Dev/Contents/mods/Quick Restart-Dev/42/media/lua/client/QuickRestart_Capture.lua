QuickRestartCapture = QuickRestartCapture or {}

local function resolveProfessionType(desc)
    if not desc or not desc.getCharacterProfession then
        return "unemployed"
    end

    local profession = desc:getCharacterProfession()
    if profession == nil then
        return "unemployed"
    end

    if type(profession) == "string" then
        return profession
    end

    if profession.getType then
        local ok, professionType = pcall(function()
            return profession:getType()
        end)
        if ok and professionType and professionType ~= "" then
            return tostring(professionType)
        end
    end

    return tostring(profession)
end

function QuickRestartCapture.captureCharacterData(player, options)
    if not player then
        return nil
    end

    local desc = player:getDescriptor()
    if not desc then
        return nil
    end

    options = options or {}
    local visualItemTypes = options.visualItemTypes or {}

    local call = pcall
    local insert = table.insert
    local toStr = tostring

    local data = {}
    data.forename = desc:getForename()
    data.surname = desc:getSurname()
    data.name = data.forename .. " " .. data.surname
    local isFemale = desc:isFemale()
    data.gender = isFemale and "female" or "male"

    data.profession = resolveProfessionType(desc)

    data.traits = {}
    if player.getCharacterTraits then
        local success, characterTraits = call(function() return player:getCharacterTraits() end)
        if success and characterTraits then
            local knownTraits = nil
            if characterTraits.getKnownTraits then
                success, knownTraits = call(function() return characterTraits:getKnownTraits() end)
            end

            if knownTraits then
                local traitCount
                success, traitCount = call(function() return knownTraits:size() end)
                if success and traitCount > 0 then
                    for i = 0, traitCount - 1 do
                        local traitType
                        success, traitType = call(function() return knownTraits:get(i) end)
                        if success and traitType then
                            local traitDef
                            success, traitDef = call(function()
                                return CharacterTraitDefinition.getCharacterTraitDefinition(traitType)
                            end)
                            if success and traitDef then
                                local traitName
                                success, traitName = call(function() return traitDef:getType() end)
                                if success and traitName then
                                    insert(data.traits, toStr(traitName))
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local visual = player:getHumanVisual()
    data.visual = {}
    if visual then
        local success, result

        success, result = call(function() return visual:getHairModel() end)
        if success then data.visual.hairModel = result end

        success, result = call(function() return visual:getBeardModel() end)
        if success then data.visual.beardModel = result end

        success, result = call(function() return visual:getNaturalHairColor() end)
        if success and result then
            local r, g, b = result:getRedFloat(), result:getGreenFloat(), result:getBlueFloat()
            data.visual.hairColor = {r = r, g = g, b = b}
        end

        success, result = call(function() return visual:getSkinTextureIndex() end)
        if success then data.visual.skinTextureIndex = result end

        success, result = call(function() return visual:getBodyHairIndex() end)
        if success then data.visual.bodyHairIndex = result end

        if CharacterCreationMain and CharacterCreationMain.instance then
            local ccm = CharacterCreationMain.instance
            if ccm.hairStubbleTickBox then
                data.visual.hairStubble = ccm.hairStubbleTickBox:isSelected(1)
            end
            if ccm.beardStubbleTickBox and not isFemale then
                data.visual.beardStubble = ccm.beardStubbleTickBox:isSelected(1)
            end
        else
            local descVisual = desc:getHumanVisual()
            if descVisual then
                if isFemale then
                    success, result = call(function() return descVisual:hasBodyVisualFromItemType(visualItemTypes.fHairStubble) end)
                    if success then data.visual.hairStubble = result end
                else
                    success, result = call(function() return descVisual:hasBodyVisualFromItemType(visualItemTypes.mHairStubble) end)
                    if success then data.visual.hairStubble = result end
                end

                if not isFemale then
                    success, result = call(function() return descVisual:hasBodyVisualFromItemType(visualItemTypes.mBeardStubble) end)
                    if success then data.visual.beardStubble = result end
                end
            end
        end
    end

    data.voice = {}
    if CharacterCreationMain and CharacterCreationMain.instance then
        local ccm = CharacterCreationMain.instance
        local success, result
        if ccm.getVoicePrefix then
            success, result = call(function() return ccm:getVoicePrefix() end)
            if success then data.voice.prefix = result end
        end
        if ccm.getVoiceType then
            success, result = call(function() return ccm:getVoiceType() end)
            if success then data.voice.type = result end
        end
        if ccm.getVoicePitch then
            success, result = call(function() return ccm:getVoicePitch() end)
            if success then data.voice.pitch = result end
        end
    end

    data.skills = {}
    local xp = player:getXp()
    local maxPerkIndex = Perks.getMaxIndex() - 1
    for i = 0, maxPerkIndex do
        local perkEnum = Perks.fromIndex(i)
        local perk = PerkFactory.getPerk(perkEnum)
        if perk then
            local perkXP = xp:getXP(perkEnum)
            if perkXP then
                data.skills[toStr(i)] = perkXP
            end
        end
    end

    data.clothing = {}
    local success, wornItems = call(function() return player:getWornItems() end)
    if success and wornItems then
        for i = 0, wornItems:size() - 1 do
            local item = wornItems:getItemByIndex(i)
            if item then
                local clothingData = {
                    type = item:getFullType()
                }

                if item.getColorInfo then
                    local result
                    success, result = call(function() return item:getColorInfo() end)
                    if success and result and result.getR and result.getG and result.getB then
                        local r, g, b
                        success, r, g, b = call(function()
                            return result:getR(), result:getG(), result:getB()
                        end)
                        if success then
                            clothingData.color = {r = r or 0, g = g or 0, b = b or 0}
                        end
                    end
                end

                if item.getVisual then
                    local itemVisual
                    success, itemVisual = call(function() return item:getVisual() end)
                    if success and itemVisual then
                        if itemVisual.getBaseTexture then
                            local baseTexture
                            success, baseTexture = call(function() return itemVisual:getBaseTexture() end)
                            if success and baseTexture and type(baseTexture) == "number" then
                                clothingData.baseTexture = baseTexture
                            end
                        end
                        if itemVisual.getTextureChoice then
                            local textureChoice
                            success, textureChoice = call(function() return itemVisual:getTextureChoice() end)
                            if success and textureChoice and type(textureChoice) == "number" then
                                clothingData.textureChoice = textureChoice
                            end
                        end
                    end
                end

                insert(data.clothing, clothingData)
            end
        end
    end

    local core = getCore()
    if core:isChallenge() then
        data.isChallenge = true
        data.challengeID = core:getChallengeID()
        if MapSpawnSelect and MapSpawnSelect.instance and MapSpawnSelect.instance.selectedRegion then
            data.region = MapSpawnSelect.instance.selectedRegion.name
        end
    else
        data.isChallenge = false
        if MapSpawnSelect and MapSpawnSelect.instance and MapSpawnSelect.instance.selectedRegion and MapSpawnSelect.instance.selectedRegion.name then
            data.region = MapSpawnSelect.instance.selectedRegion.name
        end
    end

    return data
end

return QuickRestartCapture
