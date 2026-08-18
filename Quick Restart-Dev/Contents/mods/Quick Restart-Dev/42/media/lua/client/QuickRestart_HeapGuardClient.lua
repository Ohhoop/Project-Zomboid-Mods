require("QuickRestart_ClientBootstrap")

local function readHeapKb()
    local ok, used, free, total = pcall(collectgarbage, "count")
    if not ok or type(used) ~= "number" then
        return nil
    end
    return used, free, total
end

local function onPreMapLoad()
    local used, _, total = readHeapKb()
    if not used then
        QuickRestartLog.warn("heapguard cannot read the heap")
        return
    end

    QuickRestartHeapGuard.recordFloor(used, total, QuickRestartHeapMargin.get())
    QuickRestartSeriesLearning.recordWorld()
end

Events.OnPreMapLoad.Add(onPreMapLoad)

return true
