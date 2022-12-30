local levels = {
    trace = {
        colour = colours.lightGrey,
        label = "TRC",
        level = -1,
    },
    debug = {
        colour = colours.orange,
        label = "DBG",
        level = 0,
    },
    info = {
        colour = colours.green,
        label = "INF",
        level = 1,
    },
    warn = {
        colour = colours.red,
        label = "WRN",
        level = 2,

    },
    panic = {
        colour = colours.red,
        label = "PNC",
        level = 99,
    },
}

local defaultTimeStamp = "!%b %e %H:%M:%S"

local function tableContains(table, key)
    for i, _ in pairs(table) do
        if i == key then
            return true
        end
    end

    return false
end

local function willWrap(text)
    return (({term.getCursorPos()})[1] + #text) > ({term.getSize()})[1]
end

local function formatEpoch(epoch)
    local diff = os.epoch("utc") - epoch

    if diff < 1000 then
        return tostring(diff) .. "ms"
    elseif diff < 10000 then
        return tostring(math.floor(diff/10)/100) .. "s"
    elseif diff < 60000 then
        return tostring(math.floor(diff/1000) .. "s")
    else
        local mins = math.floor(diff/60000)
        return tostring(mins) .. "m" .. (math.floor(diff/1000) - mins*60) .. "s"
    end
end

local function NewLogger(timeFormat, fileName)
    local logger = {
        timeFormat = timeFormat or defaultTimeStamp,
        minimumLevel = -1,
        fileName = "", -- filename to log to. If not passed, will not log to file.
        silent = false, -- when enabled, will only log to file (if a filename is set)
    }

    if fileName ~= "" and fileName ~= nil then
        logger.file = fs.open(fileName, "wb")
    end

    logger.setLevel = function(logLevel)
        if not tableContains(levels, logLevel) then
            error("invalid log level passed: " .. tostring(logLevel))
        end

        logger.minimumLevel = levels[logLevel].level
    end

    logger.newMessage = function(logLevel)
        if not tableContains(levels, logLevel) then
            error("invalid log level passed: " .. tostring(logLevel))
        end

        local loggerMessage = {
            logger = logger,
            level = levels[logLevel],
            variables = {},
            message = "",
            error = "",
        }

        loggerMessage.Send = function()
            if loggerMessage.level.level < logger.minimumLevel then return end

            local previousColour = term.getTextColour()

            -- Display time
            local outputText = ""
            local text = ""

            if not logger.silent then term.setTextColour(colours.grey) end
            text = os.date(loggerMessage.logger.timeFormat) .. " "
            outputText = outputText .. text
            if not logger.silent then term.write(text) end

            -- Display log level
            if not logger.silent then term.setTextColour(loggerMessage.level.colour) end
            text = loggerMessage.level.label .. " "
            outputText = outputText .. text
            if not logger.silent then term.write(text) end

            -- Display error, if present
            if loggerMessage.error ~= "" then
                if not logger.silent then term.setTextColour(colours.red) end

                text = "err=" .. loggerMessage.error .. " "
                outputText = outputText .. text
                if not logger.silent then print(text) end
            end

            -- Display variables
            for _, variable in pairs(loggerMessage.variables) do
                if not logger.silent then
                    if willWrap(variable.name .. "=" .. variable.value) then
                        print("")
                    end
                end

                if not logger.silent then term.setTextColour(colours.blue) end
                text = variable.name .. "="
                outputText = outputText .. text
                if not logger.silent then term.write(text) end

                if not logger.silent then term.setTextColour(previousColour) end
                text = variable.value .. " "
                outputText = outputText .. text
                if not logger.silent then term.write(text) end
            end

            if not logger.silent then term.setTextColour(previousColour) end

            text = loggerMessage.message
            outputText = outputText .. text
            if not logger.silent then print(text) end

            if logger.file ~= nil then
                logger.file.write(outputText .. "\n")
                logger.file.flush()
            end
        end

        loggerMessage.Msg = function (message)
            loggerMessage.message = tostring(message)
            loggerMessage.Send()
        end

        loggerMessage.Err = function (error)
            loggerMessage.error = tostring(error)

            return loggerMessage
        end

        loggerMessage.Str = function(name, value)
            table.insert(loggerMessage.variables, { name = tostring(name), value = tostring(value)})

            return loggerMessage
        end

        loggerMessage.Dur = function(name, epoch)
            loggerMessage.Str(name, formatEpoch(epoch))

            return loggerMessage
        end

        return loggerMessage
    end

    logger.Trace = function() return logger.newMessage("trace") end
    logger.Debug = function() return logger.newMessage("debug") end
    logger.Info = function() return logger.newMessage("info") end
    logger.Warn = function() return logger.newMessage("warn") end
    logger.Panic = function() return logger.newMessage("panic") end

    return logger
end

return {
    Logger = NewLogger(),
    NewLogger = NewLogger
}