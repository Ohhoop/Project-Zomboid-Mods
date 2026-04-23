QuickRestartScheduler = QuickRestartScheduler or {}

QuickRestartScheduler.tasks = QuickRestartScheduler.tasks or {}
QuickRestartScheduler.isRegistered = QuickRestartScheduler.isRegistered == true

local function hasTasks()
    for _ in pairs(QuickRestartScheduler.tasks) do
        return true
    end

    return false
end

local function tick()
    for key, task in pairs(QuickRestartScheduler.tasks) do
        task.remaining = task.remaining - 1
        if task.remaining <= 0 then
            QuickRestartScheduler.tasks[key] = nil
            pcall(task.fn)
        end
    end

    if not hasTasks() then
        Events.OnTick.Remove(tick)
        QuickRestartScheduler.isRegistered = false
    end
end

local function ensureRegistered()
    if QuickRestartScheduler.isRegistered then
        return
    end

    Events.OnTick.Add(tick)
    QuickRestartScheduler.isRegistered = true
end

function QuickRestartScheduler.scheduleAfterTicks(key, ticks, fn)
    if type(key) ~= "string" or key == "" then
        return false
    end

    if type(fn) ~= "function" then
        return false
    end

    local delay = tonumber(ticks) or 0
    if delay < 0 then
        delay = 0
    end

    QuickRestartScheduler.tasks[key] = {
        remaining = delay,
        fn = fn,
    }

    ensureRegistered()
    return true
end

function QuickRestartScheduler.cancel(key)
    if type(key) ~= "string" or key == "" then
        return false
    end

    if not QuickRestartScheduler.tasks[key] then
        return false
    end

    QuickRestartScheduler.tasks[key] = nil

    if QuickRestartScheduler.isRegistered and not hasTasks() then
        Events.OnTick.Remove(tick)
        QuickRestartScheduler.isRegistered = false
    end

    return true
end

function QuickRestartScheduler.exists(key)
    if type(key) ~= "string" or key == "" then
        return false
    end

    return QuickRestartScheduler.tasks[key] ~= nil
end

return QuickRestartScheduler
