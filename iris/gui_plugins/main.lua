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
            secondary = { colour = colours.grey, hex = 0x0A3875 },
            tertiary  = { colour = colours.lightGrey, hex = 0x09346B },
            text      = { colour = colours.white, hex = 0xFFFFFF },
        },
    }

    for i, k in pairs(this.palette) do
        this.palette[i].blit = colours.toBlit(k.colour)
    end

    this.theme = {
        titleText = this.palette.text,
        selectedTabBackground = this.palette.secondary,
        headerBackground = this.palette.primary,
        headerText = this.palette.text,

        scrollBackground = this.palette.tertiary,
        scrollBar = this.palette.secondary,

        tableHeaderBackground = this.palette.tertiary,
        tableHeaderText = this.palette.text,

        tableBodyBackground = this.palette.secondary,
        tableBodyText = this.palette.text,
    }

    this.OnGUILoad = function()
        -- Change palette to theme.
        if term.setPaletteColour then
            for i, k in pairs(this.palette) do
                if k.colour and k.hex then
                    this.palette[i].default = table.pack(term.getPaletteColour(k.colour))
                    term.setPaletteColour(k.colour, k.hex)
                end
            end
        end
    end

    this.OnGUIUnload = function()
        this.iris.logger.silent = true

        -- Reset palette.
        if term.setPaletteColour then
            for _, k in pairs(this.palette) do
                if k.colour and k.default then
                    term.setPaletteColour(k.colour, table.unpack(k.default))
                end
            end
        end

        -- Reset terminal state.
        term.clear()
        term.setCursorPos(1, 1)
    end

    -- Main GUI actions

    this._tabIndexSummary = 1
    this._tabIndexItems = 2
    this._tabIndexInventories = 3
    this._tabIndexTasks = 4

    this.selectedTab = this._tabIndexSummary
    this.tabLabels = { "IRIS ", "Items", "Inventories", "Tasks" }

    this.isSearching = false
    this.searchQuery = ""

    this._drawHeader = function()
        local w, h = term.getSize()

        local displayText = " " .. table.concat(this.tabLabels, "  ") .. "  "
        if this.searchQuery == "" then
            displayText = displayText .. "Search..."
        else
            displayText = displayText .. this.searchQuery
        end
        displayText = displayText:sub(1, w - 1)
        displayText = displayText .. (" "):rep(w - #displayText)

        local hasTableHeaderBelow = (this.selectedTab == this._tabIndexItems)

        local backgroundBlit = ""
        for i, k in pairs(this.tabLabels) do
            if this.selectedTab == i then
                backgroundBlit = backgroundBlit .. this.theme.selectedTabBackground.blit:rep(2 + #k)
            else
                backgroundBlit = backgroundBlit .. this.theme.headerBackground.blit:rep(2 + #k)
            end
        end
        backgroundBlit = backgroundBlit:sub(1, w)
        backgroundBlit = backgroundBlit .. this.theme.headerBackground.blit:rep(w - #backgroundBlit)

        term.setCursorPos(1, 1)
        term.blit((" "):rep(w), this.theme.headerText.blit:rep(w), backgroundBlit)

        term.setCursorPos(1, 2)
        term.blit(displayText, this.theme.headerText.blit:rep(w), backgroundBlit)

        term.setCursorPos(1, 3)
        if hasTableHeaderBelow then
            term.blit(("\143"):rep(w), backgroundBlit, this.theme.tableHeaderBackground.blit:rep(w))
        else
            term.blit(("\143"):rep(w), backgroundBlit, this.theme.tableBodyBackground.blit:rep(w))
        end
    end

    this.OnGUIStart = function()
        -- We want to stop the logger from printing messages.
        this.iris.logger.silent = true

        term.setBackgroundColour(this.theme.tableBodyBackground.colour)
        term.clear()

        local w, h = term.getSize()
        this._drawHeader()

        paintutils.drawBox(1, 4, w, 4, this.theme.tableHeaderBackground.colour)
        term.setCursorPos(1, 5)

        gui.listenToEvent("mouse_click", function(x, y)
            print(x, y)
        end)
    end

    return this
end

return {
    PluginInfo = PluginInfo,
    Setup = Setup
}
