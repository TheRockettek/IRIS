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

    -- OnGUILoad is called when IRIS GUI is starting up.
    -- This is also called when a user decides to enable your plugin manually.
    this.OnGUILoad = function()
        this.logger.Info().Str("eventId", this.eventId).Msg("OnGUILoad")

        if this.eventId == nil then
            this.eventId = gui.listenToEvent("turtle_inventory", function()
                this.logger.Debug().Msg("Triggered turtle sucker")

                local turtle = this.iris.turtle
                local pullable = turtle.findPullable()

                local ignoreList = { this.iris.turtle.getNameLocal() }

                this.logger.Trace().Json("pullable", pullable).Send()

                for i, k in pairs(pullable) do
                    local atlasEntry = this.iris.getFromAtlas(k)
                    local candidates, _, emptyspaces, _ = this.iris.findSpot(k.hash(), k.count,
                        atlasEntry.maxCount, ignoreList)


                    this.logger.Trace().Json("item", k).Json("candidates", candidates).Json("emptyspaces", emptyspaces)
                        .Send()

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

            this.logger.Info().Str("event_id", this.eventId).Msg("Created turtle_inventory listener")
        end
    end

    -- OnGUIUnload is called when IRIS GUI is unloading the plugin.
    -- This is not called when terminating, but will be called
    -- if a user decides to turn off your plugin.
    -- If you are overwriting an event, it is recommend you now
    -- set the original event.
    this.OnGUIUnload = function()
        this.logger.Info().Str("eventId", this.eventId).Msg("OnGUIUnload")

        if this.eventId then
            gui.stopListeningToEvent("turtle_inventory", this.eventId)
            this.logger.Info().Str("event_id", this.eventId).Msg("Removed turtle_inventory listener")
            this.eventId = nil
        end
    end

    return this
end

return {
    PluginInfo = PluginInfo,
    Setup = Setup
}
