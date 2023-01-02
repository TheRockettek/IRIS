local events = require "core.events"
-- Colours to use within IRIS gui
-- original colour to use, r, g, b

-- You can touch these
local alignNameLeft = false
local alignCountLeft = false
local countGap = 2
local padding = 1

local blinkSpeed = 0.5
local pullSpeed = 5

local irisColours = {
    main        = { colour = colours.blue, hex = 0x2F80ED },
    accent      = { colour = colours.cyan, hex = 0x2162BA },
    background  = { colour = colours.black, hex = 0x000000 },
    contrast    = { colour = colours.white, hex = 0xFFFFFF },
    highStorage = { colour = colours.green, hex = 0x5CB764 },
    lowStorage  = { colour = colours.orange, hex = 0xF19E37 },
    noStorage   = { colour = colours.red, hex = 0xE85550 },
}

-- Dont touch these
local startY = 3

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
        pageLimit = 0,

        selectedResult = nil,
        isShowingPopup = false,

        showBlink = false,
        blinkTimer = nil,

        pullTimer = nil,

        isSearching = false,
        searchQuery = "",

        isBusy = false,

        itemPercentage = 0,
        itemSlotsUsed = 0,
        itemSlotsTotal = 0,
        itemCount = 0,
        itemTotal = 0,
    }

    gui.drawBase = function()
        term.setBackgroundColour(irisColours.background.colour)
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

        -- We also remove an extra line from bottom. I think it looks nicer like that...
        if gui.isSmallDisplay(w) then
            return h - 5
        else
            return h - 4
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

        if gui.isBusy then
            term.setBackgroundColour(irisColours.noStorage.colour)
            term.write(" [BUSY]" .. (" "):rep(w - 7))
            term.setBackgroundColour(irisColours.background.colour)

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
        local paginationDisplay = " " ..
            (" "):rep(#tostring(gui.pageCount) - #tostring(gui.pageNumber)) ..
            tostring(gui.pageNumber) .. "/" .. tostring(gui.pageCount) .. " "

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
                term.setCursorPos(1, startY + (i - 1))

                local tCol
                local bCol
                local trim = (result.display or result.name):sub(1, w - maxSizeLength - countGap - (padding * 2))
                local text = (" "):rep(padding) ..
                    trim ..
                    (" "):rep(w - #trim - #tostring(result.count) - (padding * 2)) .. result.count .. (" "):rep(padding)

                if result == gui.selectedResult then
                    tCol = colours.toBlit(irisColours.contrast.colour):rep(w)
                    bCol = colours.toBlit(irisColours.accent.colour):rep(w)
                else
                    tCol = colours.toBlit(irisColours.background.colour):rep(padding) ..
                        colours.toBlit(irisColours.contrast.colour):rep(#trim) ..
                        colours.toBlit(irisColours.background.colour):rep(w - #trim - #tostring(result.count) -
                            (padding * 2)) ..
                        colours.toBlit(colours.grey):rep(#tostring(result.count)) ..
                        colours.toBlit(irisColours.background.colour):rep(padding)
                    bCol = colours.toBlit(irisColours.background.colour):rep(w)
                end

                term.blit(text, tCol, bCol)
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

        local w, h = term.getSize()
        gui.drawSearch(w, h)

        gui.results = gui.queryItems()
        gui.resultQuery = gui.searchQuery

        local limit = gui.getResultCount()

        gui.pageNumber = pageNumber
        gui.pageCount = math.ceil(#gui.results / limit)
        gui.displayedResults = gui.paginateResults(gui.results, pageNumber, limit)
        gui.pageLimit = limit

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
            if #itemLocations > 0 then
                local location = itemLocations[1]
                location.name = itemName

                if gui.matchQuery(location, gui.searchQuery) then
                    local itemCount = 0
                    for _, itemLocation in pairs(itemLocations) do
                        itemCount = itemCount + itemLocation.count
                    end

                    if itemCount > 0 then
                        table.insert(results, {
                            name = itemName,
                            count = itemCount,
                            display = location.display,
                            nbt = location.nbt,
                            tags = location.tags,
                        })
                    end
                end
            end
        end

        table.sort(results, function(a, b)
            return (a.count) > (b.count)
        end)

        iris.logger.Debug().Str("results", #results).Str("query", gui.searchQuery).Dur("duration", start).Msg("Queried items")

        return results
    end

    gui.pullTask = function()
        local w, h = term.getSize()
        gui.isBusy = true
        gui.drawBottomBar(w, h)

        local transferred, err = iris.pushInputIntoIRIS()
        if err ~= nil then
            iris.logger.Warn().Err(err).Msg("Failed to push input into IRIS")
        end

        gui.isBusy = false
        gui.drawBottomBar(w, h)

        err = iris.save()
        if err ~= nil then
            iris.logger.Warn().Err(err).Msg("Failed to save IRIS data")
        end

        if transferred > 0 then
            gui.changePagination(gui.pageNumber, false)
        end

        gui.pullTimer = os.startTimer(pullSpeed)

        if gui.blinkTimer ~= nil then
            os.cancelTimer(gui.blinkTimer)
            gui.blinkTimer = os.startTimer(blinkSpeed)
        end
    end

    gui.calculateUsage = function()
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
    end

    gui.mainScreen = function()
        gui.drawBase()

        os.pullEvent(events.EventIrisInit)

        gui.calculateUsage()
        gui.changePagination(1, true)
        gui.drawBase()

        gui.pullTimer = os.startTimer(0)

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
                gui.onClick(paramB, paramC)
            elseif type == "turtle_inventory" then
                gui.pullTask()
            elseif type == "timer" then
                if paramA == gui.blinkTimer then
                    gui.showBlink = not gui.showBlink
                    gui.blinkTimer = os.startTimer(blinkSpeed)

                    local w, h = term.getSize()
                    gui.drawSearch(w, h)
                end
            elseif type == "char" and gui.isSearching then
                gui.searchQuery = gui.searchQuery .. paramA
                gui.changePagination(1, false)
            elseif type == "mouse_scroll" then
                if paramA == -1 then
                    gui.prevPage()
                elseif paramA == 1 then
                    gui.nextPage()
                end
            elseif type == events.EventIrisFullScan then
                gui.calculateUsage()
                gui.drawBase()
            elseif type == "term_resize" then
                gui.changePagination(gui.pageNumber, true)
                gui.drawBase()
            end
        end
    end

    gui.onClick = function(x, y)
        if y == 2 then
            -- if clicking search
            gui.isSearching = true
            gui.blinkTimer = os.startTimer(blinkSpeed)
        elseif y >= startY and y <= startY + gui.pageLimit then
            local selectedResult = gui.displayedResults[y - startY + 1]
            if selectedResult == gui.selectedResult and selectedResult ~= nil then
                gui.popup()
                gui.drawBase()
            else
                gui.selectedResult = selectedResult

                local w, h = term.getSize()
                gui.drawResults(w, h)
            end
        end
    end

    gui.drawPopup = function()
        local w, h = term.getSize()

        term.setBackgroundColour(irisColours.background.colour)
        paintutils.drawFilledBox(2, 3, w - 1, h - 2, irisColours.main.colour)

        term.setCursorPos(4, 5)
        term.write(gui.selectedResult.display)
        term.setCursorPos(4, 6)
        term.write(gui.selectedResult.name)
        term.setCursorPos(4, 7)
        term.write("Count " .. tostring(gui.selectedResult.count))
        term.setCursorPos(4, 10)
        if gui.selectedResult.nbt then
            term.write("@" .. gui.selectedResult.nbt)
        end
    end

    gui.popup = function()
        gui.drawPopup()

        while true do
            local type, paramA, paramB, paramC, paramD = os.pullEvent()
            if type == "timer" then
                if paramA == gui.blinkTimer then
                    gui.blinkTimer = os.startTimer(blinkSpeed)
                end
            elseif type == "turtle_inventory" then
                gui.pullTask()
            elseif type == "mouse_click" then
                return
            end
        end
    end

    gui.matchQuery = function(item, query)
        return query == "" or item.name:lower():find(query:lower()) ~= nil or
            item.display:lower():find(query:lower()) ~= nil
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
