local PluginInfo = {
    name = "gui.main",
    friendly = "IRIS GUI Main",
    description = "This plugin provides the graphical interface for IRIS",
    author = "TheRockettek",
    version = "0.0.0",
    isBlocking = false,
}

local function Setup(gui)
    local this = {
        _type = "iris_gui:plugin",

        logger = gui.logger
    }

    this.OnGUILoad = function()
        -- TODO: Load theme
    end

    this.OnGUIStart = function()
        term.clear()

        term.setCursorPos(2, 2)
        term.write("GUI Example!")

        term.setCursorPos(1, 4)
        gui.listenToEvent("*", function(...)
            local args = { ... }
            for i, k in pairs(args) do
                print(i, k)
            end
        end)
    end

    this.OnGUIUnload = function()
        -- TODO: Go back to original palette

        term.clear()
    end

    return this
end

return {
    PluginInfo = PluginInfo,
    Setup = Setup
}
