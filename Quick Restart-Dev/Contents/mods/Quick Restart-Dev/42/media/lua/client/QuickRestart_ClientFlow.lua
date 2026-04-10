QuickRestartClientFlow = QuickRestartClientFlow or {}

function QuickRestartClientFlow.isRestartSnapshotAvailable(data)
    if type(data) ~= "table" then
        return false
    end

    local valid = QuickRestartValidate.validateLegacyCharacterData(data)
    return valid == true
end

function QuickRestartClientFlow.isDeathUiReady(player)
    if not player or not player.isDead or not player:isDead() then
        return false
    end

    local playerNum = player:getPlayerNum()
    return ISPostDeathUI and ISPostDeathUI.instance and ISPostDeathUI.instance[playerNum] ~= nil
end

local function applyVisualToDescriptor(desc, data, visualItemTypes)
    if not desc or not data or not data.visual or not isMultiplayer() then
        return
    end

    local visual = desc:getHumanVisual()
    if not visual then
        return
    end

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
                    visual:addBodyVisualFromItemType(visualItemTypes.fHairStubble)
                else
                    visual:removeBodyVisualFromItemType(visualItemTypes.fHairStubble)
                end
            else
                if data.visual.hairStubble then
                    visual:addBodyVisualFromItemType(visualItemTypes.mHairStubble)
                else
                    visual:removeBodyVisualFromItemType(visualItemTypes.mHairStubble)
                end
            end
        end)
    end
    if data.visual.beardStubble ~= nil and not isFemale then
        call(function()
            if data.visual.beardStubble then
                visual:addBodyVisualFromItemType(visualItemTypes.mBeardStubble)
            else
                visual:removeBodyVisualFromItemType(visualItemTypes.mBeardStubble)
            end
        end)
    end
end

local function resolveCharacterProfession(profession)
    local professionType = tostring(profession or "unemployed")
    local characterProfession = CharacterProfession.get(ResourceLocation.of(professionType))
    if characterProfession then
        return characterProfession
    end

    return CharacterProfession.get(ResourceLocation.of("unemployed"))
end

function QuickRestartClientFlow.startSameWorldRestartFromSnapshot(data, options)
    if not data or not data.name then
        return false
    end

    options = options or {}

    local closePanel = options.closePanel
    local clearPending = options.clearPending
    local setPendingSameWorld = options.setPendingSameWorld
    local visualItemTypes = options.visualItemTypes or {}

    if closePanel then
        closePanel()
    end

    if setPendingSameWorld then
        setPendingSameWorld(data)
    end

    BaseGameCharacterDetails.DoProfessions()
    CoopCharacterCreation:newPlayerMouse()

    local scheduler = options.scheduler or QuickRestartScheduler
    scheduler.scheduleAfterTicks("same_world_auto_complete", 2, function()
        local coop = CoopCharacterCreation.instance
        if not coop then
            if clearPending then
                clearPending()
            end
            return
        end

        local desc = MainScreen.instance.desc
        if desc then
            desc:setForename(data.forename or "John")
            desc:setSurname(data.surname or "Doe")
            desc:setFemale(data.gender == "female")
            if data.profession then
                local prof = resolveCharacterProfession(data.profession)
                if prof then
                    desc:setCharacterProfession(prof)
                end
            end
            if data.voice then
                if data.voice.prefix then desc:setVoicePrefix(data.voice.prefix) end
                if data.voice.type ~= nil then desc:setVoiceType(data.voice.type) end
                if data.voice.pitch ~= nil then desc:setVoicePitch(data.voice.pitch) end
            end
            applyVisualToDescriptor(desc, data, visualItemTypes)
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
    end)
    return true
end

function QuickRestartClientFlow.restartNewWorld(options)
    options = options or {}

    local player = getPlayer()
    if not player then
        return false
    end

    if isMultiplayer() then
        if options.sendRestartIntent then
            return options.sendRestartIntent(player, QuickRestartConstants.COMMANDS.REQUEST_RESTART_FRESH_WORLD)
        end
        return false
    end

    if options.canUseFreshWorld and not options.canUseFreshWorld() then
        return false
    end

    local playerIdentifier = options.getPlayerIdentifier and options.getPlayerIdentifier(player) or nil
    if not playerIdentifier then
        return false
    end

    local data = options.loadDataFromSaveFolder and options.loadDataFromSaveFolder(playerIdentifier) or nil
    if not data or not data.region then
        return false
    end

    if data.sandbox then
        local sandboxVarsCreation = options.fetchSandboxVarsAtCreation and options.fetchSandboxVarsAtCreation(data) or nil
        local sandboxVarsCurrent = options.fetchSandboxVarsAtDeath and options.fetchSandboxVarsAtDeath() or nil
        local differs = options.sandboxDiffers and options.sandboxDiffers(sandboxVarsCreation, sandboxVarsCurrent) or false
        if differs then
            local restartPanel = options.getRestartPanel and options.getRestartPanel() or nil
            if restartPanel and restartPanel.showSandboxChoice then
                restartPanel:showSandboxChoice(data, playerIdentifier, sandboxVarsCurrent)
            elseif options.doRestartNewWorld then
                options.doRestartNewWorld(data, playerIdentifier, sandboxVarsCreation)
            end
            return true
        end
    end

    if options.doRestartNewWorld then
        options.doRestartNewWorld(data, playerIdentifier, options.fetchSandboxVarsAtCreation and options.fetchSandboxVarsAtCreation(data) or nil)
        return true
    end

    return false
end

function QuickRestartClientFlow.restartSameWorld(options)
    options = options or {}

    local player = getPlayer()
    if not player then
        return false
    end

    if isMultiplayer() then
        if options.sendRestartIntent then
            return options.sendRestartIntent(player, QuickRestartConstants.COMMANDS.REQUEST_RESTART_SAME_WORLD)
        end
        return false
    end

    local playerIdentifier = options.getPlayerIdentifier and options.getPlayerIdentifier(player) or nil
    if not playerIdentifier then
        return false
    end

    local data = options.loadDataFromSaveFolder and options.loadDataFromSaveFolder(playerIdentifier) or nil
    if not data or not data.name then
        return false
    end

    if options.startSameWorldRestartFromSnapshot then
        return options.startSameWorldRestartFromSnapshot(data)
    end

    return false
end

function QuickRestartClientFlow.addRestartPanel(options)
    options = options or {}
    if options.getRestartPanel and options.getRestartPanel() then
        return options.getRestartPanel()
    end

    local charDataAvail = false
    local player = getPlayer()
    if player and options.getPlayerIdentifier and options.loadDataFromSaveFolder then
        local playerIdentifier = options.getPlayerIdentifier(player)
        if playerIdentifier then
            local data = options.loadDataFromSaveFolder(playerIdentifier)
            if QuickRestartClientFlow.isRestartSnapshotAvailable(data) then
                charDataAvail = true
            end
        end
    end

    local panel = QuickRestartUI.createRestartPanel({
        charDataAvail = charDataAvail,
        canUseFreshWorld = options.canUseFreshWorld,
        onRestartNewWorld = options.onRestartNewWorld,
        onRestartSameWorld = options.onRestartSameWorld,
        onSandboxSaved = options.onSandboxSaved,
        onSandboxCurrent = options.onSandboxCurrent,
    })

    if options.setRestartPanel then
        options.setRestartPanel(panel)
    end

    return panel
end

function QuickRestartClientFlow.tryShowRestartPanel(options)
    options = options or {}

    local state = options.state
    if not state or not state.awaitingRestartPanel then
        return nil
    end

    local player = getPlayer()
    if not QuickRestartClientFlow.isDeathUiReady(player) then
        return nil
    end

    if isMultiplayer() and state.waitingForActiveSnapshot then
        return nil
    end

    state.awaitingRestartPanel = false
    return QuickRestartClientFlow.addRestartPanel(options)
end

function QuickRestartClientFlow.onPlayerDeath(player, options)
    options = options or {}

    local state = options.state
    if not state then
        return
    end

    if options.resetPendingMPRestore then
        options.resetPendingMPRestore()
    end

    state.awaitingRestartPanel = true
    state.pendingRestartApproved = false
    state.pendingRestartGrantId = nil
    state.pendingRestartMode = nil
    state.pendingRestartRequestId = nil

    if isMultiplayer() then
        if options.requestActiveServerSnapshot then
            options.requestActiveServerSnapshot(player)
        end
    else
        QuickRestartClientFlow.tryShowRestartPanel(options)
    end
end

function QuickRestartClientFlow.onNewGame(player, options)
    options = options or {}

    if options.closeRestartPanel then
        options.closeRestartPanel()
    end

    local state = options.state
    if state then
        state.awaitingRestartPanel = false
        state.waitingForActiveSnapshot = false
        state.pendingRestartApproved = false
        state.pendingRestartRequestId = nil
        state.pendingRestartMode = nil
        state.pendingRestartGrantId = nil
    end

    if options.resetCharacterDataSaved then
        options.resetCharacterDataSaved()
    end

    if options.resetPendingMPRestore then
        options.resetPendingMPRestore()
    end

    local playerIdentifier = options.getPlayerIdentifier and options.getPlayerIdentifier(player) or nil
    local saveFilePath = options.getSaveFileNameForPlayer and options.getSaveFileNameForPlayer(playerIdentifier) or nil
    local data = nil

    if options.consumePendingSameWorldData then
        data = options.consumePendingSameWorldData()
        if data and state then
            state.replaceSnapshotOnNextCapture = false
        end
    end

    if not data and options.consumeSavedData then
        data = options.consumeSavedData()
    end

    if not data or not data.name then
        if not isMultiplayer() and options.loadDataFromFile then
            data = options.loadDataFromFile()
        end
    end

    if not data or not data.name then
        if isMultiplayer() and state then
            state.replaceSnapshotOnNextCapture = QuickRestartClientFlow.isRestartSnapshotAvailable(state.serverSnapshot)
        end

        if options.scheduleDelayedSave then
            options.scheduleDelayedSave(player, saveFilePath)
        end
    else
        if state then
            state.replaceSnapshotOnNextCapture = false
        end

        if options.applyLoadedCharacter then
            options.applyLoadedCharacter(player, data)
        end

        if not isMultiplayer() and options.persistAppliedData then
            options.persistAppliedData(data, saveFilePath)
        end
    end

    if not isMultiplayer() and options.scheduleSandboxCapture then
        options.scheduleSandboxCapture(saveFilePath)
    end
end

function QuickRestartClientFlow.onGameTimeLoaded(options)
    options = options or {}
    if not isClient() then
        return
    end

    local player = getPlayer()
    if player and isMultiplayer() and options.requestActiveServerSnapshot then
        options.requestActiveServerSnapshot(player)
    end

    if options.flushPendingMPSkills then
        options.flushPendingMPSkills()
    end
end

function QuickRestartClientFlow.onServerCommand(module, command, args, options)
    options = options or {}
    if module ~= QuickRestartConstants.MODULE then
        return
    end

    local state = options.state
    if not state or type(args) ~= "table" then
        return
    end

    if state.pendingRequestId and args.requestId and state.pendingRequestId ~= args.requestId then
        return
    end

    if command == QuickRestartConstants.COMMANDS.SNAPSHOT_ACK then
        state.waitingForSnapshotAck = false
        state.snapshotAcked = args.accepted == true
        if args.profileKey and args.profileKey ~= "" then
            state.pendingProfileKey = tostring(args.profileKey)
        end
        if args.accepted == true and state.pendingSnapshot then
            if args.stored == true then
                state.serverSnapshot = state.pendingSnapshot
                state.serverSnapshotLoaded = true
            end
            state.pendingSnapshot = nil
        end
        return
    end

    if command == QuickRestartConstants.COMMANDS.SNAPSHOT_RETRY then
        local player = getPlayer()
        if player and options.retryPendingSnapshot then
            options.retryPendingSnapshot(player)
        end
        return
    end

    if command == QuickRestartConstants.COMMANDS.APPLY_SKILLS_ACK then
        if options.onApplySkillsAck then
            options.onApplySkillsAck()
        end
        return
    end

    if command == QuickRestartConstants.COMMANDS.APPLY_SKILLS_RETRY then
        if args.grantId and args.grantId ~= "" then
            state.pendingRestartGrantId = tostring(args.grantId)
        end
        if options.retryApplySkills then
            options.retryApplySkills()
        end
        return
    end

    if command == QuickRestartConstants.COMMANDS.APPLY_SKILLS_DENIED then
        state.pendingRestartGrantId = nil
        if options.onApplySkillsDenied then
            options.onApplySkillsDenied(args.reason)
        end
        return
    end

    if state.pendingRestartRequestId and args.requestId and state.pendingRestartRequestId ~= args.requestId then
        return
    end

    if command == QuickRestartConstants.COMMANDS.RESTART_ACCEPTED then
        state.pendingRestartApproved = true
        state.lastRestartDeniedReason = nil
        state.pendingRestartGrantId = args.grantId
        if state.pendingRestartMode == QuickRestartConstants.COMMANDS.REQUEST_RESTART_SAME_WORLD and state.serverSnapshot and options.startSameWorldRestartFromSnapshot then
            state.pendingRestartRequestId = nil
            state.pendingRestartApproved = false
            options.startSameWorldRestartFromSnapshot(state.serverSnapshot)
            state.pendingRestartMode = nil
        end
        return
    end

    if command == QuickRestartConstants.COMMANDS.RESTART_DENIED then
        state.pendingRestartRequestId = nil
        state.pendingRestartApproved = false
        state.pendingRestartGrantId = nil
        state.lastRestartDeniedReason = args.reason
        state.pendingRestartMode = nil
        return
    end

    if command == QuickRestartConstants.COMMANDS.SNAPSHOT_DATA then
        if args.profileKey and args.profileKey ~= "" then
            state.pendingProfileKey = tostring(args.profileKey)
        end

        local snapshot = args.snapshot
        local hasValidSnapshot = false
        if args.found == true and type(snapshot) == "table" then
            hasValidSnapshot = QuickRestartClientFlow.isRestartSnapshotAvailable(snapshot)
        end

        state.serverSnapshot = hasValidSnapshot and snapshot or nil
        state.serverSnapshotLoaded = hasValidSnapshot
        state.waitingForActiveSnapshot = false

        if state.pendingRestartApproved and state.pendingRestartMode == QuickRestartConstants.COMMANDS.REQUEST_RESTART_SAME_WORLD and state.serverSnapshot and options.startSameWorldRestartFromSnapshot then
            state.pendingRestartRequestId = nil
            state.pendingRestartApproved = false
            options.startSameWorldRestartFromSnapshot(state.serverSnapshot)
            state.pendingRestartMode = nil
        elseif state.pendingRestartApproved and state.pendingRestartMode == QuickRestartConstants.COMMANDS.REQUEST_RESTART_SAME_WORLD and not state.serverSnapshot then
            state.pendingRestartRequestId = nil
            state.pendingRestartApproved = false
            state.pendingRestartGrantId = nil
            state.lastRestartDeniedReason = "invalid_server_snapshot"
            state.pendingRestartMode = nil
        end
        QuickRestartClientFlow.tryShowRestartPanel(options)
    end
end

return QuickRestartClientFlow
