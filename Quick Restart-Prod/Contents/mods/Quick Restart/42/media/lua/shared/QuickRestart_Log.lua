QuickRestartLog = QuickRestartLog or {}

QRDebugLogging = false
QuickRestartLog.DEBUG = false

local PREFIX = "[QuickRestart] "

function QuickRestartLog.isEnabled()
    return QRDebugLogging == true
end

function QuickRestartLog.setEnabled(enabled)
    QRDebugLogging = enabled == true
    return QRDebugLogging
end

local function write(level, message)
    if not QuickRestartLog.isEnabled() then
        return
    end

    print(PREFIX .. level .. " " .. tostring(message))
end

function QuickRestartLog.debug(message)
    if QuickRestartLog.DEBUG and QuickRestartLog.isEnabled() then
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
