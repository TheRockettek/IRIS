local errors        = require "core.errors"
local json          = require "libs.json"
local logging       = require "libs.logging"
local serialization = require "core.serialization"
local scanner       = require "core.scanner"

local VERSION = "0.0.1"

local configurationPath = "iris.config"

local defaultConfiguration = {
    turtleInput = "top",
    turtleOutput = "right",

    irisFileLocation = "iris.data",

    scanOnStart = true,
    scanDelay = 60000, -- Time in milliseconds to wait between a chest scan. This is only used during startup.
}

local function NewIRIS()
    local iris = {
        version = VERSION,
        logger = logging.NewLogger("", nil),

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

    -- Initializes IRIS
    iris.init = function(logger)
        if logger ~= nil then
            iris.logger = logger
        end

        iris.logger.Info().Msg("IRIS Version " .. VERSION)

        -- Load configuration
        local configuration, err = iris.loadConfiguration(configurationPath)
        if err ~= nil then
            iris.logger.Warn().Err(err).Msg("Failed to load configuration")
        else
            iris.configuration = configuration
        end

        -- Validate input is wrappable
        iris.tryWrapPeripheral(iris.configuration.turtleInput)

        -- Validate output is wrappable
        iris.tryWrapPeripheral(iris.configuration.turtleOutput)

        -- Load iris data
        iris.loadData()

        if iris.configuration.scanOnStart then
            iris.fullScan()
        end
    end

    -- Loads configuration. Overrides existing default configuration keys,
    -- preserving keys from the default config if not passed in a custom file.
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

    -- Loads data from an IRIS file
    iris.loadData = function()
        local path = iris.configuration.irisFileLocation

        if not fs.exists(path) then
            iris.logger.Warn().Msg("IRIS is loading from fresh file")

            return false
        end
    
        local file = fs.open(path, "rb")
        local contents = file.readAll()
        file.close()

        assert(type(contents) == "string")

        local irisData, err = serialization.Decode(contents)
        if err ~= nil then
            iris.logger.Warn().Err(err).Msg("Failed to load IRIS data")
        else
            assert(type(irisData) == "table")

            iris.irisData = irisData.data
            iris.isDataLoaded = true
        end

        return true
    end

    -- Saves data from memory to file. If not changes
    -- have been made indicated by isDataDirty, returns false.
    iris.saveData = function()
        if not iris.isDataDirty then return false, nil end

        local path = iris.configuration.irisFileLocation

        local irisDataSerialized, err = serialization.Encode(iris)
        if err ~= nil then
            return false, err
        end

        local file = fs.open(path, "wb")
        file.write(irisDataSerialized)
        file.close()

        iris.isDataDirty = false

        return true, nil
    end

    -- Performs a scan of all chests, stores and saves changes.
    -- If the last scan is before the scan delay, will not run and return false.
    iris.fullScan = function()
        local timeSince = os.epoch("utc") - iris.irisData.iris.lastScannedAt
        if timeSince < iris.configuration.scanDelay then
            iris.logger.Info().Str("since", timeSince).Str("delay", iris.configuration.scanDelay).Msg("Full scan called but not hit delay")

            return false
        end

        local chests = scanner.ScanAllChests(iris)

        iris.irisData.chests = chests
        iris.irisData.iris.lastScannedAt = os.epoch("utc")
        iris.isDataDirty = true

        local saved, err = iris.saveData()
        if err ~= nil then
            iris.logger.Warn().Err(err).Msg("failed to save IRIS data")
        end

        if saved then
            iris.logger.Info().Msg("IRIS data saved successfuly")
        end

        return true
    end

    iris.tryWrapPeripheral = function(name)
        if peripheral.wrap(name) == nil then
            iris.logger.Panic().Err(errors.ErrCouldNotWrapPeripheral).Str("name", name).Msg("Failed to wrap to peripheral")

            error("failed to wrap to peripheral " .. name)
        end
    end

    -- Returns all chests that contain a specific item. Returns slot and count.
    iris.locate = function(tryScan, name)
        if tryScan then
            iris.fullScan()
        end

        local locations = {}

        for chestName, chestData in pairs(iris.irisData.chests) do
            for slotId, item in pairs(chestData) do
                if item.name == name then
                    table.insert(locations, {
                        peripheral = chestName,
                        slot = slotId,
                        count = item.count,
                        max = item.max,
                    })
                end
            end
        end

        return locations
    end

    -- Find partial stacks of empty items..
    -- Returns list of partial stacks and empty slot candidate.
    -- Passing total store will make it only return slots that are needed.
    iris.findSpot = function(tryScan, name, totalStore, maxStack)
        local tryFindOptimalSlots = totalStore > 0

        local slots = iris.locate(tryScan, name)

        local output = {
            hasSpace = false,
            spacesMissing = 0,
            candidates = {},
            emptySlots = {},
        }

        if tryFindOptimalSlots then
            table.sort(slots, function(a, b) return (a.max - a.count) < (b.max - b.count) end)

            local toFit = totalStore

            for _, value in ipairs(slots) do
                if value.count ~= value.max then
                    table.insert(output.candidates, value)
                    output.hasSpace = true

                    toFit = toFit - (value.max - value.count)
                end
            end

            -- We have filled up all slots we have in storage, find more empty space.
            if toFit > 0 then
                local emptySlots = iris.findEmptySpaces(tryScan, math.ceil(toFit / maxStack))

                output.hasSpace = emptySlots.hasSpace
                output.spacesMissing = emptySlots.spacesMissing
                output.emptySlots = emptySlots.candidates
            end
        else
            local emptySlots = iris.findEmptySpaces(tryScan, math.ceil(totalStore / maxStack))

            output.hasSpace = emptySlots.hasSpace
            output.spacesMissing = emptySlots.spacesMissing
            output.emptySlots = emptySlots.candidates
        end

        return output
    end

    iris.findEmptySpaces = function(tryScan, maxSpacesNeeded)
        if tryScan then
            iris.fullScan()
        end

        local output = {
            hasSpace = false,
            spacesMissing = 0,
            candidates = {},
        }

        for chestName, chestData in pairs(iris.irisData.chests) do
            if chestData.total > #chestData.items then
                for slotId = 1, chestData.total, 1 do
                    if chestData.items[tostring(slotId)] == nil and maxSpacesNeeded > 0 then
                        table.insert(output.candidates, {
                            peripheral = chestName,
                            slot = slotId,
                        })

                        maxSpacesNeeded = maxSpacesNeeded - 1
                        output.hasSpace = true
                    end
                end

                if maxSpacesNeeded <= 0 then
                    break
                end
            end
        end

        -- If we have a number greater than 0, we do not have enough spaces available.
        output.hasSpace = false
        output.spacesMissing = maxSpacesNeeded

        return output
    end

    -- Returns all items based on locations.
    iris.flatten = function(tryScan)
        if tryScan then
            iris.fullScan()
        end

        local items = {}

        for chestName, chestData in pairs(iris.irisData.chests) do
            for slotId, item in pairs(chestData) do
                if items[item.name] == nil then
                    items[item.name] = {}
                end

                table.insert(items[item.name], {
                    peripheral = chestName,
                    slot = slotId,
                    count = item.count,
                    max = item.max,
                })
            end
        end

        return items
    end

    return iris
end

return {
    NewIRIS = NewIRIS
}