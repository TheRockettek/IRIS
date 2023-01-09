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

local function tableContainsKey(table, key)
    for i, _ in pairs(table) do if i == key then return true end end

    return false
end

local function willWrap(text)
    return (({ term.getCursorPos() })[1] + #text) > ({ term.getSize() })[1]
end

local function formatEpoch(epoch)
    local diff = os.epoch("utc") - epoch

    if diff < 1000 then
        return tostring(diff) .. "ms"
    elseif diff < 10000 then
        return tostring(math.floor(diff / 10) / 100) .. "s"
    elseif diff < 60000 then
        return tostring(math.floor(diff / 1000) .. "s")
    else
        local mins = math.floor(diff / 60000)
        return tostring(mins) .. "m" .. (math.floor(diff / 1000) - mins * 60) .. "s"
    end
end

local function NewLogger(timeFormat, fileName)
    local this = {
        _type = "logger:logger",

        startEpoch = os.epoch("utc"),
        timeFormat = timeFormat or defaultTimeStamp,
        minimumLevel = -1,
        fileName = fileName, -- filename to log to. If not passed, will not log to file.
        silent = false, -- when enabled, will only log to file (if a filename is set)
    }

    if this.fileName ~= "" and this.fileName ~= nil then
        this.file = fs.open(this.fileName, "wb")
    end

    this.setLevel = function(logLevel)
        if not tableContainsKey(levels, logLevel) then
            error("invalid log level passed: " .. tostring(logLevel))
        end

        this.minimumLevel = levels[logLevel].level
    end

    this.newMessage = function(logLevel)
        if not tableContainsKey(levels, logLevel) then
            error("invalid log level passed: " .. tostring(logLevel))
        end

        local loggerMessage = {
            _type = "logger:logger_message",

            logger = this,
            level = levels[logLevel],
            variables = {},
            message = "",
            error = "",
        }

        loggerMessage.Send = function()
            if loggerMessage.level.level < this.minimumLevel then return end

            local previousColour = term.getTextColour()

            -- Display time
            local outputText = ""
            local text = ""

            if not this.silent then term.setTextColour(colours.grey) end
            if loggerMessage.logger.timeFormat == "-" then
                text = tostring(os.epoch("utc") - this.startEpoch) .. " "
            else
                text = os.date(loggerMessage.logger.timeFormat) .. " "
            end
            outputText = outputText .. text
            if not this.silent then term.write(text) end

            -- Display log level
            if not this.silent then term.setTextColour(loggerMessage.level.colour) end
            text = loggerMessage.level.label .. " "
            outputText = outputText .. text
            if not this.silent then term.write(text) end

            -- Display error, if present
            if loggerMessage.error ~= "" then
                if not this.silent then term.setTextColour(colours.red) end

                text = "err=" .. loggerMessage.error .. " "
                outputText = outputText .. text
                if not this.silent then print(text) end
            end

            -- Display variables
            for _, variable in pairs(loggerMessage.variables) do
                if not this.silent then
                    if willWrap(variable.name .. "=" .. variable.value) then
                        print("")
                    end
                end

                if not this.silent then term.setTextColour(colours.blue) end
                text = variable.name .. "="
                outputText = outputText .. text
                if not this.silent then term.write(text) end

                if not this.silent then term.setTextColour(previousColour) end
                text = variable.value .. " "
                outputText = outputText .. text
                if not this.silent then term.write(text) end
            end

            if not this.silent then term.setTextColour(previousColour) end

            text = loggerMessage.message
            outputText = outputText .. text
            if not this.silent then print(text) end

            if this.file ~= nil then
                this.file.write(outputText .. "\n")
                this.file.flush()
            end

            return os.epoch("utc")
        end

        loggerMessage.Msg = function(message)
            loggerMessage.message = tostring(message)
            return loggerMessage.Send()
        end

        loggerMessage.Err = function(error)
            loggerMessage.error = tostring(error)

            return loggerMessage
        end

        loggerMessage.Str = function(name, value)
            table.insert(loggerMessage.variables, { name = tostring(name), value = tostring(value) })

            return loggerMessage
        end

        loggerMessage.Dur = function(epoch)
            return loggerMessage.Str("duration", formatEpoch(epoch))
        end

        loggerMessage.Json = function(name, object)
            if object == nil then
                return loggerMessage.Str(name, "nil")
            end
            return loggerMessage.Str(name, textutils.serializeJSON(object))
        end

        loggerMessage.Object = function(name, object)
            if object == nil then
                return loggerMessage.Str(name, "nil")
            end
            return loggerMessage.Str(name, Serialize(object))
        end

        return loggerMessage
    end

    this.Trace = function() return this.newMessage("trace") end
    this.Debug = function() return this.newMessage("debug") end
    this.Info = function() return this.newMessage("info") end
    this.Warn = function() return this.newMessage("warn") end
    this.Panic = function() return this.newMessage("panic") end

    this.FunctionStart = function(name, ...)
        local args = { ... }
        local functionStart = { start = os.epoch("utc"), stepStart = os.epoch("utc"), step = 0 }

        -- Completes a function step. Logs the time since function start or last step.
        functionStart.FunctionStep = function(stepName, ...)
            local results = { ... }
            functionStart.step = functionStart.step + 1
            local now = os.epoch("utc")
            local msg = this.newMessage("trace").Str("_name", name).Str("_step", functionStart.Step).Str("_stepName",
                stepName)
            if results then
                for i = 1, #results, 2 do
                    if type(results[i + 1]) == "table" then
                        results[i + 1] = Serialize(results[i + 1])
                    end
                    msg = msg.Str(results[i], results[i + 1])
                end
            end
            msg.Dur(functionStart.stepStart).Msg("Function step")
            functionStart.stepStart = now
        end

        -- Completes a function start. Logs the time since function start.
        functionStart.FunctionEnd = function(...)
            local results = { ... }
            local msg = this.newMessage("trace").Str("_name", name)
            if results then
                for i = 1, #results, 2 do
                    if type(results[i + 1]) == "table" then
                        results[i + 1] = Serialize(results[i + 1])
                    end
                    msg = msg.Str(results[i], results[i + 1])
                end
            end
            msg.Dur(functionStart.start).Msg("Function end")
        end

        local msg = this.newMessage("trace").Str("_name", name)
        if args then
            for i = 1, #args, 2 do
                if type(args[i + 1]) == "table" then
                    args[i + 1] = Serialize(args[i + 1])
                end
                msg = msg.Str(args[i], args[i + 1])
            end
        end
        msg.Msg("Function start")

        return functionStart
    end

    return this
end

local g_tLuaKeywords = {
    ["and"] = true,
    ["break"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["false"] = true,
    ["for"] = true,
    ["function"] = true,
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["nil"] = true,
    ["not"] = true,
    ["or"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["true"] = true,
    ["until"] = true,
    ["while"] = true,
}

local serialize_infinity = math.huge

local function serialize_impl(t, tracking, indent)
    local sType = type(t)
    if sType == "table" then
        if tracking[t] ~= nil then
            if tracking[t] == false then
                error("Cannot serialize table with repeated entries", 0)
            else
                error("Cannot serialize table with recursive entries", 0)
            end
        end
        tracking[t] = true

        local result
        if next(t) == nil then
            -- Empty tables are simple
            result = "{}"
        else
            -- Other tables take more work
            local open, sub_indent, open_key, close_key, equal, comma = "{", "", "[", "]=", "=", ","

            result = open
            local seen_keys = {}
            for k, v in ipairs(t) do
                seen_keys[k] = true
                result = result .. sub_indent .. serialize_impl(v, tracking, sub_indent) .. comma
            end
            for k, v in pairs(t) do
                if not seen_keys[k] then
                    local sEntry
                    if type(k) == "string" and not g_tLuaKeywords[k] and string.match(k, "^[%a_][%a%d_]*$") then
                        sEntry = k .. equal .. serialize_impl(v, tracking, sub_indent) .. comma
                    else
                        sEntry = open_key ..
                            serialize_impl(k, tracking, sub_indent) ..
                            close_key .. serialize_impl(v, tracking, sub_indent) .. comma
                    end
                    result = result .. sub_indent .. sEntry
                end
            end
            result = result .. indent .. "}"
        end

        tracking[t] = nil
        return result

    elseif sType == "string" then
        return string.format("%q", t)

    elseif sType == "number" then
        if t ~= t then --nan
            return "0/0"
        elseif t == serialize_infinity then
            return "1/0"
        elseif t == -serialize_infinity then
            return "-1/0"
        else
            return tostring(t)
        end

    elseif sType == "boolean" or sType == "nil" then
        return tostring(t)

    else
        return tostring(t)

    end
end

function Serialize(object)
    local tTracking = {}

    return serialize_impl(object, tTracking, "")
end

return {
    Logger = NewLogger(),
    NewLogger = NewLogger,
}
