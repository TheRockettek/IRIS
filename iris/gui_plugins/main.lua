local PluginInfo = {
    name = "gui.main",
    friendly = "IRIS GUI Main",
    description = "This plugin provides the graphical interface for IRIS",
    author = "TheRockettek",
    version = "0.0.0",
    isBlocking = true,
}

local function Setup(gui)
    local this = {
        _type = "iris_gui:plugin",

        iris = gui.iris,
        logger = gui.logger,

        palette = {
            primary   = { colour = colours.black, hex = 0x062144 },
            secondary = { colour = colours.gray, hex = 0x0A3875 },
            tertiary  = { colour = colours.lightGray, hex = 0x09346B },
            text      = { colour = colours.white, hex = 0xFFFFFF },
        },
    }

    this.theme = {
        titleText = this.palette.text.colour,
        headerBackground = this.palette.primary.colour,
        headerText = this.palette.text.colour,
        tabBackground = this.palette.secondary.colour,
        tabText = this.palette.text.colour,

        scrollBackground = 0,
        scrollBar = 0,

        tableHeaderBackground = 0,
        tableHeaderText = 0,

        tableBodyBackground = 0,
        tableBodyText = 0,
    }

    this.OnGUILoad = function()
        -- Change palette to theme.
        if term.setPaletteColour then
            for i, k in pairs(this.palette) do
                if k.colour and k.hex then
                    this.palette[i].default = term.getPaletteColour(k.colour)
                    term.setPaletteColour(k.colour, k.hex)
                end
            end
        end
    end

    this.OnGUIStart = function()
        term.clear()

        term.setCursorPos(2, 2)
        term.write("GUI Example!")

        term.setCursorPos(1, 4)

        os.pullEvent()
    end

    this.OnGUIUnload = function()
        -- Reset palette.
        if term.setPaletteColour then
            for _, k in pairs(this.palette) do
                if k.colour and k.default then
                    term.setPaletteColour(k.colour, table.unpack(k.default))
                end
            end
        end

        term.clear()
    end

    return this
end

return {
    PluginInfo = PluginInfo,
    Setup = Setup
}
