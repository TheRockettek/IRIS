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

    -- Signifies if this plugin may block IRIS GUI and takes over the main event loop.
    -- An example would be a plugin that provides a graphical interface. You should
    -- only have one blocking plugin, and these will be handled last.
    isBlocking = false,
}

local function Setup(gui)
    local this = {
        -- This is mandatory. This lets IRIS GUI know it is a plugin.
        _type = "iris_gui:plugin",

        -- TODO: custom logger which adds _plugin=... to all our messages.
        logger = gui.logger
    }

    -- OnPluginLoad is called when IRIS GUI is starting to load your plugin.
    -- This will be called after Setup, but before OnGUILoad.
    this.OnPluginLoad = function()
        this.logger.Msg("OnPluginLoad")
    end

    -- OnPluginUnload is called when a plugin is being unloaded. This
    -- is called when a user decides to unload your plugin.
    this.OnPluginUnload = function()
        this.logger.Msg("OnPluginUnload")
    end

    -- OnGUILoad is called when IRIS GUI has loaded all plugins and starts
    -- any internal routines. This is also called when a user
    -- decides to enable your plugin manually.
    this.OnGUILoad = function()
        this.logger.Msg("OnGUILoad")
    end

    -- OnGUIStart is called when IRIS GUI has loaded all plugins and
    -- completed all internal routines. This is also called when
    -- a user decides to enable your plugin manually.
    this.OnGUIStart = function()
        this.logger.Msg("OnGUIStart")
    end

    -- OnGUILoad is called when IRIS GUI is unloading the plugin.
    -- This is not called when terminating, but will be called
    -- if a user decides to turn off your plugin.
    -- If you are overwriting an event, it is recommend you now
    -- set the original event.
    this.OnGUIUnload = function()
        this.logger.Msg("OnGUIUnload")
    end

    return this
end

return {
    PluginInfo = PluginInfo,
    Setup = Setup
}
