QuickRestartLog = QuickRestartLog or {}

QuickRestartLog.DEBUG = QuickRestartLog.DEBUG == true

local PREFIX = "[QuickRestart] "

local function write(level, message)
    print(PREFIX .. level .. " " .. tostring(message))
end

function QuickRestartLog.debug(message)
    if QuickRestartLog.DEBUG then
        write("DEBUG", message)
    end
end

function QuickRestartLog.info(message)
    write("INFO", message)
end

function QuickRestartLog.warn(message)
    write("WARN", message)
end

function QuickRestartLog.error(message)
    write("ERROR", message)
end

return QuickRestartLog
