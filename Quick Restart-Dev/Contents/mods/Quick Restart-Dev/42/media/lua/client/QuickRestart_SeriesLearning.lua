QuickRestartSeriesLearning = QuickRestartSeriesLearning or {}

local KEY_CLEAN_EXIT = "cleanExit"
local KEY_SESSION_RESTARTS = "sessionRestarts"
local KEY_SESSION_WORLDS = "sessionWorlds"
local KEY_SESSION_POP_MIN = "sessionPopMin"
local KEY_SESSION_POP_MAX = "sessionPopMax"
local KEY_SESSION_RATIO = "sessionRatio"
local KEY_SESSION_RANDOMIZED = "sessionRandomized"

local MIN_CRASH_RATIO = 110
local WORLD_RANDOM_CATEGORIES = {"sandbox", "sandboxMods", "zombies"}

local BUCKET_LIMITS = {0.35, 0.75, 1.40, 2.00, 3.00}
local BUCKET_COUNT = #BUCKET_LIMITS + 1
local MIN_WORLDS_TO_LEARN = 2
local MIN_SAMPLES_TO_CALIBRATE = 3
local WARN_FRACTION = 0.70
local CRITICAL_FRACTION = 0.85
local WARN_FLOOR = 1.10
local CRITICAL_FLOOR = 1.15

local loaded = false
local sessionWorlds = 0
local sessionPopMin = -1
local sessionPopMax = -1
local sessionRandomized = false

local function readPopulation()
    local ok, value = pcall(function()
        return SandboxVars and SandboxVars.ZombieConfig
            and SandboxVars.ZombieConfig.PopulationMultiplier
    end)
    if not ok or type(value) ~= "number" or value < 0 then
        return nil
    end
    return value
end

local function isWorldRandomized()
    local ok, randomized = pcall(function()
        local player = getPlayer()
        if not player then
            return false
        end

        local identifier = isMultiplayer() and "player" or tostring(player:getPlayerNum())
        local options = QuickRestartRestartOptions.get(identifier)
        if type(options) ~= "table" then
            return false
        end

        for _, category in ipairs(WORLD_RANDOM_CATEGORIES) do
            if options[category] == QuickRestartRestartOptions.RANDOM then
                return true
            end
        end
        return false
    end)

    return ok and randomized == true
end

local function bucketOf(population)
    if type(population) ~= "number" or population < 0 then
        return nil
    end

    for i = 1, #BUCKET_LIMITS do
        if population < BUCKET_LIMITS[i] then
            return i
        end
    end
    return BUCKET_COUNT
end

local function sumKey(bucket)
    return "learnB" .. tostring(bucket)
end

local function countKey(bucket)
    return "learnB" .. tostring(bucket) .. "n"
end

local function ratioKey(bucket)
    return "learnB" .. tostring(bucket) .. "r"
end

local function survivedKey(bucket)
    return "learnB" .. tostring(bucket) .. "s"
end

local function bucketForSession(popMin, popMax, randomized)
    if randomized then
        return nil
    end
    if popMin < 0 or popMin ~= popMax then
        return nil
    end
    return bucketOf(popMin / 100)
end

local function learnFromSession(worlds, popMin, popMax, randomized, deathRatio)
    if worlds < MIN_WORLDS_TO_LEARN then
        return false
    end

    local bucket = bucketForSession(popMin, popMax, randomized)
    if not bucket then
        QuickRestartLog.info("series learning crash session skipped"
            .. " worlds=" .. tostring(worlds)
            .. " randomized=" .. tostring(randomized)
            .. " popMin=" .. tostring(popMin)
            .. " popMax=" .. tostring(popMax))
        return false
    end

    local sum = QuickRestartState.getNumber(sumKey(bucket), 0) + worlds
    local count = QuickRestartState.getNumber(countKey(bucket), 0) + 1
    local ratioSum = QuickRestartState.getNumber(ratioKey(bucket), 0) + deathRatio
    QuickRestartState.set(sumKey(bucket), sum)
    QuickRestartState.set(countKey(bucket), count)
    QuickRestartState.set(ratioKey(bucket), ratioSum)

    QuickRestartLog.info("series learning recorded crash"
        .. " bucket=" .. tostring(bucket)
        .. " worlds=" .. tostring(worlds)
        .. " pop=" .. string.format("%.2f", popMin / 100)
        .. " deathRatio=" .. string.format("%.2f", deathRatio / 100)
        .. " averageWorlds=" .. string.format("%.2f", sum / count)
        .. " averageDeathRatio=" .. string.format("%.2f", ratioSum / count / 100)
        .. " samples=" .. tostring(count))
    return true
end

local function learnSurvived(worlds, popMin, popMax, randomized, exitRatio)
    if worlds < MIN_WORLDS_TO_LEARN then
        return false
    end

    local bucket = bucketForSession(popMin, popMax, randomized)
    if not bucket then
        QuickRestartLog.info("series learning survived session skipped"
            .. " worlds=" .. tostring(worlds)
            .. " randomized=" .. tostring(randomized))
        return false
    end

    local best = QuickRestartState.getNumber(survivedKey(bucket), 0)
    if worlds <= best then
        return false
    end

    QuickRestartState.set(survivedKey(bucket), worlds)
    QuickRestartLog.info("series learning recorded survived"
        .. " bucket=" .. tostring(bucket)
        .. " worlds=" .. tostring(worlds)
        .. " exitRatio=" .. string.format("%.2f", exitRatio / 100)
        .. " previousBest=" .. tostring(best))
    return true
end

local function ensureLoaded()
    if loaded then
        return
    end
    loaded = true

    local current = QuickRestartHeapGuard.getEngineRestartCount()
    local storedRestarts = QuickRestartState.getNumber(KEY_SESSION_RESTARTS, nil)

    if storedRestarts ~= nil and current ~= nil and current > storedRestarts then
        sessionWorlds = QuickRestartState.getNumber(KEY_SESSION_WORLDS, 0)
        sessionPopMin = QuickRestartState.getNumber(KEY_SESSION_POP_MIN, -1)
        sessionPopMax = QuickRestartState.getNumber(KEY_SESSION_POP_MAX, -1)
        sessionRandomized = QuickRestartState.getBoolean(KEY_SESSION_RANDOMIZED, false)
        return
    end

    local previousWorlds = QuickRestartState.getNumber(KEY_SESSION_WORLDS, 0)
    local cleanExit = QuickRestartState.getBoolean(KEY_CLEAN_EXIT, true)
    local previousRatio = QuickRestartState.getNumber(KEY_SESSION_RATIO, 0)

    if previousWorlds > 0 then
        QuickRestartHeapMargin.applyPreviousOutcome(not cleanExit)
    end

    local popMin = QuickRestartState.getNumber(KEY_SESSION_POP_MIN, -1)
    local popMax = QuickRestartState.getNumber(KEY_SESSION_POP_MAX, -1)
    local randomized = QuickRestartState.getBoolean(KEY_SESSION_RANDOMIZED, false)

    if previousWorlds > 0 and previousRatio >= MIN_CRASH_RATIO then
        if not cleanExit then
            learnFromSession(previousWorlds, popMin, popMax, randomized, previousRatio)
        else
            learnSurvived(previousWorlds, popMin, popMax, randomized, previousRatio)
        end
    else
        QuickRestartLog.info("series learning previous session not counted"
            .. " worlds=" .. tostring(previousWorlds)
            .. " cleanExit=" .. tostring(cleanExit)
            .. " lastRatio=" .. tostring(previousRatio))
    end

    sessionWorlds = 0
    sessionPopMin = -1
    sessionPopMax = -1
    sessionRandomized = false
    QuickRestartState.set(KEY_CLEAN_EXIT, false)
    QuickRestartState.set(KEY_SESSION_RANDOMIZED, false)
end

function QuickRestartSeriesLearning.recordWorld()
    ensureLoaded()

    sessionWorlds = sessionWorlds + 1

    local population = readPopulation()
    local hundredths = -1
    if type(population) == "number" and population >= 0 then
        hundredths = math.floor(population * 100)
        if sessionPopMin < 0 or hundredths < sessionPopMin then
            sessionPopMin = hundredths
        end
        if hundredths > sessionPopMax then
            sessionPopMax = hundredths
        end
    end

    local ratio = 0
    local okState, state = pcall(QuickRestartHeapGuard.getState)
    if okState and type(state) == "table" and type(state.ratio) == "number" then
        ratio = math.floor(state.ratio * 100)
    end

    if not sessionRandomized and isWorldRandomized() then
        sessionRandomized = true
        QuickRestartState.set(KEY_SESSION_RANDOMIZED, true)
        QuickRestartLog.info("series learning session marked randomized")
    end

    QuickRestartState.set(KEY_CLEAN_EXIT, false)
    QuickRestartState.set(KEY_SESSION_RESTARTS,
        QuickRestartHeapGuard.getEngineRestartCount() or -1)
    QuickRestartState.set(KEY_SESSION_WORLDS, sessionWorlds)
    QuickRestartState.set(KEY_SESSION_POP_MIN, sessionPopMin)
    QuickRestartState.set(KEY_SESSION_POP_MAX, sessionPopMax)
    QuickRestartState.set(KEY_SESSION_RATIO, ratio)

    QuickRestartLog.info("series learning world"
        .. " n=" .. tostring(sessionWorlds)
        .. " pop=" .. tostring(hundredths)
        .. " expected=" .. tostring(QuickRestartSeriesLearning.getExpectedWorlds(population) or -1))
end

function QuickRestartSeriesLearning.markCleanExit()
    ensureLoaded()
    QuickRestartState.set(KEY_CLEAN_EXIT, true)
    QuickRestartLog.info("series learning clean exit marked worlds=" .. tostring(sessionWorlds))
end

function QuickRestartSeriesLearning.getExpectedWorlds(population)
    local bucket = bucketOf(population)
    if not bucket then
        return nil, nil
    end

    local count = QuickRestartState.getNumber(countKey(bucket), 0)
    if count > 0 then
        return QuickRestartState.getNumber(sumKey(bucket), 0) / count, "crash"
    end

    local survived = QuickRestartState.getNumber(survivedKey(bucket), 0)
    if survived > 0 then
        return survived, "atLeast"
    end

    return nil, nil
end

function QuickRestartSeriesLearning.getRestartsLeft()
    ensureLoaded()

    local expected, source = QuickRestartSeriesLearning.getExpectedWorlds(readPopulation())
    if not expected then
        return nil, nil
    end

    return math.max(0, math.floor(expected - sessionWorlds + 0.5)), source
end

function QuickRestartSeriesLearning.getSessionWorlds()
    ensureLoaded()
    return sessionWorlds
end

local function installDesktopHook()
    if desktopHookInstalled then
        return
    end
    if type(MainScreen) ~= "table" or type(MainScreen.quitToDesktop) ~= "function" then
        return
    end
    if MainScreen.quickRestartQuitHooked then
        desktopHookInstalled = true
        return
    end

    desktopHookInstalled = true
    MainScreen.quickRestartQuitHooked = true

    local original = MainScreen.quitToDesktop
    MainScreen.quitToDesktop = function(self, ...)
        pcall(QuickRestartSeriesLearning.markCleanExit)
        return original(self, ...)
    end

    QuickRestartLog.info("series learning quitToDesktop hook installed")
end

local function onMainMenuEnter()
    installDesktopHook()
    QuickRestartSeriesLearning.markCleanExit()
end

Events.OnMainMenuEnter.Add(onMainMenuEnter)

return QuickRestartSeriesLearning
