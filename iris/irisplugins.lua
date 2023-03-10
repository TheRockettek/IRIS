local utils = require "utils"

local pluginDirectory = "plugins"

function IRISPluginManager(iris)
    utils.expectTable("IRISPluginManager", "iris", iris, "iris:controller")

    local this = {
        _type = "iris:plugin_manager",

        plugins = {},
    }

    this.ListPlugins = function()
        local pluginNames = {}

        for i, plugin in pairs(this.plugins) do
            pluginNames[i] = plugin.isLoaded
        end

        return pluginNames
    end

    this.LoadAllPlugins = function()
        local func = iris.logger.FunctionStart("LoadAllPlugins")

        local localFolderName = fs.combine(shell.dir(), pluginDirectory)
        if fs.exists(localFolderName) then
            if fs.isDir(localFolderName) then
                local list = fs.list(localFolderName)
                for _, fileName in pairs(list) do
                    this.LoadPlugin(fileName)
                end
            else
                iris.logger.Warn().Str("localFolderName", localFolderName).Msg("Plugin folder is not a directory")
            end
        else
            iris.logger.Warn().Str("localFolderName", localFolderName).Msg("Plugin folder does not eixst")
        end

        func.FunctionEnd()
    end

    this.LoadPlugin = function(fileName)
        local localFileName = fs.combine(shell.dir(), pluginDirectory, fileName)
        if fs.exists(localFileName) then
            local container = IRISPluginContainer(localFileName)
            local success, err = container.LoadPlugin(iris)
            if success then
                local pluginName = container.pluginInfo.name

                local existingPlugin = this.plugins[pluginName]
                if existingPlugin then
                    if existingPlugin.isLoaded then
                        iris.logger.Warn().Str("pluginNane", pluginName)
                            .Msg("A plugin with this name already is loaded")
                        return false
                    end
                end

                this.plugins[pluginName] = container
                iris.logger.Info().Str("localFileName", localFileName).Msg("Loaded plugin")
                return true
            else
                iris.logger.Error().Str("localFileName", localFileName).Err(err).Msg("Failed to load plugin")

                return false
            end
        else
            iris.logger.Error().Str("localFileName", localFileName).Msg("Could not locate plugin")

            return false
        end
    end

    this._secureCall = function(plugin, funcName, func)
        local success, result = pcall(func)
        if not success then
            iris.logger.Error().Str("plugin", plugin.pluginInfo.name).Err(result).Str("type", funcName).Msg(
                "Plugin asserted error")
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

    this.OnIRISLoad = function()
        local func = iris.logger.FunctionStart("OnIRISLoad")

        for _, plugin in pairs(this.plugins) do
            if not plugin.isBlocking then
                if plugin.plugin.OnIRISLoad then
                    this._secureCall(plugin, "OnIRISLoad", plugin.plugin.OnIRISLoad)
                end
            end
        end

        for _, plugin in pairs(this.plugins) do
            if plugin.isBlocking then
                if plugin.plugin.OnIRISLoad then
                    this._secureCall(plugin, "OnIRISLoad", plugin.plugin.OnIRISLoad)
                end
            end
        end

        func.FunctionEnd()
    end

    this.OnIRISStart = function()
        local func = iris.logger.FunctionStart("OnIRISStart")

        for _, plugin in pairs(this.plugins) do
            if not plugin.isBlocking then
                if plugin.plugin.OnIRISStart then
                    this._secureCall(plugin, "OnIRISStart", plugin.plugin.OnIRISStart)
                end
            end
        end

        for _, plugin in pairs(this.plugins) do
            if plugin.isBlocking then
                if plugin.plugin.OnIRISStart then
                    this._secureCall(plugin, "OnIRISStart", plugin.plugin.OnIRISStart)
                end
            end
        end

        func.FunctionEnd()
    end

    this.OnIRISUnload = function()
        local func = iris.logger.FunctionStart("OnIRISUnload")

        for _, plugin in pairs(this.plugins) do
            if plugin.plugin.OnIRISUnload then
                this._secureCall(plugin, "OnIRISUnload", plugin.plugin.OnIRISUnload)
            end
        end

        for _, plugin in pairs(this.plugins) do
            if plugin.plugin.OnIRISUnload then
                this._secureCall(plugin, "OnIRISUnload", plugin.plugin.OnIRISUnload)
            end
        end

        func.FunctionEnd()
    end

    return this
end

function IRISPluginContainer(fileName)
    local this = {
        _type = "iris:plugin_container",
        _fileName = fileName,

        _module = nil,
        pluginInfo = nil,
        plugin = nil,
        isBlocking = false,

        isLoaded = false,
        error = nil
    }

    this._loadPlugin = function(filename)
        local result, err = loadfile(filename, nil, _ENV)
        if result then
            return result()
        else
            error(err)
        end
    end

    this.LoadPlugin = function(iris)
        local importSuccess, importResult = pcall(this._loadPlugin, this._fileName)
        if not importSuccess then
            this.error = importResult
            return false, importResult
        end

        this._module = importResult
        this.pluginInfo = this._module.PluginInfo
        this.isBlocking = this.pluginInfo.isBlocking or false

        local setupSuccess, setupResult = pcall(this._module.Setup, iris)
        this.plugin = setupResult

        this.isLoaded = setupSuccess

        if not setupSuccess then
            this.error = setupResult
            return false, setupResult
        else
            local typeSuccess, typeError = pcall(utils.expect, "LoadPlugin", "PluginInfo", this.pluginInfo, "table")
            if typeSuccess then
                typeSuccess, typeError = pcall(utils.expectTable, "LoadPlugin", "Plugin", this.plugin, "iris:plugin")
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

return {
    IRISPluginManager = IRISPluginManager,
    IRISPluginContainer = IRISPluginContainer
}
