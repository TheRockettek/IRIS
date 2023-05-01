local PluginInfo = {
    -- Unique plugin name
    name = "turtleSucker",

    -- Friendly plugin name to show to users
    friendly = "Turtle Sucker",

    -- Plugin description
    description = "Puts any items you put into a turtle back into IRIS",

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

        iris = gui.iris,

        -- TODO: custom logger which adds _plugin=... to all our messages.
        logger = gui.logger,

        eventId = nil
    }

    -- OnPluginLoad is called when IRIS GUI is starting to load your plugin.
    -- This will be called after Setup, but before OnGUILoad.
    this.OnPluginLoad = function()
        if not this.eventId then
            this.eventId = gui.listenToEvent("turtle_inventory", function()
                local turtle = this.iris.turtle
                local pullable = turtle.findPullable()

                local ignoreList = { this.iris.turtle.getNameLocal() }

                for i, k in pairs(pullable) do
                    local atlasEntry = this.iris.getFromAtlas(k)
                    local candidates, _, emptyspaces, _ = this.iris.findSpot(k.hash(), k.count,
                        atlasEntry.maxCount, ignoreList)

                    if k.count > 0 then
                        for _, m in pairs(candidates) do
                            local transferred = this.iris.push(this.iris.turtle._type, i, m._inventoryName, m._slot,
                                math.min(k.count, atlasEntry.maxCount - m.count))
                            k.count = k.count - transferred
                            if k.count > 0 then break end
                        end
                    end

                    if k.count > 0 then
                        for _, e in pairs(emptyspaces) do
                            local transferred = this.iris.push(this.iris.turtle._type, i, e.inventoryName, e.slot,
                                math.min(k.count, atlasEntry.maxCount))
                            k.count = k.count - transferred
                            if k.count > 0 then break end
                        end
                    end
                end
            end)
        end
    end

    -- OnPluginUnload is called when a plugin is being unloaded. This
    -- is called when a user decides to unload your plugin.
    this.OnPluginUnload = function()
        if this.eventId then
            gui.stopListeningToEvent("turtle_inventory", this.eventId)
            this.eventId = nil
        end
    end

    return this
end

return {
    PluginInfo = PluginInfo,
    Setup = Setup
}
