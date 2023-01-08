local utils = require "utils"

local pluginDirectory = "gui_plugins"

local PluginInfo = {
    name = "gui",
    friendly = "IRIS GUI",
    description = "This plugin provides the graphical interface for IRIS",
    author = "TheRockettek",
    version = "1.0.0",
    isBlocking = true,
}

local function NewIRISGUI(iris)
    local this = {
        _type = "iris_gui:controller",

        logger = iris.logger,

        pluginManager = nil,

        _registeredEventCount = {},
        registeredEvents = {},
    }

    this.pluginManager = GUIPluginManager(this)

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

function GUIPluginManager(gui)
    utils.expectTable("NewPluginManager", "gui", gui, "iris_gui:controller")

    local this = {
        _type = "iris_gui:plugin_manager",

        plugins = {},
        blockingPlugins = {},
    }

    this.ListPlugins = function()
        local pluginNames = {}

        for i, plugin in pairs(this.plugins) do
            pluginNames[i] = plugin.isLoaded
        end
        for i, plugin in pairs(this.blockingPlugins) do
            pluginNames[i] = plugin.isLoaded
        end

        return pluginNames
    end

    this.LoadAllPlugins = function()
        local func = gui.logger.FunctionStart("LoadAllPlugins")

        local localFolderName = fs.combine(shell.dir(), pluginDirectory)
        if fs.exists(localFolderName) then
            if fs.isDir(localFolderName) then
                local list = fs.list(localFolderName)
                for _, fileName in pairs(list) do
                    this.LoadPlugin(fileName)
                end
            else
                gui.logger.Warn().Str("localFolderName", localFolderName).Msg("Plugin folder is not a directory")
            end
        else
            gui.logger.Warn().Str("localFolderName", localFolderName).Msg("Plugin folder does not eixst")
        end

        func.FunctionEnd()
    end

    this.LoadPlugin = function(fileName)
        local localFileName = fs.combine(shell.dir(), pluginDirectory, fileName)
        if fs.exists(localFileName) then
            local container = GUIPluginContainer(localFileName)
            local success, err = container.LoadPlugin(gui)
            if success then
                local pluginName = container.pluginInfo.name

                local existingPlugin = this.plugins[pluginName]
                if existingPlugin then
                    if existingPlugin.isLoaded then
                        gui.logger.Warn().Str("pluginNane", pluginName).Msg("A plugin with this name already is loaded")
                        return false
                    end
                end

                this.plugins[pluginName] = container
                gui.logger.Info().Str("localFileName", localFileName).Msg("Loaded plugin")
                return true
            else
                gui.logger.Warn().Str("localFileName", localFileName).Err(err).Msg("Failed to load plugin")

                return false
            end
        else
            gui.logger.Warn().Str("localFileName", localFileName).Msg("Could not locate plugin")

            return false
        end
    end

    this._secureCall = function(plugin, funcName, func)
        local success, result = pcall(func)
        if not success then
            gui.logger.Warn().Str("plugin", plugin.pluginInfo.name).Err(result).Str("type", funcName).Msg("Plugin asserted error")
        end
    end

    this.UnloadPlugin = function(pluginName)
        local plugin = this.plugins[pluginName]
        if not plugin then
            return
        end

        plugin.UnloadPlugin()
        this.plugins[pluginName] = nil
    end

    this.ReloadPlugin = function(pluginName)
        local plugin = this.plugins[pluginName]
        if not plugin then
            return
        end

        this.UnloadPlugin(pluginName)
        return this.LoadPlugin(plugin._fileName)
    end

    this.OnGUILoad = function()
        local func = gui.logger.FunctionStart("OnGUILoad")

        for _, plugin in pairs(this.plugins) do
            if plugin.plugin.OnGUILoad then
                this._secureCall(plugin, "OnGUILoad", plugin.plugin.OnGUILoad)
            end
        end

        for _, plugin in pairs(this.blockingPlugins) do
            if plugin.plugin.OnGUILoad then
                this._secureCall(plugin, "OnGUILoad", plugin.plugin.OnGUILoad)
            end
        end

        func.FunctionEnd()
    end

    this.OnGUIStart = function()
        local func = gui.logger.FunctionStart("OnGUIStart")

        for _, plugin in pairs(this.plugins) do
            if plugin.plugin.OnGUIStart then
                this._secureCall(plugin, "OnGUIStart", plugin.plugin.OnGUIStart)
            end
        end

        for _, plugin in pairs(this.blockingPlugins) do
            if plugin.plugin.OnGUIStart then
                this._secureCall(plugin, "OnGUIStart", plugin.plugin.OnGUIStart)
            end
        end

        func.FunctionEnd()
    end

    this.OnGUIUnload = function()
        local func = gui.logger.FunctionStart("OnGUIUnload")

        for _, plugin in pairs(this.plugins) do
            if plugin.plugin.OnGUIUnload then
                this._secureCall(plugin, "OnGUIUnload", plugin.plugin.OnGUIUnload)
            end
        end

        for _, plugin in pairs(this.blockingPlugins) do
            if plugin.plugin.OnGUIUnload then
                this._secureCall(plugin, "OnGUIUnload", plugin.plugin.OnGUIUnload)
            end
        end

        func.FunctionEnd()
    end

    return this
end

function GUIPluginContainer(fileName)
    local this = {
        _type = "iris_gui:plugin_container",
        _fileName = fileName,

        _module = nil,
        pluginInfo = nil,
        plugin = nil,

        isLoaded = false,
        error = nil,
    }

    this._loadPlugin = function(filename)
        local result, err = loadfile(filename, nil, _ENV)
        if result then
            return result()
        else
            error(err)
        end
    end

    this.LoadPlugin = function(gui)
        local importSuccess, importResult = pcall(this._loadPlugin, this._fileName)
        if not importSuccess then
            this.error = importResult
            return false, importResult
        end

        this._module = importResult
        this.pluginInfo = this._module.PluginInfo

        local setupSuccess, setupResult = pcall(this._module.Setup, gui)
        this.plugin = setupResult

        this.isLoaded = setupSuccess

        if not setupSuccess then
            this.error = setupResult
            return false, setupResult
        else
            local typeSuccess, typeError = pcall(utils.expect, "LoadPlugin", "PluginInfo", this.pluginInfo, "table")
            if typeSuccess then
                typeSuccess, typeError = pcall(utils.expectTable, "LoadPlugin", "Plugin", this.plugin, "iris_gui:plugin")
                if typeSuccess then
                    typeSuccess, typeError = pcall(utils.expect, "LoadPlugin", "PluginName", this.pluginInfo.name,
                        "string")
                    if typeSuccess then
                        this.error = nil
                        return true, nil
                    end
                end
            end

            this.error = typeError
            return false, typeError
        end
    end

    this.UnloadPlugin = function()
        if this._module and this._module.OnPluginUnload then
            pcall(this._module.OnPluginUnload)
        end

        this.isLoaded = false
        this.error = nil
        this._module = nil
    end

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
