QuickRestartRandomizer = QuickRestartRandomizer or {}

local MIN_LEFTOVER = 0
local MAX_LEFTOVER = 5
local MAX_CONVERGE_ITERATIONS = 1000
local MAX_TRAIT_COUNT = 40
local MAX_CLOTHING_ENTRIES = 20
local MAX_FORENAME_LENGTH = 64

local function logInfo(message)
    if QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("randomizer " .. tostring(message))
    end
end

local function logWarn(message)
    if QuickRestartLog and QuickRestartLog.warn then
        QuickRestartLog.warn("randomizer " .. tostring(message))
    end
end

local function deepCopy(value, visited)
    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return value
    end

    if valueType ~= "table" then
        return nil
    end

    visited = visited or {}
    if visited[value] then
        return visited[value]
    end

    local copy = {}
    visited[value] = copy

    for key, childValue in pairs(value) do
        local keyType = type(key)
        if keyType == "string" or keyType == "number" or keyType == "boolean" then
            local copiedValue = deepCopy(childValue, visited)
            if copiedValue ~= nil then
                copy[key] = copiedValue
            end
        end
    end

    return copy
end

local function getTraitKey(def)
    return tostring(def:getType())
end

local function resolveProfessionDefinition(professionType)
    if type(professionType) ~= "string" or professionType == "" then
        return nil
    end

    local ok, def = pcall(function()
        local characterProfession = CharacterProfession.get(ResourceLocation.of(professionType))
        if not characterProfession then
            return nil
        end
        return CharacterProfessionDefinition.getCharacterProfessionDefinition(characterProfession)
    end)
    if not ok then
        return nil
    end
    return def
end

local function resolveTraitDefinition(traitString)
    if type(traitString) ~= "string" or traitString == "" then
        return nil
    end

    local ok, def = pcall(function()
        local characterTrait = CharacterTrait.get(ResourceLocation.of(traitString))
        if not characterTrait then
            return nil
        end
        return CharacterTraitDefinition.getCharacterTraitDefinition(characterTrait)
    end)
    if not ok then
        return nil
    end
    return def
end

local function isTraitEnabled(def)
    local ok, enabled = pcall(function()
        local traitType = def:getType()
        if traitType == CharacterTrait.INSOMNIAC
            or traitType == CharacterTrait.NEEDS_LESS_SLEEP
            or traitType == CharacterTrait.NEEDS_MORE_SLEEP then
            if not isMultiplayer() and not isServer() then
                return true
            end
            local serverOptions = getServerOptions()
            return serverOptions ~= nil
                and serverOptions:getBoolean("SleepAllowed")
                and serverOptions:getBoolean("SleepNeeded")
        end
        return true
    end)
    return ok and enabled == true
end

local function negativeTraitOffset(badCount)
    if badCount <= 0 then
        return 0
    end

    local penalty = 1
    pcall(function()
        penalty = getSandboxOptions():getOptionByName("NegativeTraitsPenalty"):getValue()
    end)

    if penalty == 2 then
        return math.floor(badCount / 3)
    end
    if penalty == 3 then
        return math.floor(badCount / 2)
    end
    if penalty == 4 then
        return badCount - 1
    end
    return 0
end

local function forEachGrantedDefinition(def, callback)
    local ok, grantedList = pcall(function() return def:getGrantedTraits() end)
    if not ok or not grantedList then
        return
    end

    local size = 0
    pcall(function() size = grantedList:size() end)
    for i = 0, size - 1 do
        local grantedDef = nil
        pcall(function()
            grantedDef = CharacterTraitDefinition.getCharacterTraitDefinition(grantedList:get(i))
        end)
        if grantedDef then
            callback(grantedDef)
        end
    end
end

local function collectGrantedClosure(professionDef, defs)
    local closure = {}

    local function addWithGrants(def)
        local key = getTraitKey(def)
        if closure[key] then
            return
        end
        closure[key] = def
        forEachGrantedDefinition(def, addWithGrants)
    end

    local ok, profGranted = pcall(function() return professionDef:getGrantedTraits() end)
    if ok and profGranted then
        local size = 0
        pcall(function() size = profGranted:size() end)
        for i = 0, size - 1 do
            local grantedDef = nil
            pcall(function()
                grantedDef = CharacterTraitDefinition.getCharacterTraitDefinition(profGranted:get(i))
            end)
            if grantedDef then
                addWithGrants(grantedDef)
            end
        end
    end

    for _, def in ipairs(defs) do
        forEachGrantedDefinition(def, addWithGrants)
    end

    return closure
end

local function computeBudgetForDefs(professionDef, defs)
    local base = 0
    local okCost, professionCost = pcall(function() return professionDef:getCost() end)
    if okCost and type(professionCost) == "number" then
        base = professionCost
    end
    if SandboxVars and type(SandboxVars.CharacterFreePoints) == "number" then
        base = base + SandboxVars.CharacterFreePoints
    end

    local closure = collectGrantedClosure(professionDef, defs)
    local spent = 0
    local badCount = 0
    local seen = {}

    for _, def in ipairs(defs) do
        local key = getTraitKey(def)
        if not seen[key] then
            seen[key] = true
            local okMeta, isFree, cost = pcall(function()
                return def:isFree(), def:getCost()
            end)
            if okMeta and not isFree and not closure[key] and type(cost) == "number" then
                spent = spent + cost
                if cost < 0 then
                    badCount = badCount + 1
                end
            end
        end
    end

    return base - spent - negativeTraitOffset(badCount)
end

local function isExcludedBySelection(selection, def)
    for _, entry in ipairs(selection.ordered) do
        local excluded = false
        local ok = pcall(function()
            excluded = entry.def == def
                or def:isMutuallyExclusive(entry.def)
                or entry.def:isMutuallyExclusive(def)
        end)
        if ok and excluded then
            return true
        end
    end
    return false
end

local addSelectionEntry
addSelectionEntry = function(selection, def, paid)
    local key = getTraitKey(def)
    if selection.byKey[key] then
        return false
    end

    local entry = {def = def, key = key, paid = paid}
    selection.ordered[#selection.ordered + 1] = entry
    selection.byKey[key] = entry

    forEachGrantedDefinition(def, function(grantedDef)
        addSelectionEntry(selection, grantedDef, false)
    end)

    return true
end

local function newSelectionForProfession(professionDef)
    local selection = {ordered = {}, byKey = {}}

    local ok, profGranted = pcall(function() return professionDef:getGrantedTraits() end)
    if ok and profGranted then
        local size = 0
        pcall(function() size = profGranted:size() end)
        for i = 0, size - 1 do
            local grantedDef = nil
            pcall(function()
                grantedDef = CharacterTraitDefinition.getCharacterTraitDefinition(profGranted:get(i))
            end)
            if grantedDef then
                addSelectionEntry(selection, grantedDef, false)
            end
        end
    end

    return selection
end

local function rebuildSelectionWithoutPaidKey(selection, professionDef, keyToRemove)
    local rebuilt = newSelectionForProfession(professionDef)
    for _, entry in ipairs(selection.ordered) do
        if entry.paid and entry.key ~= keyToRemove then
            addSelectionEntry(rebuilt, entry.def, true)
        end
    end
    return rebuilt
end

local function selectionDefs(selection)
    local defs = {}
    for _, entry in ipairs(selection.ordered) do
        defs[#defs + 1] = entry.def
    end
    return defs
end

local function buildCandidatePools(selection)
    local goodPool = {}
    local badPool = {}

    local ok, traitList = pcall(function() return CharacterTraitDefinition.getTraits() end)
    if not ok or not traitList then
        return goodPool, badPool
    end

    local count = 0
    pcall(function() count = traitList:size() end)
    for i = 0, count - 1 do
        local def = nil
        pcall(function() def = traitList:get(i) end)
        if def then
            local okMeta, isFree, cost = pcall(function()
                return def:isFree(), def:getCost()
            end)
            if okMeta and not isFree and type(cost) == "number" and cost ~= 0
                and isTraitEnabled(def) and not isExcludedBySelection(selection, def) then
                if cost > 0 then
                    goodPool[#goodPool + 1] = def
                else
                    badPool[#badPool + 1] = def
                end
            end
        end
    end

    return goodPool, badPool
end

function QuickRestartRandomizer.rollGender()
    if ZombRand(2) == 0 then
        return "female"
    end
    return "male"
end

function QuickRestartRandomizer.rollProfession()
    local ok, professionType = pcall(function()
        local professions = CharacterProfessionDefinition.getProfessions()
        if not professions or professions:size() == 0 then
            return nil
        end
        local def = professions:get(ZombRand(professions:size()))
        if not def then
            return nil
        end
        return tostring(def:getType())
    end)
    if not ok or type(professionType) ~= "string" or professionType == "" then
        return nil
    end
    return professionType
end

function QuickRestartRandomizer.computeTraitBudget(professionType, traitStrings)
    local professionDef = resolveProfessionDefinition(professionType)
    if not professionDef then
        return nil, "unknown_profession"
    end

    if type(traitStrings) ~= "table" then
        return nil, "traits_not_table"
    end

    local defs = {}
    for _, traitString in ipairs(traitStrings) do
        local def = resolveTraitDefinition(traitString)
        if not def then
            return nil, "unknown_trait"
        end
        defs[#defs + 1] = def
    end

    return computeBudgetForDefs(professionDef, defs)
end

function QuickRestartRandomizer.rollTraits(professionType)
    local professionDef = resolveProfessionDefinition(professionType)
    if not professionDef then
        return nil, "unknown_profession"
    end

    local selection = newSelectionForProfession(professionDef)

    local function addRandomFromPool(pool)
        if #pool == 0 then
            return false
        end
        return addSelectionEntry(selection, pool[ZombRand(#pool) + 1], true)
    end

    local function addRandomGood()
        local goodPool = buildCandidatePools(selection)
        return addRandomFromPool(goodPool)
    end

    local function addRandomBad()
        local _, badPool = buildCandidatePools(selection)
        return addRandomFromPool(badPool)
    end

    local function removeRandomPaid(sign, maxMagnitude)
        local candidates = {}
        for _, entry in ipairs(selection.ordered) do
            if entry.paid then
                local okCost, cost = pcall(function() return entry.def:getCost() end)
                if okCost and type(cost) == "number"
                    and ((sign > 0 and cost > 0) or (sign < 0 and cost < 0))
                    and math.abs(cost) <= maxMagnitude then
                    candidates[#candidates + 1] = entry.key
                end
            end
        end
        if #candidates == 0 then
            return false
        end
        selection = rebuildSelectionWithoutPaidKey(selection, professionDef, candidates[ZombRand(#candidates) + 1])
        return true
    end

    for _ = 1, ZombRand(5) + 1 do
        addRandomGood()
    end
    for _ = 1, ZombRand(5) + 1 do
        addRandomBad()
    end

    local leftover = computeBudgetForDefs(professionDef, selectionDefs(selection))
    local iterations = MAX_CONVERGE_ITERATIONS
    while iterations > 0 and (leftover < MIN_LEFTOVER or leftover > MAX_LEFTOVER) do
        iterations = iterations - 1
        if leftover < MIN_LEFTOVER then
            if ZombRand(2) == 0 then
                removeRandomPaid(1, math.abs(leftover))
            else
                addRandomBad()
            end
        else
            if ZombRand(2) == 0 then
                removeRandomPaid(-1, math.abs(leftover))
            else
                addRandomGood()
            end
        end
        leftover = computeBudgetForDefs(professionDef, selectionDefs(selection))
    end

    if leftover < MIN_LEFTOVER or leftover > MAX_LEFTOVER then
        return nil, "budget_unreachable"
    end

    if #selection.ordered > MAX_TRAIT_COUNT then
        return nil, "too_many_traits"
    end

    local traits = {}
    for _, entry in ipairs(selection.ordered) do
        traits[#traits + 1] = entry.key
    end

    return {traits = traits, leftover = leftover}
end

function QuickRestartRandomizer.validateTraitSelection(professionType, traitStrings)
    if type(traitStrings) ~= "table" then
        return false, "traits_not_table"
    end

    if #traitStrings > MAX_TRAIT_COUNT then
        return false, "too_many_traits"
    end

    local defs = {}
    local seen = {}
    for _, traitString in ipairs(traitStrings) do
        if type(traitString) ~= "string" or traitString == "" then
            return false, "invalid_trait_entry"
        end
        local def = resolveTraitDefinition(traitString)
        if not def then
            return false, "unknown_trait"
        end
        local key = getTraitKey(def)
        if seen[key] then
            return false, "duplicate_trait"
        end
        seen[key] = true
        if not isTraitEnabled(def) then
            return false, "trait_disabled"
        end
        defs[#defs + 1] = def
    end

    for i = 1, #defs do
        for j = i + 1, #defs do
            local excluded = false
            pcall(function()
                excluded = defs[i]:isMutuallyExclusive(defs[j]) or defs[j]:isMutuallyExclusive(defs[i])
            end)
            if excluded then
                return false, "mutually_exclusive_traits"
            end
        end
    end

    local leftover, reason = QuickRestartRandomizer.computeTraitBudget(professionType, traitStrings)
    if leftover == nil then
        return false, reason
    end
    if leftover < MIN_LEFTOVER or leftover > MAX_LEFTOVER then
        return false, "trait_budget_out_of_range"
    end

    return true
end

function QuickRestartRandomizer.rollVisual(gender)
    local ok, result = pcall(function()
        if not SurvivorFactory or not SurvivorFactory.CreateSurvivor then
            return nil
        end

        local female = gender == "female"
        local tempDesc = SurvivorFactory.CreateSurvivor(SurvivorType.Neutral, female)
        if not tempDesc then
            return nil
        end

        local visual = {
            hairStubble = false,
            beardStubble = false,
        }
        local humanVisual = tempDesc:getHumanVisual()
        if humanVisual then
            local okField, value = pcall(function() return humanVisual:getHairModel() end)
            if okField and value ~= nil then
                visual.hairModel = tostring(value)
            end

            if female then
                visual.beardModel = ""
            else
                okField, value = pcall(function() return humanVisual:getBeardModel() end)
                if okField and value ~= nil then
                    visual.beardModel = tostring(value)
                end
            end

            okField, value = pcall(function() return humanVisual:getNaturalHairColor() end)
            if okField and value then
                visual.hairColor = {
                    r = value:getRedFloat(),
                    g = value:getGreenFloat(),
                    b = value:getBlueFloat(),
                }
            end

            okField, value = pcall(function() return humanVisual:getSkinTextureIndex() end)
            if okField and type(value) == "number" then
                visual.skinTextureIndex = value
            end

            okField, value = pcall(function() return humanVisual:getBodyHairIndex() end)
            if okField and type(value) == "number" then
                visual.bodyHairIndex = value
            end
        end

        local forename = nil
        local okName, name = pcall(function() return tempDesc:getForename() end)
        if okName and type(name) == "string" and name ~= "" then
            forename = name
        end

        return {visual = visual, forename = forename}
    end)
    if not ok or type(result) ~= "table" then
        return nil, nil
    end
    return result.visual, result.forename
end

function QuickRestartRandomizer.rollVoice(gender)
    local female = gender == "female"
    local ok, voice = pcall(function()
        local prefix = female and "VoiceFemale" or "VoiceMale"
        local voiceType = 0

        if getAllVoiceStyles then
            local styles = getAllVoiceStyles()
            if styles then
                local wantedBodyType = female and 1 or 2
                local choices = {}
                for i = 0, styles:size() - 1 do
                    local style = styles:get(i)
                    if style and style:getBodyTypeDefault() == wantedBodyType then
                        choices[#choices + 1] = style
                    end
                end

                if #choices > 0 then
                    local style = choices[ZombRand(#choices) + 1]
                    if style:getPrefix() ~= nil then
                        prefix = tostring(style:getPrefix())
                    end
                    if style:getVoiceType() ~= nil then
                        voiceType = tonumber(style:getVoiceType()) or 0
                    end
                end
            end
        end

        return {
            prefix = prefix,
            type = voiceType,
            pitch = ZombRand(201) - 100,
        }
    end)
    if not ok or type(voice) ~= "table" then
        return nil
    end
    return voice
end

function QuickRestartRandomizer.rollClothing(professionType, gender, traitStrings)
    local ok, clothing = pcall(function()
        if not ClothingSelectionDefinitions or not instanceItem then
            return nil
        end

        local female = gender == "female"
        local outfitByLocation = {}
        local locationOrder = {}

        local function applyDefinition(definition)
            if type(definition) ~= "table" then
                return
            end
            for bodyLocation, locationTable in pairs(definition) do
                if type(locationTable) == "table" and type(locationTable.items) == "table" and #locationTable.items > 0 then
                    local chance = locationTable.chance
                    if not chance or ZombRand(100) < chance then
                        if outfitByLocation[bodyLocation] == nil then
                            locationOrder[#locationOrder + 1] = bodyLocation
                        end
                        outfitByLocation[bodyLocation] = locationTable.items[ZombRand(#locationTable.items) + 1]
                    end
                end
            end
        end

        local function applyGenderedDefinition(definition)
            if type(definition) ~= "table" then
                return
            end
            if female then
                applyDefinition(definition.Female)
            elseif definition.Male then
                applyDefinition(definition.Male)
            else
                applyDefinition(definition.Female)
            end
        end

        applyGenderedDefinition(ClothingSelectionDefinitions.default)

        local professionName = nil
        pcall(function()
            local characterProfession = CharacterProfession.get(ResourceLocation.of(tostring(professionType)))
            if characterProfession then
                professionName = characterProfession:getName()
            end
        end)
        if professionName and ClothingSelectionDefinitions[professionName] then
            applyGenderedDefinition(ClothingSelectionDefinitions[professionName])
        end

        if TraitClothingSelectionDefinitions and type(traitStrings) == "table" then
            for _, traitString in ipairs(traitStrings) do
                pcall(function()
                    local characterTrait = CharacterTrait.get(ResourceLocation.of(tostring(traitString)))
                    if characterTrait and TraitClothingSelectionDefinitions[characterTrait] then
                        applyGenderedDefinition(TraitClothingSelectionDefinitions[characterTrait])
                    end
                end)
            end
        end

        local entries = {}
        for _, bodyLocation in ipairs(locationOrder) do
            local itemType = outfitByLocation[bodyLocation]
            if type(itemType) == "string" and itemType ~= "" and #entries < MAX_CLOTHING_ENTRIES then
                local item = instanceItem(itemType)
                if item then
                    local entry = {type = itemType}

                    local okType, fullType = pcall(function() return item:getFullType() end)
                    if okType and type(fullType) == "string" and fullType ~= "" then
                        entry.type = fullType
                    end

                    local okLoc, bodyLoc = pcall(function() return item:getBodyLocation() end)
                    if okLoc and bodyLoc ~= nil and tostring(bodyLoc) ~= "" then
                        entry.bodyLocation = tostring(bodyLoc)
                    end

                    entries[#entries + 1] = entry
                end
            end
        end

        return entries
    end)
    if not ok or type(clothing) ~= "table" then
        return nil
    end
    return clothing
end

function QuickRestartRandomizer.pickRandomRegion(regions)
    if type(regions) ~= "table" or #regions == 0 then
        return nil
    end
    return regions[ZombRand(#regions) + 1]
end

local EXCLUDED_SANDBOX_OPTIONS = {
    CharacterFreePoints = true,
    NegativeTraitsPenalty = true,
}

local ZOMBIE_RESPAWN_HOURS = {16.0, 72.0, 216.0, 0.0}
local ZOMBIE_RESPAWN_UNSEEN_HOURS = {6.0, 16.0, 48.0, 0.0}
local ZOMBIE_RESPAWN_MULTIPLIER = {0.5, 0.1, 0.05, 0.0}

local function isZombieOptionName(name)
    return name == "Zombies"
        or name == "ZombieRespawn"
        or name == "ZombieMigrate"
        or string.find(name, "ZombieLore.", 1, true) == 1
        or string.find(name, "ZombieConfig.", 1, true) == 1
end

local function writeSandboxPath(sandboxTable, name, value)
    local container = sandboxTable
    local segments = {}
    for segment in string.gmatch(name, "[^%.]+") do
        segments[#segments + 1] = segment
    end

    for i = 1, #segments - 1 do
        if type(container[segments[i]]) ~= "table" then
            container[segments[i]] = {}
        end
        container = container[segments[i]]
    end

    container[segments[#segments]] = value
end

local function rollSandboxOptionValue(option)
    local optionType = nil
    local ok = pcall(function() optionType = option:getType() end)
    if not ok or type(optionType) ~= "string" then
        return nil
    end

    if optionType == "boolean" then
        return ZombRand(2) == 0
    end

    if optionType == "enum" then
        local numValues = nil
        pcall(function() numValues = option:getNumValues() end)
        if type(numValues) == "number" and numValues > 0 then
            return ZombRand(numValues) + 1
        end
        return nil
    end

    if optionType == "integer" or optionType == "double" then
        local minValue = nil
        local maxValue = nil
        pcall(function()
            minValue = option:getMin()
            maxValue = option:getMax()
        end)
        if type(minValue) == "number" and type(maxValue) == "number" and maxValue > minValue then
            local span = math.floor(maxValue - minValue)
            if span > 0 then
                return minValue + ZombRand(span + 1)
            end
        end
        return nil
    end

    return nil
end

local function applyZombieLinkedValues(sandboxTable, name, value)
    if name == "Zombies" and ZombiePopulationMultiplierTable then
        local multiplier = tonumber(ZombiePopulationMultiplierTable[value])
        if multiplier then
            writeSandboxPath(sandboxTable, "ZombieConfig.PopulationMultiplier", multiplier)
        end
        return
    end

    if name == "ZombieRespawn" then
        if ZOMBIE_RESPAWN_HOURS[value] then
            writeSandboxPath(sandboxTable, "ZombieConfig.RespawnHours", ZOMBIE_RESPAWN_HOURS[value])
            writeSandboxPath(sandboxTable, "ZombieConfig.RespawnUnseenHours", ZOMBIE_RESPAWN_UNSEEN_HOURS[value])
            writeSandboxPath(sandboxTable, "ZombieConfig.RespawnMultiplier", ZOMBIE_RESPAWN_MULTIPLIER[value])
        end
        return
    end

    if name == "ZombieMigrate" then
        writeSandboxPath(sandboxTable, "ZombieConfig.RedistributeHours", value == true and 12.0 or 0.0)
    end
end

function QuickRestartRandomizer.rollSandbox(sandboxTable, options)
    if type(sandboxTable) ~= "table" then
        return nil
    end

    local sanitized = QuickRestartRestartOptions.sanitize(options)
    local RANDOM = QuickRestartRestartOptions.RANDOM
    local randomizeSandbox = sanitized.sandbox == RANDOM
    local randomizeZombies = sanitized.zombies == RANDOM

    if not randomizeSandbox and not randomizeZombies then
        return nil
    end

    local ok, result = pcall(function()
        local sandboxOptions = getSandboxOptions()
        if not sandboxOptions then
            return nil
        end

        local rolled = deepCopy(sandboxTable)
        local rolledCount = 0

        for i = 1, sandboxOptions:getNumOptions() do
            local option = sandboxOptions:getOptionByIndex(i - 1)
            if option then
                local name = nil
                pcall(function() name = option:getName() end)
                if type(name) == "string" and name ~= "" and not EXCLUDED_SANDBOX_OPTIONS[name] then
                    local zombieOption = isZombieOptionName(name)
                    local shouldRoll = (zombieOption and randomizeZombies) or (not zombieOption and randomizeSandbox)
                    if shouldRoll then
                        local value = rollSandboxOptionValue(option)
                        if value ~= nil then
                            writeSandboxPath(rolled, name, value)
                            if zombieOption then
                                applyZombieLinkedValues(rolled, name, value)
                            end
                            rolledCount = rolledCount + 1
                        end
                    end
                end
            end
        end

        logInfo("rollSandbox randomized options=" .. tostring(rolledCount)
            .. " sandbox=" .. tostring(randomizeSandbox)
            .. " zombies=" .. tostring(randomizeZombies))

        return rolled
    end)

    if not ok or type(result) ~= "table" then
        logWarn("rollSandbox failed, keeping saved sandbox settings")
        return nil
    end

    return result
end

function QuickRestartRandomizer.ensureProfessionGrantedTraits(professionType, traitStrings)
    local baseTraits = {}
    if type(traitStrings) == "table" then
        for _, traitString in ipairs(traitStrings) do
            if type(traitString) == "string" and traitString ~= "" then
                baseTraits[#baseTraits + 1] = traitString
            end
        end
    end

    local professionDef = resolveProfessionDefinition(professionType)
    if not professionDef then
        return baseTraits, 0
    end

    local seen = {}
    for _, traitString in ipairs(baseTraits) do
        local def = resolveTraitDefinition(traitString)
        if def then
            seen[getTraitKey(def)] = true
        else
            seen[traitString] = true
        end
    end

    local added = 0
    local closure = collectGrantedClosure(professionDef, {})
    for key in pairs(closure) do
        if not seen[key] then
            seen[key] = true
            baseTraits[#baseTraits + 1] = key
            added = added + 1
        end
    end

    return baseTraits, added
end

function QuickRestartRandomizer.fitTraitsToBudget(professionType, traitStrings)
    local traits = {}
    if type(traitStrings) == "table" then
        for _, traitString in ipairs(traitStrings) do
            if type(traitString) == "string" and traitString ~= "" then
                traits[#traits + 1] = traitString
            end
        end
    end

    local professionDef = resolveProfessionDefinition(professionType)
    if not professionDef then
        return traits, 0, nil
    end

    local removed = 0

    while true do
        local resolvedDefs = {}
        for _, traitString in ipairs(traits) do
            local def = resolveTraitDefinition(traitString)
            if def then
                resolvedDefs[#resolvedDefs + 1] = def
            end
        end

        local leftover = computeBudgetForDefs(professionDef, resolvedDefs)
        if leftover >= MIN_LEFTOVER then
            return traits, removed, leftover
        end

        local closure = collectGrantedClosure(professionDef, resolvedDefs)
        local removeIndex = nil
        local removeCost = nil
        for index, traitString in ipairs(traits) do
            local def = resolveTraitDefinition(traitString)
            if def then
                local key = getTraitKey(def)
                local okMeta, isFree, cost = pcall(function()
                    return def:isFree(), def:getCost()
                end)
                if okMeta and not isFree and not closure[key] and type(cost) == "number" and cost > 0 then
                    if removeCost == nil or cost > removeCost then
                        removeIndex = index
                        removeCost = cost
                    end
                end
            end
        end

        if not removeIndex then
            return nil, removed, leftover
        end

        table.remove(traits, removeIndex)
        removed = removed + 1
    end
end

function QuickRestartRandomizer.transformSnapshot(snapshot, options)
    if type(snapshot) ~= "table" then
        return snapshot, nil
    end

    local sanitized = QuickRestartRestartOptions.sanitize(options)
    local transformed = deepCopy(snapshot)
    transformed.options = QuickRestartRestartOptions.sanitize(options)
    local deltas = {}
    local RANDOM = QuickRestartRestartOptions.RANDOM

    if sanitized.profession == RANDOM then
        local professionType = QuickRestartRandomizer.rollProfession()
        if professionType then
            transformed.profession = professionType
            deltas.profession = professionType
            logInfo("transform profession=" .. professionType)
        else
            logWarn("transform profession roll failed, keeping saved profession")
        end
    end

    local effectiveProfession = transformed.profession or snapshot.profession

    if sanitized.traits == RANDOM then
        local result, reason = QuickRestartRandomizer.rollTraits(effectiveProfession)
        if result then
            transformed.traits = result.traits
            deltas.traits = deepCopy(result.traits)
            logInfo("transform traits count=" .. tostring(#result.traits) .. " leftover=" .. tostring(result.leftover))
        else
            logWarn("transform traits roll failed reason=" .. tostring(reason) .. ", keeping saved traits")
        end
    end

    if deltas.profession ~= nil and deltas.traits == nil then
        local ensuredTraits, addedCount = QuickRestartRandomizer.ensureProfessionGrantedTraits(effectiveProfession, transformed.traits)
        local fittedTraits, removedCount, leftover = QuickRestartRandomizer.fitTraitsToBudget(effectiveProfession, ensuredTraits)
        if fittedTraits then
            transformed.traits = fittedTraits
            if addedCount > 0 or removedCount > 0 then
                logInfo("transform kept traits adjusted for new profession added=" .. tostring(addedCount)
                    .. " removed=" .. tostring(removedCount)
                    .. " leftover=" .. tostring(leftover))
            end
        else
            transformed.profession = snapshot.profession
            deltas.profession = nil
            effectiveProfession = snapshot.profession
            logWarn("transform profession roll reverted: kept traits cannot fit budget leftover=" .. tostring(leftover))
        end
    end

    if sanitized.gender == RANDOM then
        local gender = QuickRestartRandomizer.rollGender()
        if gender ~= snapshot.gender then
            local visual, forename = QuickRestartRandomizer.rollVisual(gender)
            local voice = QuickRestartRandomizer.rollVoice(gender)
            if visual and voice and forename then
                transformed.gender = gender
                transformed.visual = visual
                transformed.voice = voice
                transformed.forename = forename
                transformed.name = forename .. " " .. tostring(transformed.surname or "")
                deltas.gender = gender
                deltas.visual = deepCopy(visual)
                deltas.voice = deepCopy(voice)
                deltas.forename = forename
                logInfo("transform gender=" .. gender .. " forename=" .. tostring(forename))
            else
                logWarn("transform gender flip aborted: visual, voice or name roll failed, keeping saved gender")
            end
        else
            logInfo("transform gender roll matched saved gender")
        end
    end

    if sanitized.clothing == RANDOM then
        local clothing = QuickRestartRandomizer.rollClothing(
            effectiveProfession,
            transformed.gender or snapshot.gender,
            transformed.traits or snapshot.traits
        )
        if clothing then
            transformed.clothing = clothing
            deltas.clothing = deepCopy(clothing)
            logInfo("transform clothing count=" .. tostring(#clothing))
        else
            logWarn("transform clothing roll failed, keeping saved clothing")
        end
    end

    local hasDeltas = false
    for _ in pairs(deltas) do
        hasDeltas = true
        break
    end

    return transformed, hasDeltas and deltas or nil
end

function QuickRestartRandomizer.mergeDeltasOntoSnapshot(snapshot, deltas)
    if type(snapshot) ~= "table" then
        return nil
    end

    local merged = deepCopy(snapshot)
    if type(deltas) ~= "table" then
        return merged
    end

    if deltas.profession ~= nil then
        merged.profession = tostring(deltas.profession)
    end
    if type(deltas.traits) == "table" then
        merged.traits = deepCopy(deltas.traits)
    end
    if deltas.gender ~= nil then
        merged.gender = tostring(deltas.gender)
    end
    if type(deltas.visual) == "table" then
        merged.visual = deepCopy(deltas.visual)
    end
    if type(deltas.voice) == "table" then
        merged.voice = deepCopy(deltas.voice)
    end
    if deltas.forename ~= nil then
        merged.forename = tostring(deltas.forename)
        merged.name = merged.forename .. " " .. tostring(merged.surname or "")
    end
    if type(deltas.clothing) == "table" then
        merged.clothing = deepCopy(deltas.clothing)
    end

    if deltas.profession ~= nil and deltas.traits == nil then
        local ensuredTraits = QuickRestartRandomizer.ensureProfessionGrantedTraits(merged.profession, merged.traits)
        local fittedTraits, removedCount, leftover = QuickRestartRandomizer.fitTraitsToBudget(merged.profession, ensuredTraits)
        if fittedTraits then
            merged.traits = fittedTraits
            if removedCount and removedCount > 0 then
                logInfo("merge kept traits trimmed for new profession removed=" .. tostring(removedCount)
                    .. " leftover=" .. tostring(leftover))
            end
        else
            merged.profession = tostring(snapshot.profession or merged.profession)
            merged.traits = deepCopy(snapshot.traits)
            logWarn("merge profession delta reverted: kept traits cannot fit budget leftover=" .. tostring(leftover))
        end
    end

    return merged
end

function QuickRestartRandomizer.validateRandomizedResult(baseline, deltas)
    if type(baseline) ~= "table" then
        return false, "missing_baseline"
    end
    if type(deltas) ~= "table" then
        return false, "missing_deltas"
    end

    if deltas.gender ~= nil and deltas.gender ~= "male" and deltas.gender ~= "female" then
        return false, "invalid_gender"
    end

    if deltas.profession ~= nil then
        if type(deltas.profession) ~= "string" or not QuickRestartValidate.professionExists(deltas.profession) then
            return false, "invalid_profession"
        end
    end

    local effectiveProfession = deltas.profession or baseline.profession

    if deltas.traits ~= nil then
        local ok, reason = QuickRestartRandomizer.validateTraitSelection(effectiveProfession, deltas.traits)
        if not ok then
            return false, reason
        end
    end

    if deltas.clothing ~= nil then
        if type(deltas.clothing) ~= "table" or #deltas.clothing > MAX_CLOTHING_ENTRIES then
            return false, "invalid_clothing"
        end
        for _, entry in ipairs(deltas.clothing) do
            if type(entry) ~= "table" or type(entry.type) ~= "string" or entry.type == "" then
                return false, "invalid_clothing_entry"
            end
            if entry.bodyLocation ~= nil and type(entry.bodyLocation) ~= "string" then
                return false, "invalid_clothing_body_location"
            end
            local exists = false
            pcall(function()
                exists = getScriptManager():getItem(entry.type) ~= nil
            end)
            if not exists then
                return false, "unknown_clothing_item"
            end
        end
    end

    if deltas.visual ~= nil then
        local visual = deltas.visual
        if type(visual) ~= "table"
            or (visual.hairModel ~= nil and type(visual.hairModel) ~= "string")
            or (visual.beardModel ~= nil and type(visual.beardModel) ~= "string")
            or (visual.skinTextureIndex ~= nil and type(visual.skinTextureIndex) ~= "number")
            or (visual.bodyHairIndex ~= nil and type(visual.bodyHairIndex) ~= "number")
            or (visual.hairStubble ~= nil and type(visual.hairStubble) ~= "boolean")
            or (visual.beardStubble ~= nil and type(visual.beardStubble) ~= "boolean") then
            return false, "invalid_visual"
        end
        if visual.hairColor ~= nil then
            if type(visual.hairColor) ~= "table"
                or type(visual.hairColor.r) ~= "number"
                or type(visual.hairColor.g) ~= "number"
                or type(visual.hairColor.b) ~= "number" then
                return false, "invalid_visual"
            end
        end
    end

    if deltas.voice ~= nil then
        local voice = deltas.voice
        if type(voice) ~= "table"
            or (voice.prefix ~= nil and type(voice.prefix) ~= "string")
            or (voice.type ~= nil and type(voice.type) ~= "number") then
            return false, "invalid_voice"
        end
        if voice.pitch ~= nil then
            if type(voice.pitch) ~= "number" or voice.pitch < -100 or voice.pitch > 100 then
                return false, "invalid_voice"
            end
        end
    end

    if deltas.forename ~= nil then
        if type(deltas.forename) ~= "string" or deltas.forename == "" or #deltas.forename > MAX_FORENAME_LENGTH then
            return false, "invalid_forename"
        end
    end

    if deltas.gender ~= nil and deltas.gender ~= baseline.gender then
        if deltas.visual == nil or deltas.voice == nil or deltas.forename == nil then
            return false, "incomplete_gender_change"
        end
    end

    return true
end

return QuickRestartRandomizer
