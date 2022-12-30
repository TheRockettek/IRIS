local errors = require "core.errors"
local json   = require "libs.json"
local logging= require "libs.logging"
local serialization = require "core.serialization"
local peripherals   = require "core.peripherals"
local VERSION = "0.0.1"

local configurationPath = "iris.config"

local defaultConfiguration = {
    turtleInput = "top",
    turtleOutput = "right",

    irisFileLocation = "iris.data",

    scanOnStart = true,
    scanDelay = 60000, -- Time in milliseconds to wait between a chest scan. This is only used during startup.
}

local function tryWrapPeripheral(name)
    if peripheral.wrap(name) == nil then
        logging.Logger.Panic().Err(errors.ErrCouldNotWrapPeripheral).Msg("name", name).Msg("Failed to wrap to peripheral")

        error("failed to wrap to peripheral " .. name)
    end
end

local function NewIRIS()
    local iris = {
        version = VERSION,

        isDataLoaded = false,
        isDataDirty = false,
        irisData = {
            iris = {
                lastScannedAt = 0,
            },
            chests = {}
        },

        configuration = defaultConfiguration,
    }

    iris.init = function()
        -- Load configuration
        local configuration, err = iris.loadConfiguration(configurationPath)
        if err ~= nil then
            logging.Logger.Warn().Err(err).Msg("Failed to load configuration")
        else
            iris.configuration = configuration
        end

        -- Validate input is wrappable
        tryWrapPeripheral(iris.configuration.turtleInput)

        -- Validate output is wrappable
        tryWrapPeripheral(iris.configuration.turtleOutput)

        -- Load iris data
        iris.loadData()

        if iris.configuration.scanOnStart then
            iris.fullScan()
        end
    end

    iris.loadConfiguration = function(path)
        if not fs.exists(path) then
            return nil, errors.ErrConfigurationDoesNotExist
        end

        local file = fs.open(path, "rb")
        local contents = file.readAll()
        file.close()

        assert(type(contents) == "string")

        local jsonDecode = json.Decode(contents)
        if jsonDecode == nil then
            return defaultConfiguration, errors.ErrFailedToJSONDecode
        end

        assert(type(jsonDecode) == "table")

        local configuration = defaultConfiguration

        for key, value in pairs(jsonDecode) do
            configuration[key] = value
        end

        return configuration, nil
    end

    iris.loadData = function()
        local path = iris.configuration.irisFileLocation

        if not fs.exists(path) then
            logging.Logger.Warn().Err(err).Msg("IRIS from fresh start")

            return false
        end
    
        local file = fs.open(path, "rb")
        local contents = file.readAll()
        file.close()

        assert(type(contents) == "string")

        local irisData, err = serialization.Decode(contents)
        if err ~= nil then
            logging.Logger.Warn().Err(err).Msg("Failed to load IRIS data")
        else
            assert(type(irisData) == "table")

            iris.irisData = irisData.data
            iris.isDataLoaded = true
        end

        return true
    end

    iris.saveData = function()
        local path = iris.configuration.irisFileLocation

        local irisDataSerialized, err = serialization.Encode(iris.irisData)
        if err ~= nil then
            return err
        end

        local file = fs.open(path, "wb")
        file.write(irisDataSerialized)
        file.close()

        iris.isDataDirty = false

        return true
    end

    iris.fullScan = function()
        local timeSince = os.epoch("utc") - iris.irisData.iris.lastScannedAt
        if timeSince < iris.configuration.scanDelay then
            logging.Logger.Info().Str("since", timeSince).Str("delay", iris.configuration.scanDelay).Msg("Full scan called but not hit delay")

            return false
        end

        local chests = peripherals.FindAllChests()

        iris.irisData.chests = chests
        iris.irisData.iris.lastScannedAt = os.epoch("utc")

        iris.isDataDirty = true

        iris.saveData()

        return true
    end

    return iris
end

return {
    NewIRIS = NewIRIS
}