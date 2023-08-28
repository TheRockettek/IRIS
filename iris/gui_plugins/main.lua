local utils = require "utils"

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
        selectedTabBackground = this.palette.tertiary,
        headerBackground = this.palette.primary,
        headerText = this.palette.text,

        scrollBackground = this.palette.secondary,
        scrollBar = this.palette.primary,

        tableHeaderBackground = this.palette.secondary,
        tableHeaderText = this.palette.text,

        tableBodyBackground = this.palette.tertiary,
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
        term.setBackgroundColour(colours.black)
        term.clear()
        term.setCursorPos(1, 1)
    end

    -- Main GUI actions

    this.tabs = {}

    this.isDropdownVisible = false
    this.isSearching = false

    this.searchTextDefault = "Search..."
    this.searchQuery = ""
    this.displaySearchQuery = ""

    this.addTab = function(name, onClickFunc)
        table.insert(this.tabs, {
            name = name,
            func = onClickFunc,
        })
        return #this.tabs
    end

    -- Register tabs

    this._tabIndexIRIS = this.addTab("IRIS",
        function(tabId) this.isDropdownVisible = not this.isDropdownVisible;
            if this.isDropdownVisible then this._drawDropdown() else this
                    ._drawPage()
            end
        end)
    this._tabIndexItems = this.addTab("Items", function(tabId) this.selectedTab = tabId; this._drawPage() end)

    this.selectedTab = this._tabIndexItems

    this._onSearchQuery = function()
        local w, _ = term.getSize()
        local wt = 0
        for _, k in pairs(this.tabs) do
            wt = wt + 2 + #k.name
        end
        this.displaySearchQuery = this.searchQuery:sub(math.max(#this.searchQuery-(w-2-wt), 0), #this.searchQuery)

        term.clear()
        this._drawHeader()
        this._drawItemsPage()
    end

    this._onSearchSelect = function()
        this.isSearching = true
    end

    this._onSearchUnselect = function()
        this.isSearching = false
    end

    this._drawHeader = function()
        local w, h = term.getSize()

        local displayText = ""
        for _, k in pairs(this.tabs) do
            displayText = displayText .. " " .. k.name .. " "
        end

        if this.searchQuery == "" then
            displayText = displayText .. " " .. this.searchTextDefault
        else
            displayText = displayText .. " " .. this.displaySearchQuery
        end

        displayText = displayText:sub(1, w - 1)
        displayText = displayText .. (" "):rep(w - #displayText)

        local backgroundBlit = ""
        for i, k in pairs(this.tabs) do
            if this.selectedTab == i then
                backgroundBlit = backgroundBlit .. this.theme.selectedTabBackground.blit:rep(2 + #k.name)
            else
                backgroundBlit = backgroundBlit .. this.theme.headerBackground.blit:rep(2 + #k.name)
            end
        end
        backgroundBlit = backgroundBlit:sub(1, w)
        if this.isSearching then
            backgroundBlit = backgroundBlit .. this.theme.selectedTabBackground.blit:rep(w - #backgroundBlit)
        else
            backgroundBlit = backgroundBlit .. this.theme.headerBackground.blit:rep(w - #backgroundBlit)
        end

        local blitText = (" "):rep(w)
        local textBlit = this.theme.headerText.blit:rep(w)

        term.setCursorPos(1, 1)
        term.blit(blitText, textBlit, backgroundBlit)
        term.setCursorPos(1, 2)
        term.blit(displayText, textBlit, backgroundBlit)
        term.setCursorPos(1, 3)
        term.blit(blitText, textBlit, backgroundBlit)
    end

    this._drawPage = function()
        if this.selectedTab == this._tabIndexItems then
            this._drawItemsPage()
        end
    end

    this._sortFunc = function(a, b)
        return a.count > b.count
    end

    this._searchByQuery = function(query)
        local summary = this.iris.itemSummary
        if utils.trim(query) == "" then
            return summary
        else
            local result = {}

            for key, item in pairs(summary) do
                if string.find(item.name, query) ~= nil then
                    result[key] = item
                end
            end

            return result
        end
    end

    this._drawItemsPage = function()
        local w, h = term.getSize()

        local displayedItems = {}
        local longestLength = 0

        local summaryDictionary = this._searchByQuery(this.searchQuery)
        local summary = {}
        for _, item in pairs(summaryDictionary) do
            table.insert(summary, item)
        end

        table.sort(summary, this._sortFunc)

        for i, item in ipairs(summary) do
            table.insert(displayedItems, item)

            local length = #(tostring(item.count))
            if length > longestLength then
                longestLength = length
            end

            if i > h-3 then
                break
            end
        end

        for i, k in pairs(displayedItems) do
            term.setCursorPos(1, i+3)
            term.write(k.name:sub(1, w-longestLength-2))
            term.setCursorPos(w-#(tostring(k.count)), i+3)
            term.write(k.count)
        end
    end

    this._drawDropdown = function()
    end

    this.OnGUIStart = function()
        -- We want to stop the logger from printing messages.
        this.iris.logger.silent = true

        term.setBackgroundColour(this.theme.tableBodyBackground.colour)
        term.clear()

        local w, h = term.getSize()
        this._drawHeader()

        term.setCursorPos(1, 5)

        gui.listenToEvent("mouse_click", function(mouseType, x, y)
            if mouseType == 1 then
                this.logger.Debug().Str("X", x).Str("Y", y).Msg("Mouse click")
                if y >= 1 and y <= 3 then -- Heading click
                    local xOffset = 0
                    for tabId, tab in pairs(this.tabs) do
                        local tabWidth = 2 + #tab.name
                        this.logger.Debug().Str("tw", tabWidth).Str("offset", xOffset).Str("xc", x >= xOffset).Str("xb",
                            x <= xOffset + tabWidth).Msg("Mouse click")
                        if x >= xOffset and x <= xOffset + tabWidth then
                            tab.func(tabId)
                            this._onSearchUnselect()
                            this._drawHeader();
                        end
                        xOffset = xOffset + tabWidth
                    end
                    if x > xOffset then
                        this._onSearchSelect()
                        this._drawHeader();
                        return
                    end
                    --
                end
                this._onSearchUnselect()
                this._drawHeader();
            end
        end)

        gui.listenToEvent("char", function(char)
            if this.isSearching then
                this.searchQuery = this.searchQuery .. char
                this._onSearchQuery()
            end
        end)

        gui.listenToEvent("key", function(code)
            if code == 259 and #this.searchQuery > 0 then -- backspace
                this.searchQuery = this.searchQuery:sub(1, #this.searchQuery-1)
                this._onSearchQuery()
            elseif code == 261 and #this.searchQuery > 0 then -- delete
                this.searchQuery = ""
                this._onSearchQuery()
            end
        end)

        this._drawPage()
    end

    return this
end

return {
    PluginInfo = PluginInfo,
    Setup = Setup
}
