local events = require "core.events"
local errors = require "core.errors"
local waitgroup = require "libs.waitgroup"
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
        pageNumber = 0,
        pageCount = 0,

        resultQuery = "",
        results = {},
        displayedResults = {},
        pageLimit = 0,

        selectedResult = nil,
        isShowingPopup = false,

        showBlink = false,
        blinkTimer = nil,

        isSearching = false,
        searchQuery = "",

        isBusy = false,

        itemPercentage = 0,
        itemSlotsUsed = 0,
        itemSlotsTotal = 0,
        itemCount = 0,
        itemTotal = 0,

        reservedTurtleSlots = {}
    }

    gui.clearReserved = function()
        gui.reservedTurtleSlots = {}
    end

    gui.setReserved = function(slot, item, count)
        gui.reservedTurtleSlots[tostring(slot)] = { name = iris._getItemName(item), count = count }
    end

    gui.findPullable = function()
        local candidates = {}

        local wg = waitgroup.NewWaitGroup()

        for slotId = 1, iris.turtle.size(), 1 do
            wg.Add(function()
                local reservedSlot = gui.reservedTurtleSlots[tostring(slotId)]
                local item = turtle.getItemDetail(slotId, true)
                if item then
                    if reservedSlot == nil or iris._getItemName(item) ~= reservedSlot.name then
                        candidates[tostring(slotId)] = {
                            peripheral = iris.internalInventory,
                            name = item.name,
                            nbt = item.nbt,
                            count = item.count,
                            max = item.maxCount
                        }
                    elseif item.count > reservedSlot.count then
                        candidates[tostring(slotId)] = {
                            peripheral = iris.internalInventory,
                            name = item.name,
                            nbt = item.nbt,
                            count = reservedSlot.count - item.count,
                            max = item.maxCount
                        }
                    end
                else
                    -- The reserved item is no longer in that slot, unreserve it.
                    -- This is likely because someone has just taken it out!
                    if reservedSlot ~= nil then
                        gui.reservedTurtleSlots[tostring(slotId)] = nil
                    end
                end
            end)
        end

        wg.Wait()

        return candidates
    end

    gui.findSpace = function()
        for slotId = 1, iris.turtle.size(), 1 do
            if turtle.getItemCount(slotId) == 0 then
                return slotId
            end
        end

        return nil
    end

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
        text = (" %.0f%% - (%d/%d) [%d/%d] "):format(gui.itemPercentage, gui.itemSlotsUsed, gui.itemSlotsTotal,
            gui.itemCount, gui.itemTotal)
        if #text > w then
            text = (" %.0f%% - (%d/%d) "):format(gui.itemPercentage, gui.itemSlotsUsed, gui.itemSlotsTotal, gui.itemCount
                , gui.itemTotal)
            if #text > w then
                text = (" %.0f%% "):format(gui.itemPercentage, gui.itemSlotsUsed, gui.itemSlotsTotal, gui.itemCount,
                    gui.itemTotal)
            end
        end

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
        local paginationDisplay = ""

        if gui.pageCount > 1 then
            paginationDisplay = " " ..
                (" "):rep(#tostring(gui.pageCount) - #tostring(gui.pageNumber)) ..
                tostring(gui.pageNumber) .. "/" .. tostring(gui.pageCount) .. " "
        end

        term.setTextColour(irisColours.contrast.colour)
        term.setBackgroundColour(irisColours.background.colour)

        if gui.isSmallDisplay(w) then -- When enabled, the pagination and item count will be on seperate lines
            term.setCursorPos(math.floor((w - #paginationDisplay) / 2), h)
            term.write(paginationDisplay)

            gui.drawPercentage(1, h - 1, w)
        else
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
        for _, itemLocations in pairs(items) do
            if #itemLocations > 0 then
                local location = itemLocations[1]

                if gui.matchQuery(location, gui.searchQuery) then
                    local itemCount = 0
                    for _, itemLocation in pairs(itemLocations) do
                        itemCount = itemCount + itemLocation.count
                    end

                    if itemCount > 0 then
                        table.insert(results, {
                            count = itemCount,
                            name = location.name,
                            display = location.display,
                            nbt = location.nbt,
                            tags = location.tags,
                        })
                    end
                end
            end
        end

        table.sort(results, gui.sortFunction)

        iris.logger.Debug().Str("results", #results).Str("query", gui.searchQuery).Dur("duration", start).Msg("Queried items")

        return results
    end

    gui.pullTask = function()
        local start = os.epoch("utc")

        local w, h = term.getSize()
        gui.isBusy = true
        gui.drawBottomBar(w, h)

        local candidates = gui.findPullable()
        local transferred = 0
        local missingSpace = false

        for _, _ in pairs(candidates) do
            transferred, missingSpace = iris._transferItems(iris.internalInventory, candidates)
            if missingSpace then
                iris.logger.Warn().Err(errors.ErrIRISMissingSpace).Msg("Failed to push input into IRIS")
            end

            break
        end

        gui.isBusy = false
        gui.drawBottomBar(w, h)

        local err = iris.save()
        if err ~= nil then
            iris.logger.Warn().Err(err).Msg("Failed to save IRIS data")
        end

        if transferred > 0 then
            gui.changePagination(gui.pageNumber, false)
        end

        if gui.blinkTimer ~= nil then
            os.cancelTimer(gui.blinkTimer)
            gui.blinkTimer = os.startTimer(blinkSpeed)
        end

        iris.logger.Info().Dur("duration", start).Str("transferred", transferred).Msg("Completed pull task")

        -- Try again, we might have more items in the turtle.
        if transferred > 0 then
            gui.pullTask()
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

        gui.pullTask()

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
                gui.onClick(paramA, paramB, paramC)
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
            elseif type == "peripheral" then
                local _, peripheralType = peripheral.getType(paramA)
                if peripheralType == "inventory" then
                    local w, h = term.getSize()
                    gui.isBusy = true
                    gui.drawBottomBar(w, h)

                    iris.fullScan()

                    gui.isBusy = false
                    gui.drawBottomBar(w, h)
                end
            elseif type == "peripheral_detatch" then
                if iris.irisData.inventories[paramA] ~= nil then
                    local w, h = term.getSize()
                    gui.isBusy = true
                    gui.drawBottomBar(w, h)

                    iris.fullScan()

                    gui.isBusy = false
                    gui.drawBottomBar(w, h)
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

    gui.onClick = function(mouseButton, x, y)
        gui.isSearching = false

        if mouseButton == 1 then -- Left click
            if y == 2 then -- Clicking search
                gui.isSearching = true
                gui.blinkTimer = os.startTimer(blinkSpeed)
            elseif y >= startY and y <= startY + gui.pageLimit then
                local selectedResult = gui.displayedResults[y - startY + 1]
                if selectedResult == gui.selectedResult and selectedResult ~= nil then -- Double clicked result
                    -- Pull stack from IRIS
                    local emptySlot = gui.findSpace()
                    if emptySlot then
                        local w, h = term.getSize()
                        gui.isBusy = true
                        gui.drawBottomBar(w, h)

                        local start = os.epoch("utc")
                        local locations = iris.locate(selectedResult.name, selectedResult.nbt)
                        local max = 1

                        for _, k in pairs(locations) do
                            max = k.max
                            break
                        end

                        iris.logger.Info().Str("name", selectedResult.name).Str("nbt", selectedResult.nbt).Str("max", max)
                            .Msg("Requesting items from IRIS")

                        local totalTransferred, _ = iris.pullItemFromIRIS(selectedResult.name, selectedResult.nbt, max)

                        iris.logger.Info().Str("name", selectedResult.name).Str("nbt", selectedResult.nbt).Str("transferred"
                            , totalTransferred).Dur("duration", start).Msg("Requested items from IRIS")

                        gui.isBusy = false
                        gui.drawBottomBar(w, h)

                        gui.setReserved(emptySlot, selectedResult, totalTransferred)
                        gui.selectedResult = nil
                        if totalTransferred > 0 then
                            gui.changePagination(gui.pageNumber, false)
                        end
                    end
                else
                    gui.selectedResult = selectedResult

                    local w, h = term.getSize()
                    gui.drawResults(w, h)
                end
            end
        elseif mouseButton == 2 then -- Right click
            if y >= startY and y <= startY + gui.pageLimit then
                local selectedResult = gui.displayedResults[y - startY + 1]
                if selectedResult ~= nil then
                    gui.selectedResult = selectedResult
                    gui.popup()
                end
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
        query = query:lower()

        if query == "" then
            return true
        elseif query[1] == "$" then
            -- the $ allows for searching item tags
            if item.tags then
                query = query:sub(2, #query)
                for tagName, _ in pairs(item.tags) do
                    if gui.matchString(tagName, query) then
                        return true
                    end
                end
            end
        else
            return gui.matchString(item.name, query) or gui.matchString(item.display, query)
        end
    end

    gui.matchString = function(str, query)
        return str:lower():find(query) ~= nil
    end

    gui.sortFunction = function(a, b)
        -- return (a.count) > (b.count)
        return (a.display:lower()) < (b.display:lower())
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
