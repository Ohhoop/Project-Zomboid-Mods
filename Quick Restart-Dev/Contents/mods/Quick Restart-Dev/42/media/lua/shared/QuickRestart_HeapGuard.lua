QuickRestartHeapGuard = QuickRestartHeapGuard or {}

local STATE_VERSION = 2
local MAX_FLOORS = 40
local WARN_RESTARTS = 10
local CRITICAL_RESTARTS = 5
local MIN_COST_KB = 4 * 1024
local MIN_SLOPE_POINTS = 5
local SLOPE_WINDOW = 8
local PRIOR_WEIGHT = 6
local MIN_PRIOR_POINTS = 8
local WARMUP_FLOORS = 2
local THRESHOLD_RESTARTS = 2
local SWING_WINDOW = 12
local SWING_RESERVE_KB = 128 * 1024

QuickRestartHeapGuard.LEVEL_OK = "ok"
QuickRestartHeapGuard.LEVEL_WARN = "warn"
QuickRestartHeapGuard.LEVEL_CRITICAL = "critical"

local STATE_FILE = "QuickRestart" .. getFileSeparator() .. "HeapGuard.txt"

local floors = {}
local ceilingKb = 0
local loaded = false
local level = QuickRestartHeapGuard.LEVEL_OK
local announcedLevel = QuickRestartHeapGuard.LEVEL_OK
local lastFloorKb = 0
local lastCostKb = 0
local lastRestartsLeft = -1
local lastMarginKb = 0
local listeners = {}

local function readNumber(getter)
    local ok, value = pcall(getter)
    if not ok or type(value) ~= "number" then
        return nil
    end
    return value
end

function QuickRestartHeapGuard.getEngineRestartCount()
    local size = readNumber(function() return IsoGridSquare.ignoreBlockingSprites:size() end)
    if not size then
        return nil
    end
    return math.floor(size / 2)
end

local function writeState()
    local writer = getFileWriter(STATE_FILE, true, false)
    if not writer then
        return false
    end

    writer:write("version=" .. tostring(STATE_VERSION) .. "\n")
    writer:write("restarts=" .. tostring(QuickRestartHeapGuard.getEngineRestartCount() or -1) .. "\n")
    writer:write("ceiling=" .. tostring(math.floor(ceilingKb)) .. "\n")
    for _, value in ipairs(floors) do
        writer:write("floor=" .. tostring(math.floor(value)) .. "\n")
    end
    writer:close()
    return true
end

local function readState()
    local reader = getFileReader(STATE_FILE, false)
    if not reader then
        return nil, 0, 0, {}
    end

    local storedVersion, storedRestarts, storedCeiling = 0, nil, 0
    local storedFloors = {}
    local line = reader:readLine()
    while line do
        local key, value = string.match(line, "^(%w+)=(-?%d+)$")
        value = tonumber(value)
        if key == "version" then
            storedVersion = value or 0
        elseif key == "restarts" then
            storedRestarts = value
        elseif key == "ceiling" then
            storedCeiling = value or 0
        elseif key == "floor" and value and value > 0 then
            storedFloors[#storedFloors + 1] = value
        end
        line = reader:readLine()
    end
    reader:close()
    return storedRestarts, storedCeiling, storedVersion, storedFloors
end

local function ensureLoaded()
    if loaded then
        return
    end
    loaded = true

    local current = QuickRestartHeapGuard.getEngineRestartCount()
    local storedRestarts, storedCeiling, storedVersion, storedFloors = readState()

    ceilingKb = storedCeiling or 0
    floors = {}
    level = QuickRestartHeapGuard.LEVEL_OK
    announcedLevel = level

    if storedVersion ~= STATE_VERSION then
        QuickRestartLog.info("heapguard state migrated"
            .. " storedVersion=" .. tostring(storedVersion)
            .. " version=" .. tostring(STATE_VERSION)
            .. " droppedFloors=" .. tostring(#storedFloors))
        return
    end

    if storedRestarts == nil or current == nil or current < storedRestarts then
        QuickRestartLog.info("heapguard new process"
            .. " stored=" .. tostring(storedRestarts)
            .. " current=" .. tostring(current)
            .. " carriedCeilingKb=" .. tostring(math.floor(ceilingKb)))
        return
    end

    floors = storedFloors
    QuickRestartLog.info("heapguard history restored"
        .. " floors=" .. tostring(#floors)
        .. " ceilingKb=" .. tostring(math.floor(ceilingKb)))
end

local function median(values)
    local count = #values
    if count == 0 then
        return 0
    end

    table.sort(values)
    if count % 2 == 1 then
        return values[(count + 1) / 2]
    end
    return (values[count / 2] + values[count / 2 + 1]) / 2
end

local function slopePoints()
    local points = {}
    local first = math.max(WARMUP_FLOORS + 1, #floors - SLOPE_WINDOW + 1)
    for i = first, #floors do
        points[#points + 1] = { x = i, y = floors[i] }
    end
    return points
end

local function measuredSlope(points)
    if #points < MIN_SLOPE_POINTS then
        return nil
    end

    local slopes = {}
    for i = 1, #points - 1 do
        for j = i + 1, #points do
            slopes[#slopes + 1] = (points[j].y - points[i].y) / (points[j].x - points[i].x)
        end
    end
    return math.max(0, median(slopes))
end

local function blendedSlope(points)
    local measured = measuredSlope(points)
    local prior = QuickRestartHeapGuard.getPriorCostKb()

    if measured == nil then
        if prior > 0 and #points > 0 then
            return prior
        end
        return nil
    end

    if prior <= 0 then
        return measured
    end

    local weight = #points
    return (PRIOR_WEIGHT * prior + weight * measured) / (PRIOR_WEIGHT + weight)
end

local function interceptFor(points, slope)
    local intercepts = {}
    for _, point in ipairs(points) do
        intercepts[#intercepts + 1] = point.y - slope * point.x
    end
    return median(intercepts)
end

function QuickRestartHeapGuard.getPriorCostKb()
    if QuickRestartHeapMargin and QuickRestartHeapMargin.getPriorCostKb then
        local ok, value = pcall(QuickRestartHeapMargin.getPriorCostKb)
        if ok and type(value) == "number" and value > 0 then
            return value
        end
    end
    return 0
end

function QuickRestartHeapGuard.getSwingKb()
    ensureLoaded()

    local best = 0
    local first = math.max(WARMUP_FLOORS + 2, #floors - SWING_WINDOW + 1)
    for i = first, #floors do
        local delta = floors[i] - floors[i - 1]
        if delta > best then
            best = delta
        end
    end
    return best
end

function QuickRestartHeapGuard.getCostKb()
    ensureLoaded()

    local slope = blendedSlope(slopePoints())
    if slope == nil or slope <= 0 then
        return 0
    end
    return math.max(MIN_COST_KB, slope)
end

function QuickRestartHeapGuard.getProjectedFloorKb()
    ensureLoaded()

    local points = slopePoints()
    local slope = blendedSlope(points)
    if slope == nil or slope <= 0 then
        return lastFloorKb
    end

    return slope * points[#points].x + interceptFor(points, slope)
end

function QuickRestartHeapGuard.getRestartsLeft(marginKb)
    ensureLoaded()

    local cost = QuickRestartHeapGuard.getCostKb()
    if cost <= 0 or ceilingKb <= 0 then
        return -1
    end

    return (ceilingKb - (marginKb or 0) - QuickRestartHeapGuard.getProjectedFloorKb()) / cost
end

local function levelForRestarts(restartsLeft)
    if restartsLeft < CRITICAL_RESTARTS then
        return QuickRestartHeapGuard.LEVEL_CRITICAL
    end
    if restartsLeft < WARN_RESTARTS then
        return QuickRestartHeapGuard.LEVEL_WARN
    end
    return QuickRestartHeapGuard.LEVEL_OK
end

local function levelForHeadroom(headroomKb, marginKb)
    if type(marginKb) ~= "number" or marginKb <= 0 then
        return QuickRestartHeapGuard.LEVEL_OK
    end

    local swing = QuickRestartHeapGuard.getSwingKb()
    local floor = marginKb
    if swing > 0 and (swing + SWING_RESERVE_KB) > floor then
        floor = swing + SWING_RESERVE_KB
    end

    if headroomKb < floor then
        return QuickRestartHeapGuard.LEVEL_CRITICAL
    end
    return QuickRestartHeapGuard.LEVEL_OK
end

function QuickRestartHeapGuard.recordFloor(usedKb, totalKb, marginKb)
    ensureLoaded()

    if type(usedKb) ~= "number" or usedKb <= 0 then
        return false
    end

    if type(totalKb) == "number" and totalKb > ceilingKb then
        ceilingKb = totalKb
    end

    floors[#floors + 1] = usedKb
    while #floors > MAX_FLOORS do
        table.remove(floors, 1)
    end

    lastFloorKb = usedKb
    lastMarginKb = marginKb or 0
    lastCostKb = QuickRestartHeapGuard.getCostKb()
    lastRestartsLeft = QuickRestartHeapGuard.getRestartsLeft(lastMarginKb)

    if lastCostKb > 0 then
        level = levelForRestarts(lastRestartsLeft)
    else
        level = levelForHeadroom(ceilingKb - usedKb, lastMarginKb)
    end

    writeState()

    local points = slopePoints()
    if #points >= MIN_PRIOR_POINTS then
        local measured = measuredSlope(points)
        if measured ~= nil and QuickRestartHeapMargin and QuickRestartHeapMargin.setPriorCostKb then
            pcall(QuickRestartHeapMargin.setPriorCostKb, measured)
        end
    end

    QuickRestartLog.info("heapguard floor"
        .. " n=" .. tostring(#floors)
        .. " floorKb=" .. tostring(math.floor(usedKb))
        .. " projectedKb=" .. tostring(math.floor(QuickRestartHeapGuard.getProjectedFloorKb()))
        .. " ceilingKb=" .. tostring(math.floor(ceilingKb))
        .. " marginKb=" .. tostring(math.floor(lastMarginKb))
        .. " costKb=" .. tostring(math.floor(lastCostKb))
        .. " priorKb=" .. tostring(math.floor(QuickRestartHeapGuard.getPriorCostKb()))
        .. " swingKb=" .. tostring(math.floor(QuickRestartHeapGuard.getSwingKb()))
        .. " restartsLeft=" .. string.format("%.2f", lastRestartsLeft)
        .. " level=" .. level
        .. " engineRestarts=" .. tostring(QuickRestartHeapGuard.getEngineRestartCount()))

    if level ~= announcedLevel then
        announcedLevel = level
        for _, fn in ipairs(listeners) do
            pcall(fn, level, QuickRestartHeapGuard.getState())
        end
    end

    return true
end

function QuickRestartHeapGuard.getRestartsCap()
    ensureLoaded()

    return THRESHOLD_RESTARTS
end

function QuickRestartHeapGuard.getState()
    ensureLoaded()
    return {
        level = level,
        floors = #floors,
        floorKb = lastFloorKb,
        ceilingKb = ceilingKb,
        marginKb = lastMarginKb,
        costKb = lastCostKb,
        restartsLeft = lastRestartsLeft,
        engineRestarts = QuickRestartHeapGuard.getEngineRestartCount() or -1,
    }
end

function QuickRestartHeapGuard.getLevel()
    ensureLoaded()
    return level
end

function QuickRestartHeapGuard.getDisplayLevel()
    return QuickRestartHeapGuard.getLevel()
end

function QuickRestartHeapGuard.shouldWarnPlayer()
    ensureLoaded()
    return level == QuickRestartHeapGuard.LEVEL_WARN
        or level == QuickRestartHeapGuard.LEVEL_CRITICAL
end

function QuickRestartHeapGuard.addLevelListener(fn)
    if type(fn) ~= "function" then
        return false
    end

    listeners[#listeners + 1] = fn
    return true
end

return QuickRestartHeapGuard
