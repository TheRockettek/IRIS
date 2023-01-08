local utils = require "utils"

local pluginDirectory = "plugins"

function PluginManager(iris)
    utils.expectTable("NewPluginManager", "iris", iris, "iris:controller")

    local this = {
        _type = "iris:plugin_manager",

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
            local container = PluginContainer(localFileName)
            local success, err = container.LoadPlugin()
            if success then
                local pluginName = container.pluginInfo.name

                local existingPlugin = this.plugins[pluginName]
                if existingPlugin then
                    if existingPlugin.isLoaded then
                        iris.logger.Warn().Str("pluginNane", pluginName).Msg("A plugin with this name already is loaded")
                        return false
                    end
                end

                this.plugins[pluginName] = container
                iris.logger.Info().Str("localFileName", localFileName).Msg("Loaded plugin")
                return true
            else
                iris.logger.Warn().Str("localFileName", localFileName).Err(err).Msg("Failed to load plugin")

                return false
            end
        else
            iris.logger.Warn().Str("localFileName", localFileName).Msg("Could not locate plugin")

            return false
        end
    end

    this._secureCall = function(plugin, funcName, func)
        local success, result = pcall(func)
        if not success then
            iris.logger.Warn().Str("plugin", plugin.pluginInfo.name).Err(result).Str("type", funcName).Msg("Plugin asserted error")
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
            if plugin.plugin.OnIRISLoad then
                this._secureCall(plugin, "OnIRISLoad", plugin.plugin.OnIRISLoad())
            end
        end

        for _, plugin in pairs(this.blockingPlugins) do
            if plugin.plugin.OnIRISLoad then
                this._secureCall(plugin, "OnIRISLoad", plugin.plugin.OnIRISLoad())
            end
        end

        func.FunctionEnd()
    end

    this.OnIRISStart = function()
        local func = iris.logger.FunctionStart("OnIRISStart")

        for _, plugin in pairs(this.plugins) do
            if plugin.plugin.OnIRISStart then
                this._secureCall(plugin, "OnIRISStart", plugin.plugin.OnIRISStart())
            end
        end

        for _, plugin in pairs(this.blockingPlugins) do
            if plugin.plugin.OnIRISStart then
                this._secureCall(plugin, "OnIRISStart", plugin.plugin.OnIRISStart())
            end
        end

        func.FunctionEnd()
    end

    this.OnIRISUnload = function()
        local func = iris.logger.FunctionStart("OnIRISUnload")

        for _, plugin in pairs(this.plugins) do
            if plugin.plugin.OnIRISUnload then
                this._secureCall(plugin, "OnIRISUnload", plugin.plugin.OnIRISUnload())
            end
        end

        for _, plugin in pairs(this.blockingPlugins) do
            if plugin.plugin.OnIRISUnload then
                this._secureCall(plugin, "OnIRISUnload", plugin.plugin.OnIRISUnload())
            end
        end

        func.FunctionEnd()
    end

    return this
end

function PluginContainer(fileName)
    local this = {
        _type = "iris:plugin_container",
        _fileName = fileName,

        _module = nil,
        pluginInfo = nil,
        plugin = nil,

        isLoaded = false,
        error = nil,
    }

    this.LoadPlugin = function(iris)
        local importSuccess, importResult = pcall(dofile, this._fileName)
        if importSuccess then
            this.error = importResult
            return false, importResult
        end

        this._module = importResult
        this.pluginInfo = this._module.PluginInfo

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

    this.UnloadPlugin = function(iris)
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
    NewPluginManager = PluginManager,
    NewPluginContainer = PluginContainer
}
