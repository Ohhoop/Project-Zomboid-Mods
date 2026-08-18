QuickRestartPhase = QuickRestartPhase or {}

local KEY_PHASE = "phase"

QuickRestartPhase.MENU = "menu"
QuickRestartPhase.LOADING = "loading"
QuickRestartPhase.INGAME = "ingame"

local reported = false

function QuickRestartPhase.getPrevious()
    return QuickRestartState.get(KEY_PHASE)
end

function QuickRestartPhase.reportPrevious()
    if reported then
        return nil
    end
    reported = true

    local previous = QuickRestartPhase.getPrevious()
    if previous then
        QuickRestartLog.info("phase previous session ended in " .. tostring(previous))
    end
    return previous
end

function QuickRestartPhase.set(phase)
    QuickRestartState.set(KEY_PHASE, phase)
    QuickRestartLog.info("phase " .. tostring(phase))
    return phase
end

Events.OnMainMenuEnter.Add(function()
    QuickRestartPhase.reportPrevious()
    QuickRestartPhase.set(QuickRestartPhase.MENU)
end)

Events.OnPreMapLoad.Add(function()
    QuickRestartPhase.set(QuickRestartPhase.LOADING)
end)

Events.OnGameStart.Add(function()
    QuickRestartPhase.set(QuickRestartPhase.INGAME)
end)

return QuickRestartPhase
