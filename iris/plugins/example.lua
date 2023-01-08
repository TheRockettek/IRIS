local PluginInfo = {
    -- Unique plugin name
    name = "example",

    -- Friendly plugin name to show to users
    friendly = "Example plugin",

    -- Plugin description
    description = "This is an example plugin",

    -- Author display name
    author = "TheRockettek",

    version = "0.0.0",

    -- Signifies if this plugin may block IRIS and takes over the main event loop.
    -- An example would be a plugin that provides a graphical interface. You should
    -- only have one blocking plugin, and these will be handled last.
    isBlocking = false,
}

local function Setup(iris)
    local this = {
        -- This is mandatory. This lets IRIS know it is a plugin.
        _type = "iris:plugin",

        -- TODO: custom logger which adds _plugin=... to all our messages.
        logger = iris.logger
    }

    -- OnPluginLoad is called when IRIS is starting to load your plugin.
    -- This will be called after Setup, but before OnIRISLoad.
    this.OnPluginLoad = function()
        this.logger.Info().Msg("OnPluginLoad")
    end

    -- OnPluginUnload is called when a plugin is being unloaded. This
    -- is called when a user decides to unload your plugin.
    this.OnPluginUnload = function()
        this.logger.Info().Msg("OnPluginUnload")
    end

    -- OnIRISLoad is called when IRIS has loaded all plugins and starts
    -- any internal routines. This is also called when a user
    -- decides to enable your plugin manually.
    this.OnIRISLoad = function()
        this.logger.Info().Msg("OnIRISLoad")
    end

    -- OnIRISStart is called when IRIS has loaded all plugins and
    -- completed all internal routines. This is also called when
    -- a user decides to enable your plugin manually.
    this.OnIRISStart = function()
        this.logger.Info().Msg("OnIRISStart")
    end

    -- OnIRISLoad is called when IRIS is unloading the plugin.
    -- This is not called when terminating, but will be called
    -- if a user decides to turn off your plugin.
    -- If you are overwriting an event, it is recommend you now
    -- set the original event.
    this.OnIRISUnload = function()
        this.logger.Info().Msg("OnIRISUnload")
    end

    return this
end

return {
    PluginInfo = PluginInfo,
    Setup = Setup
}
