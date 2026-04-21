
require('NPCs/MainCreationMethods')

QuickRestart = QuickRestart or {}
QuickRestart.saveData = nil
QuickRestart.pendingSameWorld = nil
QuickRestart.sameWorldData = nil
QuickRestart.pendingMPSkills = nil

local function getPlayerIdentifier(player)
    if not player then return nil end
    if isMultiplayer() then
        return "player"
    end
    return tostring(player:getPlayerNum())
end

local function canUseFreshWorld()
    if isMultiplayer() then return false end
    if getNumActivePlayers() > 1 then return false end
    return true
end

local writeDataToFile
local loadDataFromFile
local loadDataFromSaveFolder
local restartPanel

local function saveCharacterData(player, saveFilePath)
    if not player then
        return
    end

    local desc = player:getDescriptor()
    if not desc then
        return
    end

    local call = pcall
    local insert = table.insert
    local toStr = tostring

    local data = {}
    data.forename = desc:getForename()
    data.surname = desc:getSurname()
    data.name = data.forename .. " " .. data.surname
    local isFemale = desc:isFemale()
    data.gender = isFemale and "female" or "male"

    if desc.getCharacterProfession then
        data.profession = desc:getCharacterProfession()
    else
        data.profession = "unemployed"
    end

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
        if success then
            data.visual.bodyHairIndex = result
        end

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
                    success, result = call(function() return descVisual:hasBodyVisualFromItemType(F_HAIR_STUBBLE) end)
                    if success then
                        data.visual.hairStubble = result
                    end
                else
                    success, result = call(function() return descVisual:hasBodyVisualFromItemType(M_HAIR_STUBBLE) end)
                    if success then
                        data.visual.hairStubble = result
                    end
                end

                if not isFemale then
                    success, result = call(function() return descVisual:hasBodyVisualFromItemType(M_BEARD_STUBBLE) end)
                    if success then
                        data.visual.beardStubble = result
                    end
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
            if success then
                data.voice.prefix = result
            end
        end
        if ccm.getVoiceType then
            success, result = call(function() return ccm:getVoiceType() end)
            if success then
                data.voice.type = result
            end
        end
        if ccm.getVoicePitch then
            success, result = call(function() return ccm:getVoicePitch() end)
            if success then
                data.voice.pitch = result
            end
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
                    if success and result then
                        if result.getR and result.getG and result.getB then
                            local r, g, b
                            success, r, g, b = call(function()
                                return result:getR(), result:getG(), result:getB()
                            end)
                            if success then
                                clothingData.color = {r = r or 0, g = g or 0, b = b or 0}
                            end
                        end
                    end
                end

                if item.getVisual then
                    local visual
                    success, visual = call(function() return item:getVisual() end)
                    if success and visual then
                        if visual.getBaseTexture then
                            local baseTexture
                            success, baseTexture = call(function() return visual:getBaseTexture() end)
                            if success and baseTexture and type(baseTexture) == "number" then
                                clothingData.baseTexture = baseTexture
                            end
                        end
                        if visual.getTextureChoice then
                            local textureChoice
                            success, textureChoice = call(function() return visual:getTextureChoice() end)
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

    if saveFilePath then
        writeDataToFile(data, saveFilePath)
    end
end

local characterDataSaved = false

local F_HAIR_STUBBLE = "Base.F_Hair_Stubble"
local M_HAIR_STUBBLE = "Base.M_Hair_Stubble"
local M_BEARD_STUBBLE = "Base.M_Beard_Stubble"
local INVENTORY_CONTAINER = "InventoryContainer"

local ENCODE_KEY = "QuickRestart_B42_SecretKey_2026"
local ENCODE_KEY_LEN = #ENCODE_KEY

local function encodeString(str)
    if not str or str == "" then return "" end
    local result = {}
    local strByte = string.byte
    local strChar = string.char
    local strLen = #str
    for i = 1, strLen do
        local charByte = strByte(str, i)
        local kb = strByte(ENCODE_KEY, ((i - 1) % ENCODE_KEY_LEN) + 1)
        result[i] = strChar((charByte + kb) % 256)
    end
    return table.concat(result)
end

local function decodeString(str)
    if not str or str == "" then return "" end
    local result = {}
    local strByte = string.byte
    local strChar = string.char
    local strLen = #str
    for i = 1, strLen do
        local charByte = strByte(str, i)
        local kb = strByte(ENCODE_KEY, ((i - 1) % ENCODE_KEY_LEN) + 1)
        result[i] = strChar((charByte - kb + 256) % 256)
    end
    return table.concat(result)
end

local function getSaveFileName()
    return "QuickRestart"..getFileSeparator().."QuickRestart.txt"
end

local function getSaveFileNameForPlayer(playerIdentifier)
    local world = getWorld()
    if world then
        local worldName = world:getWorld()
        if worldName then
            worldName = string.gsub(worldName, "_player", "")
            return "QuickRestart"..getFileSeparator()..worldName..getFileSeparator().."QuickRestart_"..tostring(playerIdentifier)..".txt"
        end
    end
    return "QuickRestart_" .. tostring(playerIdentifier) .. ".txt"
end

writeDataToFile = function(data, customFileName, sandboxVars)
    local content = {}
    local insert = table.insert
    local toStr = tostring
    insert(content, "name=" .. (data.name or "") .. "\n")
    insert(content, "forename=" .. (data.forename or "") .. "\n")
    insert(content, "surname=" .. (data.surname or "") .. "\n")
    insert(content, "gender=" .. (data.gender or "") .. "\n")
    insert(content, "profession=" .. toStr(data.profession or "") .. "\n")
    insert(content, "region=" .. (data.region or "") .. "\n")

    insert(content, "isChallenge=" .. toStr(data.isChallenge or false) .. "\n")
    if data.isChallenge and data.challengeID then
        insert(content, "challengeID=" .. data.challengeID .. "\n")
    end

    if data.traits and #data.traits > 0 then
        insert(content, "traits=" .. table.concat(data.traits, ",") .. "\n")
    else
        insert(content, "traits=\n")
    end

    if data.skills then
        local skillsList = {}
        for perkId, level in pairs(data.skills) do
            insert(skillsList, perkId .. ":" .. level)
        end
        insert(content, "skills=" .. table.concat(skillsList, ",") .. "\n")
    else
        insert(content, "skills=\n")
    end

    if data.visual then
        insert(content, "visual_hairModel=" .. (data.visual.hairModel or "") .. "\n")
        insert(content, "visual_beardModel=" .. (data.visual.beardModel or "") .. "\n")
        if data.visual.skinTextureIndex ~= nil then
            insert(content, "visual_skinTextureIndex=" .. toStr(data.visual.skinTextureIndex) .. "\n")
        else
            insert(content, "visual_skinTextureIndex=\n")
        end
        if data.visual.bodyHairIndex ~= nil then
            insert(content, "visual_bodyHairIndex=" .. toStr(data.visual.bodyHairIndex) .. "\n")
        else
            insert(content, "visual_bodyHairIndex=\n")
        end
        if data.visual.hairColor then
            insert(content, "visual_hairColor=" .. data.visual.hairColor.r .. "," .. data.visual.hairColor.g .. "," .. data.visual.hairColor.b .. "\n")
        end
        insert(content, "visual_hairStubble=" .. toStr(data.visual.hairStubble or false) .. "\n")
        insert(content, "visual_beardStubble=" .. toStr(data.visual.beardStubble or false) .. "\n")
    end

    if data.voice then
        insert(content, "voice_prefix=" .. (data.voice.prefix or "") .. "\n")
        if data.voice.type ~= nil then
            insert(content, "voice_type=" .. toStr(data.voice.type) .. "\n")
        else
            insert(content, "voice_type=\n")
        end
        if data.voice.pitch ~= nil then
            insert(content, "voice_pitch=" .. toStr(data.voice.pitch) .. "\n")
        else
            insert(content, "voice_pitch=\n")
        end
    end

    if data.clothing and #data.clothing > 0 then
        local clothingList = {}
        for _, item in ipairs(data.clothing) do
            local clothingStr = item.type
            local color = item.color
            if color then
                clothingStr = clothingStr .. "|" .. color.r .. "," .. color.g .. "," .. color.b
            else
                clothingStr = clothingStr .. "|"
            end
            local baseTexture = item.baseTexture
            if baseTexture then
                clothingStr = clothingStr .. "|" .. baseTexture
            else
                clothingStr = clothingStr .. "|"
            end
            local textureChoice = item.textureChoice
            if textureChoice then
                clothingStr = clothingStr .. "|" .. textureChoice
            end
            insert(clothingList, clothingStr)
        end
        insert(content, "clothing=" .. table.concat(clothingList, ";") .. "\n")
    else
        insert(content, "clothing=\n")
    end

    if sandboxVars then
        local typeFunc = type
        for key, value in pairs(sandboxVars) do
            local valueType = typeFunc(value)
            if valueType == "number" or valueType == "boolean" or valueType == "string" then
                insert(content, "sandbox_" .. key .. "=" .. toStr(value) .. "\n")
            elseif valueType == "table" then
                local tableStr = {}
                for k, v in pairs(value) do
                    local vType = typeFunc(v)
                    if vType == "number" or vType == "boolean" or vType == "string" then
                        insert(tableStr, k .. ":" .. toStr(v))
                    end
                end
                if #tableStr > 0 then
                    insert(content, "sandbox_" .. key .. "={" .. table.concat(tableStr, ",") .. "}\n")
                end
            end
        end
    end

    local fullContent = table.concat(content)
    local encodedContent = encodeString(fullContent)

    local fileName = customFileName or getSaveFileName()
    local savePath = getFileWriter(fileName, true, false)
    if savePath then
        savePath:write(encodedContent)
        savePath:close()
        return true
    end
    return false
end

local function deleteDataFile()
    local fileName = getSaveFileName()
    local writer = getFileWriter(fileName, true, false)
    if writer then
        writer:write("")
        writer:close()
    end
end

local saveSandboxData
saveSandboxData = function(saveFilePath)
    local data = loadDataFromFile(saveFilePath)
    if not data then return end
    if data.sandbox then
        for _ in pairs(data.sandbox) do return end
    end
    writeDataToFile(data, saveFilePath, SandboxVars)
end

local function fetchSandboxVarsAtCreation(data)
    return data.sandbox
end

local function fetchSandboxVarsAtDeath()
    if not SandboxVars then return nil end
    local snapshot = {}
    for key, value in pairs(SandboxVars) do
        local t = type(value)
        if (t == "number" or t == "boolean" or t == "string") and key ~= "Version" and key ~= "VERSION" then
            snapshot[key] = value
        elseif t == "table" then
            local tableCopy = {}
            for k, v in pairs(value) do
                local vt = type(v)
                if vt == "number" or vt == "boolean" or vt == "string" then
                    tableCopy[k] = v
                end
            end
            snapshot[key] = tableCopy
        end
    end
    return snapshot
end

local function sandboxDiffers(sandboxVarsCreation, sandboxVarsCurrent)
    if not sandboxVarsCreation or not sandboxVarsCurrent then return false end
    for key, value in pairs(sandboxVarsCreation) do
        local t = type(value)
        if (t == "number" or t == "boolean" or t == "string") and key ~= "Version" and key ~= "VERSION" then
            if sandboxVarsCurrent[key] ~= value then
                print("[QuickRestart] sandboxDiffers: scalar mismatch key=" .. tostring(key) .. " creation=" .. tostring(value) .. " current=" .. tostring(sandboxVarsCurrent[key]))
                return true
            end
        elseif t == "table" then
            local other = sandboxVarsCurrent[key]
            if type(other) ~= "table" then
                print("[QuickRestart] sandboxDiffers: table missing in current key=" .. tostring(key))
                return true
            end
            for k, v in pairs(value) do
                local vt = type(v)
                if (vt == "number" or vt == "boolean" or vt == "string") and other[k] ~= v then
                    print("[QuickRestart] sandboxDiffers: table mismatch key=" .. tostring(key) .. " subkey=" .. tostring(k) .. " creation=" .. tostring(v) .. " current=" .. tostring(other[k]))
                    return true
                end
            end
            for k, v in pairs(other) do
                local vt = type(v)
                if (vt == "number" or vt == "boolean" or vt == "string") and value[k] ~= v then
                    print("[QuickRestart] sandboxDiffers: table mismatch key=" .. tostring(key) .. " subkey=" .. tostring(k) .. " creation=" .. tostring(value[k]) .. " current=" .. tostring(v))
                    return true
                end
            end
        end
    end
    for key, value in pairs(sandboxVarsCurrent) do
        local t = type(value)
        if (t == "number" or t == "boolean" or t == "string") and sandboxVarsCreation[key] ~= value then
            print("[QuickRestart] sandboxDiffers: scalar only in current key=" .. tostring(key) .. " current=" .. tostring(value))
            return true
        elseif t == "table" and type(sandboxVarsCreation[key]) ~= "table" then
            print("[QuickRestart] sandboxDiffers: table only in current key=" .. tostring(key))
            return true
        end
    end
    return false
end

local function doRestartNewWorld(data, playerIdentifier, sandboxVars)
    writeDataToFile(data, nil, sandboxVars)

    local oldFileName = getSaveFileNameForPlayer(playerIdentifier)
    local writer = getFileWriter(oldFileName, true, false)
    if writer then
        writer:write("")
        writer:close()
    end

    getCore():exitToMenu()
end

function QuickRestart.RestartNewWorld()
    if not canUseFreshWorld() then
        return
    end

    local player = getPlayer()
    if not player then return end

    local playerIdentifier = getPlayerIdentifier(player)
    if not playerIdentifier then return end

    local data = loadDataFromSaveFolder(playerIdentifier)
    if not data or not data.region then
        return
    end

    if data.sandbox then
        local sandboxVarsCreation = fetchSandboxVarsAtCreation(data)
        local sandboxVarsCurrent = fetchSandboxVarsAtDeath()
        if sandboxDiffers(sandboxVarsCreation, sandboxVarsCurrent) then
            if restartPanel then
                restartPanel:showSandboxChoice(data, playerIdentifier, sandboxVarsCurrent)
            else
                doRestartNewWorld(data, playerIdentifier, sandboxVarsCreation)
            end
            return
        end
    end

    doRestartNewWorld(data, playerIdentifier, fetchSandboxVarsAtCreation(data))
end

function QuickRestart.RestartSameWorld()
    local player = getPlayer()
    if not player then return end

    local playerIdentifier = getPlayerIdentifier(player)
    if not playerIdentifier then return end

    local data = loadDataFromSaveFolder(playerIdentifier)
    if not data or not data.name then return end

    if restartPanel then
        restartPanel:removeFromUIManager()
        restartPanel = nil
    end

    QuickRestart.pendingSameWorld = true
    QuickRestart.sameWorldData = data

    BaseGameCharacterDetails.DoProfessions()
    CoopCharacterCreation:newPlayerMouse()

    local ticks = 0
    local function autoComplete()
        ticks = ticks + 1
        if ticks < 2 then return end
        Events.OnTick.Remove(autoComplete)

        local coop = CoopCharacterCreation.instance
        if not coop then
            QuickRestart.pendingSameWorld = nil
            QuickRestart.sameWorldData = nil
            return
        end

        local desc = MainScreen.instance.desc
        if desc then
            desc:setForename(data.forename or "John")
            desc:setSurname(data.surname or "Doe")
            desc:setFemale(data.gender == "female")
            if data.profession then
                local prof = CharacterProfession.get(ResourceLocation.of(tostring(data.profession)))
                if prof then desc:setCharacterProfession(prof) end
            end
            if data.voice then
                if data.voice.prefix then desc:setVoicePrefix(data.voice.prefix) end
                if data.voice.type ~= nil then desc:setVoiceType(data.voice.type) end
                if data.voice.pitch ~= nil then desc:setVoicePitch(data.voice.pitch) end
            end
            if isMultiplayer() and data.visual then
                local visual = desc:getHumanVisual()
                if visual then
                    local call = pcall
                    local isFemale = desc:isFemale()
                    if data.visual.hairModel then
                        call(function() visual:setHairModel(data.visual.hairModel) end)
                    end
                    if data.visual.beardModel and data.visual.beardModel ~= "" then
                        call(function() visual:setBeardModel(data.visual.beardModel) end)
                    else
                        call(function() visual:setBeardModel("") end)
                    end
                    if data.visual.hairColor then
                        call(function()
                            local color = ImmutableColor.new(data.visual.hairColor.r, data.visual.hairColor.g, data.visual.hairColor.b, 1)
                            visual:setNaturalHairColor(color)
                            visual:setHairColor(color)
                            visual:setNaturalBeardColor(color)
                            visual:setBeardColor(color)
                        end)
                    end
                    if data.visual.skinTextureIndex ~= nil then
                        call(function() visual:setSkinTextureIndex(data.visual.skinTextureIndex) end)
                    end
                    if data.visual.bodyHairIndex ~= nil then
                        call(function() visual:setBodyHairIndex(data.visual.bodyHairIndex) end)
                    end
                    if data.visual.hairStubble ~= nil then
                        call(function()
                            if isFemale then
                                if data.visual.hairStubble then
                                    visual:addBodyVisualFromItemType(F_HAIR_STUBBLE)
                                else
                                    visual:removeBodyVisualFromItemType(F_HAIR_STUBBLE)
                                end
                            else
                                if data.visual.hairStubble then
                                    visual:addBodyVisualFromItemType(M_HAIR_STUBBLE)
                                else
                                    visual:removeBodyVisualFromItemType(M_HAIR_STUBBLE)
                                end
                            end
                        end)
                    end
                    if data.visual.beardStubble ~= nil and not isFemale then
                        call(function()
                            if data.visual.beardStubble then
                                visual:addBodyVisualFromItemType(M_BEARD_STUBBLE)
                            else
                                visual:removeBodyVisualFromItemType(M_BEARD_STUBBLE)
                            end
                        end)
                    end
                end
            end
        end

        local mapSel = coop.mapSpawnSelect
        mapSel:fillList()
        local regionFound = false
        if data.region then
            for _, entry in ipairs(mapSel.listbox.items) do
                if entry.item and entry.item.region and entry.item.region.name == data.region then
                    mapSel.selectedRegion = entry.item.region
                    regionFound = true
                    break
                end
            end
        end
        if not regionFound then
            mapSel:useDefaultSpawnRegion()
        end

        if isMultiplayer() and data.traits and #data.traits > 0 and coop.charCreationProfession then
            for _, traitStr in ipairs(data.traits) do
                local characterTrait = CharacterTrait.get(ResourceLocation.of(tostring(traitStr)))
                if characterTrait then
                    local traitDef = CharacterTraitDefinition.getCharacterTraitDefinition(characterTrait)
                    if traitDef then
                        coop.charCreationProfession.listboxTraitSelected:addUniqueItem(traitDef:getLabel(), traitDef, traitDef:getDescription())
                    end
                end
            end
        end

        if coop:accept1() then
            coop:removeFromUIManager()
            CoopCharacterCreation.setVisibleAllUI(true)
            CoopCharacterCreation.instance = nil
            if ISPostDeathUI.instance[0] then
                ISPostDeathUI.instance[0]:removeFromUIManager()
                ISPostDeathUI.instance[0] = nil
            end
            setPlayerMouse(nil)
        end
    end
    Events.OnTick.Add(autoComplete)
end

loadDataFromFile = function(customFileName)
    local fileName = customFileName or getSaveFileName()
    local dataReader = getFileReader(fileName, false)
    if not dataReader then
        return nil
    end

    local insert = table.insert
    local encodedContent = {}
    local line = dataReader:readLine()
    while line do
        insert(encodedContent, line)
        line = dataReader:readLine()
    end
    dataReader:close()

    local encodedString = table.concat(encodedContent)
    if encodedString == "" then
        return nil
    end

    local success, decodedContent = pcall(function()
        return decodeString(encodedString)
    end)

    if not success then
        return nil
    end

    local data = {visual = {}, voice = {}, skills = {}, traits = {}, clothing = {}, sandbox = {}}
    local toNum = tonumber
    local gmatch = string.gmatch

    for contentLine in gmatch(decodedContent, "[^\n]+") do
        local key, value = contentLine:match("^([^=]+)=(.*)$")
        if key and value then
            if key == "pending" then
            elseif key:match("^sandbox_") then
                local sandboxKey = key:gsub("^sandbox_", "")
                if value:match("^{.*}$") then
                    local tableContent = value:match("^{(.*)}$")
                    local tableValue = {}
                    for pair in gmatch(tableContent, "[^,]+") do
                        local k, v = pair:match("([^:]+):(.+)")
                        if k and v then
                            if v == "true" then
                                tableValue[k] = true
                            elseif v == "false" then
                                tableValue[k] = false
                            elseif toNum(v) then
                                tableValue[k] = toNum(v)
                            else
                                tableValue[k] = v
                            end
                        end
                    end
                    data.sandbox[sandboxKey] = tableValue
                elseif value == "true" then
                    data.sandbox[sandboxKey] = true
                elseif value == "false" then
                    data.sandbox[sandboxKey] = false
                elseif toNum(value) then
                    data.sandbox[sandboxKey] = toNum(value)
                else
                    data.sandbox[sandboxKey] = value
                end
            elseif key:match("^visual_") then
                local visualKey = key:gsub("^visual_", "")
                if visualKey == "hairColor" then
                    local r, g, b = value:match("([^,]+),([^,]+),([^,]+)")
                    if r and g and b then
                        data.visual.hairColor = {r = toNum(r), g = toNum(g), b = toNum(b)}
                    end
                elseif visualKey == "hairStubble" or visualKey == "beardStubble" then
                    data.visual[visualKey] = (value == "true")
                elseif visualKey == "skinTextureIndex" or visualKey == "bodyHairIndex" then
                    data.visual[visualKey] = toNum(value)
                else
                    data.visual[visualKey] = value
                end
            elseif key:match("^voice_") then
                local voiceKey = key:gsub("^voice_", "")
                if voiceKey == "pitch" or voiceKey == "type" then
                    data.voice[voiceKey] = toNum(value)
                else
                    data.voice[voiceKey] = value
                end
            elseif key == "traits" then
                for trait in gmatch(value, "[^,]+") do
                    insert(data.traits, trait)
                end
            elseif key == "skills" then
                for skillPair in gmatch(value, "[^,]+") do
                    local perkId, level = skillPair:match("([^:]+):([^:]+)")
                    if perkId and level then
                        data.skills[perkId] = toNum(level)
                    end
                end
            elseif key == "clothing" then
                for clothingItem in gmatch(value, "[^;]+") do
                    local parts = {}
                    for part in gmatch(clothingItem, "[^|]+") do
                        insert(parts, part)
                    end
                    if #parts >= 1 then
                        local item = {type = parts[1]}
                        if parts[2] and parts[2] ~= "" then
                            local r, g, b = parts[2]:match("([^,]+),([^,]+),([^,]+)")
                            if r and g and b then
                                item.color = {r = toNum(r), g = toNum(g), b = toNum(b)}
                            end
                        end
                        if parts[3] and parts[3] ~= "" then
                            item.baseTexture = toNum(parts[3])
                        end
                        if parts[4] and parts[4] ~= "" then
                            item.textureChoice = toNum(parts[4])
                        end
                        insert(data.clothing, item)
                    end
                end
            elseif key == "isChallenge" then
                data.isChallenge = (value == "true")
            elseif key == "challengeID" then
                data.challengeID = value
            else
                data[key] = value
            end
        end
    end

    return data
end

loadDataFromSaveFolder = function(playerIdentifier)
    local fileName = getSaveFileNameForPlayer(playerIdentifier)
    return loadDataFromFile(fileName)
end

local pendingRestartChecked = false

local function checkPendingRestart()
    if pendingRestartChecked then return end
    pendingRestartChecked = true

    local data = loadDataFromFile()

    if not data or not data.name then
        return
    end

    if data.sandbox then
        for key, value in pairs(data.sandbox) do
            SandboxVars[key] = value
        end
    end

    QuickRestart.saveData = data

    if not MainScreen or not MainScreen.instance or not MainScreen.instance.desc then
        return
    end

    local desc = MainScreen.instance.desc

    desc:setForename(data.forename or "John")
    desc:setSurname(data.surname or "Doe")
    desc:setFemale(data.gender == "female")

    if data.voice then
        if data.voice.prefix then desc:setVoicePrefix(data.voice.prefix) end
        if data.voice.type then desc:setVoiceType(data.voice.type) end
        if data.voice.pitch then desc:setVoicePitch(data.voice.pitch) end
    end

    if data.profession then
        local professionStr = tostring(data.profession)
        local characterProfession = CharacterProfession.get(ResourceLocation.of(professionStr))
        if characterProfession then
            desc:setCharacterProfession(characterProfession)
        end
    end

    local worldName = "QuickRestart_" .. os.time()

    if data.isChallenge and data.challengeID then
        local targetChallenge = nil
        if LastStandChallenge then
            for i, challenge in ipairs(LastStandChallenge) do
                if challenge.id == data.challengeID then
                    targetChallenge = challenge
                    break
                end
            end
        end

        if targetChallenge then
            if getWorld().setDifficulty then
                getWorld():setDifficulty("Hardcore")
            end
            LastStandData.chosenChallenge = targetChallenge
            doChallenge(targetChallenge)
            getWorld():setWorld(worldName)
            createWorld(worldName)
            GameWindow.doRenderEvent(false)
            forceChangeState(LoadingQueueState.new())
        else
            getWorld():setGameMode("Sandbox")
            if data.region then
                getWorld():setMap(data.region)
            end
            createWorld(worldName)
            GameWindow.doRenderEvent(false)
            forceChangeState(LoadingQueueState.new())
        end
    elseif data.region then
        getWorld():setGameMode("Sandbox")
        getWorld():setMap(data.region)

        createWorld(worldName)
        GameWindow.doRenderEvent(false)
        forceChangeState(LoadingQueueState.new())
    end
end

Events.OnMainMenuEnter.Add(checkPendingRestart)

QuickRestartPanel = ISPanel:derive("QuickRestartPanel")

function QuickRestartPanel:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = {r=0, g=0, b=0, a=0.3}
    o.borderColor = {r=0, g=0, b=0, a=0}
    return o
end

function QuickRestartPanel:createChildren()
    ISPanel.createChildren(self)

    local buttonWidth = self.width * 0.72
    local buttonHeight = 20
    local spacing = 12
    local xCenter = (self.width - buttonWidth) / 2

    local textHeight = 25
    local totalButtonsHeight = buttonHeight * 2 + spacing
    local yStart = (self.height - totalButtonsHeight - textHeight) / 2 + textHeight

    self.freshWorldEnabled = canUseFreshWorld()
    local charDataAvail = self.charDataAvail

    local freshEnabled = self.freshWorldEnabled and charDataAvail
    local sameEnabled = charDataAvail

    local freshLabel = getText("UI_QuickRestart_FreshWorld")
    local sameLabel = getText("UI_QuickRestart_ThisWorld")

    if freshEnabled then
        self.freshButton = ISButton:new(xCenter, yStart, buttonWidth, buttonHeight, freshLabel, self, function() QuickRestart.RestartNewWorld() end)
    else
        self.freshButton = ISButton:new(xCenter, yStart, buttonWidth, buttonHeight, "", self, nil)
        self.freshButton.enable = false
        self.freshButton.disabledLabel = freshLabel
    end

    self.freshButton:initialise()
    self.freshButton:instantiate()

    if freshEnabled then
        self.freshButton.backgroundColor = {r=0, g=0, b=0, a=0.9}
    else
        self.freshButton.backgroundColor = {r=0.3, g=0.3, b=0.3, a=0.9}
    end

    self.freshButton.borderColor = {r=0.7, g=0.7, b=0.7, a=0.3}
    self:addChild(self.freshButton)

    if sameEnabled then
        self.sameButton = ISButton:new(xCenter, yStart + buttonHeight + spacing, buttonWidth, buttonHeight, sameLabel, self, function() QuickRestart.RestartSameWorld() end)
    else
        self.sameButton = ISButton:new(xCenter, yStart + buttonHeight + spacing, buttonWidth, buttonHeight, "", self, nil)
        self.sameButton.enable = false
        self.sameButton.disabledLabel = sameLabel
    end

    self.sameButton:initialise()
    self.sameButton:instantiate()

    if sameEnabled then
        self.sameButton.backgroundColor = {r=0, g=0, b=0, a=0.9}
    else
        self.sameButton.backgroundColor = {r=0.3, g=0.3, b=0.3, a=0.9}
    end

    self.sameButton.borderColor = {r=0.7, g=0.7, b=0.7, a=0.3}
    self:addChild(self.sameButton)
end

local function drawTooltip(panel, tooltipText, mouseX, mouseY)
    local textManager = getTextManager()
    local font = UIFont.Small
    local padding = 5
    local fontHeight = textManager:getFontHeight(font)
    local maxWidth = 400

    local lines = {}
    local line = ""
    for word in tooltipText:gmatch("%S+") do
        local test = line == "" and word or (line .. " " .. word)
        if textManager:MeasureStringX(font, test) > maxWidth then
            if line ~= "" then
                lines[#lines + 1] = line
                line = word
            else
                lines[#lines + 1] = word
            end
        else
            line = test
        end
    end
    if line ~= "" then lines[#lines + 1] = line end

    local maxLineWidth = 0
    for _, l in ipairs(lines) do
        local w = textManager:MeasureStringX(font, l)
        if w > maxLineWidth then maxLineWidth = w end
    end

    local boxWidth = maxLineWidth + padding * 2
    local boxHeight = fontHeight * #lines + padding * 2 + (#lines - 1) * 2
    local boxX = mouseX + 25
    local boxY = mouseY + 25

    panel:drawRect(boxX, boxY, boxWidth, boxHeight, 0.9, 0, 0, 0)
    panel:drawRectBorder(boxX, boxY, boxWidth, boxHeight, 1, 0.7, 0.7, 0.7)
    for i, l in ipairs(lines) do
        panel:drawText(l, boxX + padding, boxY + padding + (i - 1) * (fontHeight + 2), 1, 1, 1, 1, font)
    end
end

function QuickRestartPanel:showSandboxChoice(data, playerIdentifier, sandboxVarsCurrent)
    self:removeChild(self.freshButton)
    self:removeChild(self.sameButton)
    self.freshButton = nil
    self.sameButton = nil

    self.sandboxMode = true

    local subtitle = getText("UI_QuickRestart_SandboxConflict_Subtitle")
    local textManager = getTextManager()
    local font = UIFont.Small
    local fontHeight = textManager:getFontHeight(font)
    local subtitleLines = {}
    local line = ""
    for word in subtitle:gmatch("%S+") do
        local test = line == "" and word or (line .. " " .. word)
        if textManager:MeasureStringX(font, test) > self.width - 20 then
            if line ~= "" then
                subtitleLines[#subtitleLines + 1] = line
                line = word
            else
                subtitleLines[#subtitleLines + 1] = word
            end
        else
            line = test
        end
    end
    if line ~= "" then subtitleLines[#subtitleLines + 1] = line end
    self.subtitleLines = subtitleLines

    local buttonWidth = self.width * 0.72
    local buttonHeight = 20
    local spacing = 10
    local xCenter = (self.width - buttonWidth) / 2

    local titleMediumHeight = textManager:getFontHeight(UIFont.Medium)
    local newHeight = 10 + titleMediumHeight + 4 + fontHeight + 8 + #subtitleLines * (fontHeight + 2) + 10 + buttonHeight + spacing + buttonHeight + 10
    local oldBottom = self:getY() + self:getHeight()
    self:setHeight(newHeight)
    self:setY(oldBottom - newHeight)

    local buttonY2 = self.height - 10 - buttonHeight
    local buttonY1 = buttonY2 - spacing - buttonHeight

    self.savedButton = ISButton:new(xCenter, buttonY1, buttonWidth, buttonHeight, getText("UI_QuickRestart_SandboxConflict_Saved"), self, function()
        doRestartNewWorld(data, playerIdentifier, fetchSandboxVarsAtCreation(data))
    end)
    self.savedButton:initialise()
    self.savedButton:instantiate()
    self.savedButton.backgroundColor = {r=0, g=0, b=0, a=0.9}
    self.savedButton.borderColor = {r=0.7, g=0.7, b=0.7, a=0.3}
    self:addChild(self.savedButton)

    self.currentButton = ISButton:new(xCenter, buttonY2, buttonWidth, buttonHeight, getText("UI_QuickRestart_SandboxConflict_Current"), self, function()
        doRestartNewWorld(data, playerIdentifier, sandboxVarsCurrent)
    end)
    self.currentButton:initialise()
    self.currentButton:instantiate()
    self.currentButton.backgroundColor = {r=0, g=0, b=0, a=0.9}
    self.currentButton.borderColor = {r=0.7, g=0.7, b=0.7, a=0.3}
    self:addChild(self.currentButton)
end

function QuickRestartPanel:render()
    ISPanel.render(self)

    local textManager = getTextManager()
    local font = UIFont.Small
    local fontHeight = textManager:getFontHeight(font)

    if self.sandboxMode then
        local title = getText("UI_QuickRestart_SandboxConflict_Title")
        local titleWidth = textManager:MeasureStringX(UIFont.Medium, title)
        local titleX = (self.width - titleWidth) / 2
        local titleY = 10

        self:drawText(title, titleX-1, titleY, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(title, titleX+1, titleY, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(title, titleX, titleY-1, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(title, titleX, titleY+1, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(title, titleX, titleY, 1, 1, 1, 1, UIFont.Medium)

        local labelY = titleY + textManager:getFontHeight(UIFont.Medium) + 4
        local label = getText("UI_QuickRestart_SandboxConflictPanel_Label")
        local labelWidth = textManager:MeasureStringX(font, label)
        local labelX = (self.width - labelWidth) / 2
        self:drawText(label, labelX, labelY, 1, 1, 1, 1, font)

        local lineY = labelY + fontHeight + 8
        for _, l in ipairs(self.subtitleLines) do
            local lx = (self.width - textManager:MeasureStringX(font, l)) / 2
            self:drawText(l, lx, lineY, 1, 1, 1, 1, font)
            lineY = lineY + fontHeight + 2
        end

        local tooltipText = nil
        if self.savedButton and self.savedButton:isMouseOver() then
            tooltipText = getText("UI_QuickRestart_SandboxConflict_Saved_Tooltip")
        elseif self.currentButton and self.currentButton:isMouseOver() then
            tooltipText = getText("UI_QuickRestart_SandboxConflict_Current_Tooltip")
        end

        if tooltipText then
            local mouseX = getMouseX() - self:getAbsoluteX()
            local mouseY = getMouseY() - self:getAbsoluteY()
            drawTooltip(self, tooltipText, mouseX, mouseY)
        end
    else
        local text = getText("UI_QuickRestart_Title")
        local textWidth = textManager:MeasureStringX(UIFont.Medium, text)
        local x = (self.width - textWidth) / 2
        local y = 10

        self:drawText(text, x-1, y, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(text, x+1, y, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(text, x, y-1, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(text, x, y+1, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(text, x, y, 1, 1, 1, 1, UIFont.Medium)

        local function drawDisabledLabel(btn)
            if btn and btn.disabledLabel then
                local lw = textManager:MeasureStringX(font, btn.disabledLabel)
                local lx = btn:getX() + (btn:getWidth() - lw) / 2
                local ly = btn:getY() + (btn:getHeight() - fontHeight) / 2
                self:drawText(btn.disabledLabel, lx, ly, 0.6, 0.6, 0.6, 1, font)
            end
        end
        drawDisabledLabel(self.freshButton)
        drawDisabledLabel(self.sameButton)

        local tooltipText = nil
        if self.freshButton:isMouseOver() then
            if not self.freshWorldEnabled then
                tooltipText = getText("UI_QuickRestart_MP_Tooltip")
            elseif not self.charDataAvail then
                tooltipText = getText("UI_QuickRestart_NoData_Tooltip")
            else
                tooltipText = getText("UI_QuickRestart_FreshWorld_Tooltip")
            end
        elseif self.sameButton and self.sameButton:isMouseOver() then
            if not self.charDataAvail then
                tooltipText = getText("UI_QuickRestart_NoData_Tooltip")
            else
                tooltipText = getText("UI_QuickRestart_ThisWorld_Tooltip")
            end
        end

        if tooltipText then
            local mouseX = getMouseX() - self:getAbsoluteX()
            local mouseY = getMouseY() - self:getAbsoluteY()
            local padding = 5
            local textWidth = textManager:MeasureStringX(font, tooltipText)
            local textHeight = textManager:getFontHeight(font)
            local boxX = mouseX + 25
            local boxY = mouseY + 25
            local boxWidth = textWidth + padding * 2
            local boxHeight = textHeight + padding * 2
            self:drawRect(boxX, boxY, boxWidth, boxHeight, 0.9, 0, 0, 0)
            self:drawRectBorder(boxX, boxY, boxWidth, boxHeight, 1, 0.7, 0.7, 0.7)
            self:drawText(tooltipText, boxX + padding, boxY + padding, 1, 1, 1, 1, font)
        end
    end
end

restartPanel = nil

local function addRestartPanel()
    if restartPanel then return end

    local charDataAvail = false
    local player = getPlayer()
    if player then
        local playerIdentifier = getPlayerIdentifier(player)
        if playerIdentifier then
            local data = loadDataFromSaveFolder(playerIdentifier)
            if data then
                charDataAvail = data.name ~= nil
            end
        end
    end

    local core = getCore()
    local screenWidth = core:getScreenWidth()
    local screenHeight = core:getScreenHeight()

    local panelWidth = screenWidth * 0.08
    local panelHeight = screenHeight * 0.08
    local x = (screenWidth - panelWidth) / 2
    local y = screenHeight * 0.75

    restartPanel = QuickRestartPanel:new(x, y, panelWidth, panelHeight)
    restartPanel.charDataAvail = charDataAvail
    restartPanel:initialise()
    restartPanel:instantiate()
    restartPanel:addToUIManager()
    restartPanel:setVisible(true)
end

Events.OnPlayerDeath.Add(function(player)
    local ticks = 0
    local function waitForDeathScreen()
        ticks = ticks + 1
        if ticks >= 120 then
            Events.OnTick.Remove(waitForDeathScreen)
            addRestartPanel()
        end
    end
    Events.OnTick.Add(waitForDeathScreen)
end)


Events.OnNewGame.Add(function(player, square)
    if restartPanel then
        restartPanel:removeFromUIManager()
        restartPanel = nil
    end

    characterDataSaved = false

    local playerIdentifier = getPlayerIdentifier(player)
    local saveFilePath = getSaveFileNameForPlayer(playerIdentifier)
    local data = nil

    if QuickRestart.pendingSameWorld and QuickRestart.sameWorldData then
        data = QuickRestart.sameWorldData
        QuickRestart.pendingSameWorld = nil
        QuickRestart.sameWorldData = nil
    else
        data = QuickRestart.saveData
        QuickRestart.saveData = nil

        if not data or not data.name then
            data = loadDataFromFile()
        end
    end

    if not data or not data.name then
        if not characterDataSaved then
            local ticks = 0
            local function delayedSave()
                ticks = ticks + 1
                if ticks >= 60 then
                    characterDataSaved = true
                    Events.OnTick.Remove(delayedSave)
                    saveCharacterData(player, saveFilePath)
                end
            end
            Events.OnTick.Add(delayedSave)
        end
    else

    local desc = player:getDescriptor()

    if not isMultiplayer() and data.visual then
        local visual = player:getHumanVisual()
        local isFemale = desc:isFemale()
        local call = pcall

        if data.visual.hairModel then
            call(function() visual:setHairModel(data.visual.hairModel) end)
        end

        if data.visual.beardModel and data.visual.beardModel ~= "" then
            call(function() visual:setBeardModel(data.visual.beardModel) end)
        else
            call(function() visual:setBeardModel("") end)
        end

        if data.visual.hairColor then
            call(function()
                local color = ImmutableColor.new(data.visual.hairColor.r, data.visual.hairColor.g, data.visual.hairColor.b, 1)

                visual:setNaturalHairColor(color)
                visual:setHairColor(color)

                visual:setNaturalBeardColor(color)
                visual:setBeardColor(color)
            end)
        end

        if data.visual.skinTextureIndex ~= nil then
            call(function() visual:setSkinTextureIndex(data.visual.skinTextureIndex) end)
        end

        if data.visual.bodyHairIndex ~= nil then
            call(function() visual:setBodyHairIndex(data.visual.bodyHairIndex) end)
        end

        if data.visual.hairStubble ~= nil then
            call(function()
                if isFemale then
                    if data.visual.hairStubble then
                        visual:addBodyVisualFromItemType(F_HAIR_STUBBLE)
                    else
                        visual:removeBodyVisualFromItemType(F_HAIR_STUBBLE)
                    end
                else
                    if data.visual.hairStubble then
                        visual:addBodyVisualFromItemType(M_HAIR_STUBBLE)
                    else
                        visual:removeBodyVisualFromItemType(M_HAIR_STUBBLE)
                    end
                end
            end)
        end

        if data.visual.beardStubble ~= nil and not isFemale then
            call(function()
                if data.visual.beardStubble then
                    visual:addBodyVisualFromItemType(M_BEARD_STUBBLE)
                else
                    visual:removeBodyVisualFromItemType(M_BEARD_STUBBLE)
                end
            end)
        end

    end

    if data.voice then
        local call = pcall
        if data.voice.prefix then
            call(function() desc:setVoicePrefix(data.voice.prefix) end)
        end
        if data.voice.type ~= nil then
            call(function() desc:setVoiceType(data.voice.type) end)
        end
        if data.voice.pitch ~= nil then
            call(function() desc:setVoicePitch(data.voice.pitch) end)
        end
    end

    if data.traits and #data.traits > 0 then
        local characterTraits = player:getCharacterTraits()
        for _, traitStr in ipairs(data.traits) do
            local characterTrait = CharacterTrait.get(ResourceLocation.of(tostring(traitStr)))
            if characterTrait and not player:hasTrait(characterTrait) then
                characterTraits:add(characterTrait)
                player:modifyTraitXPBoost(characterTrait, false)
            end
        end
        SyncXp(player)
    end

    if data.skills then
        if isMultiplayer() then
            QuickRestart.pendingMPSkills = data.skills
        else

        local xp = player:getXp()

        local levelPerkHandlers = Events.LevelPerk.handlers
        Events.LevelPerk.handlers = {}

        for perkIndexStr, targetXP in pairs(data.skills) do
            local perkIndex = tonumber(perkIndexStr)
            if perkIndex then
                local perkEnum = Perks.fromIndex(perkIndex)
                local perk = PerkFactory.getPerk(perkEnum)
                if perk then
                    if targetXP == 0 then
                        player:setPerkLevelDebug(perkEnum, 0)
                        xp:setXPToLevel(perkEnum, 0)
                        print("[QuickRestart] skill perkIndex=" .. perkIndexStr .. " set to 0")
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
                        print("[QuickRestart] skill perkIndex=" .. perkIndexStr .. " level=" .. level .. " xp=" .. targetXP)
                    end
                end
            end
        end

        Events.LevelPerk.handlers = levelPerkHandlers
        end
    end

    if data.clothing then
        local function restoreClothing()
            local hasStarterKit = SandboxVars and SandboxVars.StarterKit
            local inventory = player:getInventory()
            local call = pcall
            local isInstance = instanceof

            player:clearWornItems()

            for i, clothingData in ipairs(data.clothing) do
                if clothingData.type then
                    local success, item = call(function() return inventory:AddItem(clothingData.type) end)
                    if success and item then
                        if hasStarterKit and isInstance(item, INVENTORY_CONTAINER) then
                            inventory:Remove(item)
                            local existing = inventory:getItems()
                            for j = 0, existing:size() - 1 do
                                local existingItem = existing:get(j)
                                if isInstance(existingItem, INVENTORY_CONTAINER) then
                                    if clothingData.color then
                                        call(function()
                                            existingItem:setColorRed(clothingData.color.r)
                                            existingItem:setColorGreen(clothingData.color.g)
                                            existingItem:setColorBlue(clothingData.color.b)
                                            existingItem:setColor(Color.new(clothingData.color.r, clothingData.color.g, clothingData.color.b))
                                            existingItem:setCustomColor(true)
                                        end)
                                    end
                                    local visual = nil
                                    call(function() visual = existingItem:getVisual() end)
                                    if visual then
                                        if clothingData.baseTexture and visual.setBaseTexture then
                                            call(function() visual:setBaseTexture(clothingData.baseTexture) end)
                                        end
                                        if clothingData.textureChoice and visual.setTextureChoice then
                                            call(function() visual:setTextureChoice(clothingData.textureChoice) end)
                                        end
                                    end
                                    call(function() existingItem:synchWithVisual() end)
                                    call(function() player:setClothingItem_Back(existingItem) end)
                                    break
                                end
                            end
                        else
                            if clothingData.color then
                                call(function()
                                    item:setColorRed(clothingData.color.r)
                                    item:setColorGreen(clothingData.color.g)
                                    item:setColorBlue(clothingData.color.b)
                                    item:setColor(Color.new(clothingData.color.r, clothingData.color.g, clothingData.color.b))
                                    item:setCustomColor(true)
                                end)
                            end

                            local visual = nil
                            call(function() visual = item:getVisual() end)

                            if visual then
                                if clothingData.baseTexture and visual.setBaseTexture then
                                    call(function() visual:setBaseTexture(clothingData.baseTexture) end)
                                end

                                if clothingData.textureChoice and visual.setTextureChoice then
                                    call(function() visual:setTextureChoice(clothingData.textureChoice) end)
                                end
                            end

                            call(function() item:synchWithVisual() end)

                            if item.getBodyLocation then
                                local bodyLoc = item:getBodyLocation()

                                if bodyLoc then
                                    call(function()
                                        player:setWornItem(bodyLoc, item)
                                    end)
                                end
                            end
                        end
                    end
                end
            end

            triggerEvent("OnClothingUpdated", player)
        end

        local ticks = 0
        local function waitForClothing()
            ticks = ticks + 1
            if ticks >= 10 then
                restoreClothing()
                Events.OnTick.Remove(waitForClothing)
            end
        end
        Events.OnTick.Add(waitForClothing)
    end

        writeDataToFile(data, saveFilePath, data.sandbox)
        deleteDataFile()
    end

    local sandboxTicks = 0
    local function delayedSandboxCapture()
        sandboxTicks = sandboxTicks + 1
        if sandboxTicks >= 60 then
            Events.OnTick.Remove(delayedSandboxCapture)
            saveSandboxData(saveFilePath)
        end
    end
    Events.OnTick.Add(delayedSandboxCapture)
end)

Events.OnGameTimeLoaded.Add(function()
    if not isClient() then return end
    if not QuickRestart.pendingMPSkills then return end
    sendClientCommand("QuickRestart", "applySkills", {skills = QuickRestart.pendingMPSkills})
    QuickRestart.pendingMPSkills = nil
end)
