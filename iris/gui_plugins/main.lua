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

    this.offset = 0
    this.selectedItem = nil
    this.totalResults = 0
    this.shownResults = {}

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

    this._refreshData = function(resetOffset)
        if resetOffset then
            this.offset = 0
        end

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

    this._refreshDataSelect = function()
        this.isSearching = true
    end

    this._changeOffset = function(newOffset)
        if newOffset ~= this.offset then
            this.offset = newOffset
            this._refreshData()
        end
    end

    this._refreshDataUnselect = function()
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

        local results = {}
        local longestLength = 0
        
        local summaryDictionary = this._searchByQuery(this.searchQuery)
        local summary = {}
        for _, item in pairs(summaryDictionary) do
            table.insert(summary, item)
        end

        table.sort(summary, this._sortFunc)

        for _, item in ipairs(summary) do
            table.insert(results, item)

            local length = #(tostring(item.count))
            if length > longestLength then
                longestLength = length
            end
        end

        this.totalResults = #results

        for i=1, this.offset, 1 do
            table.remove(results, 1)
        end

        this.shownResults = results

        for i, k in pairs(this.shownResults) do
            term.setCursorPos(1, i+3)
            term.write(k.name:sub(1, w-longestLength-1))
            term.setCursorPos(w-#(tostring(k.count))+1, i+3)
            term.write(k.count)

            if i >= h-3 then
                break
            end
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
            local _, h = term.getSize()

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
                            this._refreshDataUnselect()
                            this._drawHeader();
                        end
                        xOffset = xOffset + tabWidth
                    end
                    if x > xOffset then
                        this._refreshDataSelect()
                        this._drawHeader();
                        return
                    end
                else
                    if y >= 4 and y <= h then
                        local yOffset = y - 3
                        local totalRows = #this.shownResults
                        if yOffset <= totalRows then
                            local selectedItem = this.shownResults[yOffset]
                            local atlasEntry = this.iris.getFromAtlas(selectedItem)
                            local pulledItems = math.min(selectedItem.count, atlasEntry.maxCount)
                            local candidates, itemsRemaining = this.iris.findItem(selectedItem.hash(), pulledItems, { this.iris.turtle.getNameLocal() })

                            local slotNumber = 0

                            local turtleInventory = this.iris.turtle.list()
                            for i=1, 16, 1 do
                                if turtleInventory[i] == nil then
                                    slotNumber = i
                                    break
                                end
                            end

                            if slotNumber == 0 then
                                return
                            end

                            local total = 0

                            for _, candidate in pairs(candidates) do
                                local transferred = this.iris.push(candidate._inventoryName, candidate._slot, this.iris.turtle._type, slotNumber, candidate.count)
                                total = total + transferred

                                this.iris.turtle.reserveItem(slotNumber, selectedItem, total)
                            end

                            this._refreshDataSelect()
                            this._drawHeader();
                        end
                    end
                end
                this._refreshDataUnselect()
                this._drawHeader();
            end
        end)

        gui.listenToEvent("mouse_scroll", function(scroll)
            if scroll == 1 then -- scroll down
                local _, h = term.getSize()
                local totalShown = h-3
                if this.offset+totalShown-1 < this.totalResults then
                    this._changeOffset(this.offset + 1)
                end
            elseif scroll == -1 then -- scroll up
                if this.offset > 0 then
                    this._changeOffset(this.offset - 1)
                end
            end
        end)

        gui.listenToEvent("char", function(char)
            if this.isSearching then
                this.searchQuery = this.searchQuery .. char
                this._refreshData(true)
            end
        end)

        gui.listenToEvent("key", function(code)
            local _, h = term.getSize()
            local totalShown = h-3

            if code == keys.backspace and #this.searchQuery > 0 then -- backspace
                this.searchQuery = this.searchQuery:sub(1, #this.searchQuery-1)
                this._refreshData(true)
            elseif code == keys.delete and #this.searchQuery > 0 then -- delete
                this.searchQuery = ""
                this._refreshData(true)
            elseif code == keys.pageUp then -- page up
                this._changeOffset(math.max(0, this.offset - totalShown))
            elseif code == keys.pageDown then -- page down
                this._changeOffset(math.min(this.totalResults - totalShown + 1, this.offset + totalShown))
            elseif code == keys.home then
                this._changeOffset(0)
            end
        end)

        gui.listenToEvent("iris_refresh", function()
            this._refreshDataUnselect()
            this._drawHeader();
        end)

        this._drawPage()
    end

    return this
end

return {
    PluginInfo = PluginInfo,
    Setup = Setup
}
