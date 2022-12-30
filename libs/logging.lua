local levels = {
    trace = {
        colour = colours.lightGrey,
        label = "TRC"
    },
    debug = {
        colour = colours.orange,
        label = "DBG"
    },
    info = {
        colour = colours.green,
        label = "INF"
    },
    warn = {
        colour = colours.red,
        label = "WRN"
    },
    panic = {
        colour = colours.red,
        label = "PNC"
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
        fileName = ""
    }

    if fileName ~= "" and fileName ~= nil then
        logger.file = fs.open(fileName, "wb")
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
            local previousColour = term.getTextColour()

            -- Display time
            local outputText = ""
            local text = ""

            term.setTextColour(colours.grey)
            text = os.date(loggerMessage.logger.timeFormat) .. " "
            outputText = outputText .. text
            term.write(text)

            -- Display log level
            term.setTextColour(loggerMessage.level.colour)
            text = loggerMessage.level.label .. " "
            outputText = outputText .. text
            term.write(text)

            -- Display error, if present
            if loggerMessage.error ~= "" then
                term.setTextColour(colours.red)

                text = "err=" .. loggerMessage.error
                outputText = outputText .. text
                print(text)
            end

            -- Display variables
            for _, variable in pairs(loggerMessage.variables) do
                if willWrap(variable.name .. "=" .. variable.value) then
                    print("")
                end

                term.setTextColour(colours.blue)
                text = variable.name .. "="
                outputText = outputText .. text
                term.write(text)

                term.setTextColour(previousColour)
                text = variable.value .. " "
                outputText = outputText .. text
                term.write(text)
            end

            term.setTextColour(previousColour)

            text = loggerMessage.message
            outputText = outputText .. text
            print(text)

            if loggerMessage.file ~= nil then
                loggerMessage.file.write()
                loggerMessage.file.flush(outputText)
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