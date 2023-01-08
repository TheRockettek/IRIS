local plugins = require "plugins"

local PluginInfo = {
    -- Unique plugin name
    name = "gui",

    -- Friendly plugin name to show to users
    friendly = "IRIS GUI",

    -- Plugin description
    description = "This plugin provides the graphical interface for IRIS",

    -- Author display name
    author = "TheRockettek",

    version = "1.0.0",

    -- Signifies if this plugin may block IRIS and takes over the main event loop.
    -- An example would be a plugin that provides a graphical interface. You should
    -- only have one blocking plugin, and these will be handled last.
    isBlocking = false,
}

local function NewIRISGUI(iris)
    local this = {
        _type = "iris_gui:controller",

        logger = iris.logger,

        pluginManager = nil,

        _registeredEventCount = {},
        registeredEvents = {},
    }

    this.pluginManager = plugins.NewPluginManager(this)

    -- Plugin manager code is located at bottom, to ensure IRIS GUI functions are defined.

    this.listenToEvent = function(eventName, func)
        eventName = eventName:lower()

        local event = this.registeredEvents[eventName]
        if not event then
            this.registeredEvents[eventName] = {}
            this._registeredEventCount[eventName] = 0
        end

        this._registeredEventCount[eventName] = this._registeredEventCount[eventName] + 1
        local eventId = tostring(this._registeredEventCount[eventName])

        this.registeredEvents[eventName][tostring(eventId)] = func

        return eventId
    end

    this.stopListeningToEvent = function(eventName, eventId)
        this.registeredEvents[eventName][tostring(eventId)] = nil
    end

    this.run = function()
        this.pluginManager.OnGUIStart()

        while true do
            local pullEventRawData = table.pack(os.pullEventRaw())
            local eventType = string.lower(pullEventRawData[1])
            if eventType == "terminate" then
                break
            end

            local eventData = table.unpack(pullEventRawData, 2)

            local event = this.registeredEvents[eventType]
            if event then
                for _, k in pairs(event) do
                    k(eventData)
                end
            end
        end

        this.pluginManager.OnIRISUnload()
    end

    this.pluginManager.LoadAllPlugins()
    this.pluginManager.OnGUILoad()

    return this
end

local function Setup(iris)
    local this = {
        _type = "iris:plugin",

        gui = NewIRISGUI(iris),
        logger = iris.logger,
    }

    this.OnIRISStart = function()
        this.gui.run()
    end

    return this
end

return {
    PluginInfo = PluginInfo,
    Setup = Setup
}
