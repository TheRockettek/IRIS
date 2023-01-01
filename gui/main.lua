local events = require "core.events"
-- Colours to use within IRIS gui
-- original colour to use, r, g, b

local irisColours = {
    main        = { colour = colours.blue, hex = 0x2F80ED },
    accent      = { colour = colours.cyan, hex = 0x2162BA },
    background  = { colour = colours.black, hex = 0x000000 },
    contrast    = { colour = colours.white, hex = 0xFFFFFF },
    highStorage = { colour = colours.green, hex = 0x5CB764 },
    lowStorage  = { colour = colours.orange, hex = 0xF19E37 },
    noStorage   = { colour = colours.red, hex = 0xE85550 },
}

local function setupPalette()
    if term.setPaletteColour == nil then
        return
    end

    for _, colour in pairs(irisColours) do
        term.setPaletteColour(colour.colour, colour.hex)
    end
end

local function NewGUI(iris)
    local gui = {
        pageNumber = 1,
        pageCount = 1,

        resultQuery = "",
        results = {},
        displayedResults = {},

        showBlink = false,
        blinkTimer = nil,

        isSearching = false,
        searchQuery = "",

        isInitialized = false,

        isScanning = false,
        scanningCurrent = 0,
        scanningTotal = 0,

        itemPercentage = 0,
        itemSlotsUsed = 0,
        itemSlotsTotal = 0,
        itemCount = 0,
        itemTotal = 0,
    }

    gui.drawBase = function()
        term.clear()

        local w, h = term.getSize()

        term.setTextColour(irisColours.contrast.colour)

        -- Draw header
        paintutils.drawBox(1, 1, w, 1, irisColours.main.colour)

        -- Add label
        local label = "IRIS"
        term.setCursorPos(w - #label, 1)
        term.write(label)

        paintutils.drawBox(1, 2, w, 2, irisColours.accent.colour)

        -- Add search
        gui.drawSearch(w, h)

        -- Draw results
        gui.drawResults(w, h)

        -- Draw bottom bar
        gui.drawBottomBar(w, h)
    end

    gui.getResultCount = function()
        local w, h = term.getSize()

        if gui.isSmallDisplay(w) then
            return h - 4
        else
            return h - 3
        end
    end

    gui.isSmallDisplay = function(termW)
        return termW < 39
    end

    gui.drawSearch = function(w, h)
        term.setTextColour(irisColours.contrast.colour)

        paintutils.drawBox(1, 2, w, 2, irisColours.accent.colour)

        local text
        if gui.isSearching then
            text = gui.searchQuery:sub((-w) + 1, -1)
            if gui.showBlink then
                text = text .. "_"
            end
        else
            text = gui.searchQuery:sub(-w, -1)
        end

        term.setCursorPos(1, 2)
        term.write(text)
    end

    gui.drawPercentage = function(x, y, w)
        term.setCursorPos(x, y)
        term.setBackgroundColour(irisColours.background.colour)

        if gui.isScanning then
            term.write("Scanning... (" .. tostring(gui.scanningCurrent) .. "/" .. tostring(gui.scanningTotal) .. ")")

            return
        elseif not gui.isInitialized then
            term.write("Getting Ready...")

            return
        end

        local text
        -- text = (" %.0f%% - (%d/%d) [%d/%d] "):format(gui.itemPercentage, gui.itemSlotsUsed, gui.itemSlotsTotal,
        --     gui.itemCount, gui.itemTotal)
        -- if #text > w then
        text = (" %.0f%% - (%d/%d) "):format(gui.itemPercentage, gui.itemSlotsUsed, gui.itemSlotsTotal, gui.itemCount
            , gui.itemTotal)
        if #text > w then
            text = (" %.0f%% "):format(gui.itemPercentage, gui.itemSlotsUsed, gui.itemSlotsTotal, gui.itemCount,
                gui.itemTotal)
        end
        -- end

        text = text .. (" "):rep(w - #text) -- Add any missing padding

        local barCharCount = math.floor((gui.itemPercentage / 100) * w)
        local barColour

        if (gui.itemSlotsTotal - gui.itemSlotsUsed) <= 3 then
            barColour = irisColours.noStorage
        elseif (gui.itemSlotsTotal - gui.itemSlotsUsed) <= (9 * 3) then
            barColour = irisColours.lowStorage
        else
            barColour = irisColours.highStorage
        end

        -- We use blit to draw the entire bar at once.
        -- We will apply the background like normal then apply white when on background
        -- and black when on the bar.
        term.blit(
            text,
            colours.toBlit(irisColours.background.colour):rep(barCharCount) ..
            colours.toBlit(irisColours.contrast.colour):rep(w - barCharCount),
            colours.toBlit(barColour.colour):rep(barCharCount) ..
            colours.toBlit(irisColours.background.colour):rep(w - barCharCount)
        )
    end

    gui.drawBottomBar = function(w, h)
        local paginationDisplay
        if gui.pageCount == 0 then
            paginationDisplay = (" "):rep(9)
        else
            if gui.pageNumber > 1 then
                paginationDisplay = " < "
            else
                paginationDisplay = "   "
            end

            paginationDisplay = paginationDisplay .. tostring(gui.pageNumber) .. "/" .. tostring(gui.pageCount)

            if gui.pageNumber < gui.pageCount then
                paginationDisplay = paginationDisplay .. " > "
            else
                paginationDisplay = paginationDisplay .. "   "
            end
        end

        term.setTextColour(irisColours.contrast.colour)

        if gui.isSmallDisplay(w) then -- When enabled, the pagination and item count will be on seperate lines
            paintutils.drawBox(1, h, w, h, irisColours.main.colour)
            term.setCursorPos(math.floor((w - #paginationDisplay) / 2), h)
            term.write(paginationDisplay)

            gui.drawPercentage(1, h - 1, w)
        else
            paintutils.drawBox(w - #paginationDisplay + 1, h, w, h, irisColours.main.colour)
            term.setCursorPos(w - #paginationDisplay + 1, h)
            term.write(paginationDisplay)

            gui.drawPercentage(1, h, w - #paginationDisplay)
        end
    end

    gui.drawResults = function(w, h)
        local startY = 3
        local padding = 3

        local alignNameLeft = false
        local alignCountLeft = false

        local maxSizeLength = 0
        for _, result in pairs(gui.displayedResults) do
            local sizeLength = #(tostring(result.count))
            if sizeLength > maxSizeLength then
                maxSizeLength = sizeLength
            end
        end

        term.setBackgroundColour(irisColours.background.colour)

        local limit = gui.getResultCount()

        for i = 1, limit, 1 do
            local result = gui.displayedResults[i]

            term.setCursorPos(1, startY + (i - 1))
            term.clearLine()

            if result then
                if alignNameLeft then
                    term.setCursorPos(1, startY + (i - 1))
                    term.setTextColour(irisColours.contrast.colour)
                    term.write(result.name:sub(1, w - maxSizeLength - padding))

                    local x
                    if alignCountLeft then
                        x = w - maxSizeLength + 1
                    else
                        x = w - #(tostring(result.count)) + 1
                    end

                    term.setCursorPos(x, startY + (i - 1))
                    term.setTextColour(colours.grey)
                    term.write(result.count)
                else
                    local x
                    if alignCountLeft then
                        x = 1
                    else
                        x = maxSizeLength - #(tostring(result.count)) + 1
                    end

                    term.setCursorPos(x, startY + (i - 1))
                    term.setTextColour(colours.grey)
                    term.write(result.count)

                    term.setCursorPos(maxSizeLength + padding, startY + (i - 1))
                    term.setTextColour(irisColours.contrast.colour)
                    term.write(result.name)
                end
            end
        end
    end

    gui.mainScreen = function()
        gui.drawBase()

        local blinkSpeed = 0.5

        os.pullEvent(events.EventIrisInit)
        gui.isInitialized = true

        local itemSlotsUsed, itemSlotsTotal, itemCount, itemTotal = iris.calculateUsage()
        gui.itemSlotsUsed = itemSlotsUsed
        gui.itemSlotsTotal = itemSlotsTotal
        gui.itemCount = itemCount
        gui.itemTotal = itemTotal
        if gui.itemSlotsTotal == 0 then
            gui.itemPercentage = 0
        else
            gui.itemPercentage = math.floor((gui.itemSlotsUsed / gui.itemSlotsTotal) * 100)
        end

        gui.changePagination(1, true)
        gui.drawBase()

        local pullSpeed = 5
        local pullTimer = os.startTimer(0)

        while true do
            local type, paramA, paramB, paramC, paramD = os.pullEvent()
            if type == "key" then
                if paramA == keys.backspace and gui.isSearching then
                    gui.searchQuery = gui.searchQuery:sub(1, -2)
                    gui.changePagination(1, false)
                elseif paramA == keys.enter then
                    gui.isSearching = false
                    if gui.blinkTimer ~= nil then
                        os.cancelTimer(gui.blinkTimer)
                        gui.blinkTimer = nil
                    end
                elseif paramA == keys.down or paramA == keys.pageDown then
                    gui.nextPage()
                elseif paramA == keys.up or paramA == keys.pageUp then
                    gui.prevPage()
                elseif paramA == keys.home then
                    gui.changePagination(1, false)
                end
            elseif type == "mouse_click" then
                -- if clicking search
                gui.isSearching = true
                gui.blinkTimer = os.startTimer(blinkSpeed)
            elseif type == "timer" then
                if paramA == gui.blinkTimer then
                    gui.showBlink = not gui.showBlink
                    gui.blinkTimer = os.startTimer(blinkSpeed)

                    local w, h = term.getSize()
                    gui.drawSearch(w, h)
                elseif paramA == pullTimer then
                    iris.pushInputIntoIRIS(true)

                    local err = iris.save()
                    if err ~= nil then
                        iris.logger.Warn().Err(err).Msg("Failed to save IRIS data")
                    end

                    gui.changePagination(gui.pageNumber, false)

                    pullTimer = os.startTimer(pullSpeed)

                    if gui.blinkTimer ~= nil then
                        os.cancelTimer(gui.blinkTimer)
                        gui.blinkTimer = os.startTimer(blinkSpeed)
                    end
                end
            elseif type == "char" and gui.isSearching then
                gui.searchQuery = gui.searchQuery .. paramA
                gui.changePagination(1, false)
            elseif type == events.EventIrisScanStart then
                gui.isScanning = true
                gui.drawBase()
            elseif type == events.EventIrisScanComplete then
                gui.isScanning = false
                gui.drawBase()
            elseif type == events.EventIrisFullScan then
                gui.itemSlotsUsed = paramA
                gui.itemSlotsTotal = paramB
                gui.itemCount = paramC
                gui.itemTotal = paramD
                gui.itemPercentage = math.floor((gui.itemSlotsUsed / gui.itemSlotsTotal) * 100)
                gui.drawBase()
            end
        end
    end

    gui.nextPage = function()
        if gui.pageNumber < gui.pageCount then
            gui.changePagination(gui.pageNumber + 1, false)
        end
    end

    gui.prevPage = function()
        if gui.pageNumber > 1 then
            gui.changePagination(gui.pageNumber - 1, false)
        end
    end

    gui.changePagination = function(pageNumber, resetQuery)
        local start = os.epoch("utc")

        if resetQuery then
            gui.searchQuery = ""
        end

        gui.results = gui.queryItems()
        gui.resultQuery = gui.searchQuery

        local limit = gui.getResultCount()

        gui.pageNumber = pageNumber
        gui.pageCount = math.ceil(#gui.results / limit)
        gui.displayedResults = gui.paginateResults(gui.results, pageNumber, limit)

        local w, h = term.getSize()
        gui.drawResults(w, h)
        gui.drawBottomBar(w, h)

        iris.logger.Trace().Dur("duration", start).Str("page", pageNumber).Str("resetQuery", resetQuery).Msg("Completed page transition")
    end

    gui.paginateResults = function(results, pageNumber, limit)
        local displayedResults = {}

        for i = 1 + (limit * (pageNumber - 1)), limit * pageNumber, 1 do
            local result = results[i]
            if result then
                table.insert(displayedResults, result)
            else
                break
            end
        end

        return displayedResults
    end

    gui.queryItems = function()
        local start = os.epoch("utc")
        local results = {}

        local items = iris.flatten()
        for itemName, itemLocations in pairs(items) do
            if gui.matchQuery(itemName, gui.searchQuery) then
                local itemCount = 0
                for _, itemLocation in pairs(itemLocations) do
                    itemCount = itemCount + itemLocation.count
                end

                table.insert(results, {
                    name = itemName,
                    count = itemCount,
                })
            end
        end

        table.sort(results, function(a, b)
            return (a.count) > (b.count)
        end)

        iris.logger.Debug().Str("results", #results).Str("query", gui.searchQuery).Dur("duration", start).Msg("Queried items")

        return results
    end

    gui.matchQuery = function(itemName, query)
        return query == "" or itemName:find(query) ~= nil
    end

    gui.run = function()
        setupPalette()
        gui.mainScreen()
    end

    return gui
end

return {
    NewGUI = NewGUI
}
