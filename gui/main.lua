-- Colours to use within IRIS gui
-- original colour to use, r, g, b

local colours = {
    main       =  { colour = colours.blue,   hex = 0x2F80ED },
    accent     =  { colour = colours.cyan,   hex = 0x2162BA },
    background =  { colour = colours.black,  hex = 0x000000 },
    contrast   =  { colour = colours.white,  hex = 0xFFFFFF },
    highStorage = { colour = colours.green,  hex = 0x5CB764 },
    lowStorage  = { colour = colours.orange, hex = 0xF19E37 },
    noStorage   = { colour = colours.red,    hex = 0xE85550 },
}

local function setupPalette()
    if term.setPaletteColour == nil then
        return
    end

    for _, colour in pairs(colours) do
        term.setPaletteColour(colour.colour, colour.hex)
    end
end

local function NewGUI(iris)
    local gui = {
        iris = iris,

        searchQuery = "",
        isSearching = "",

        pageNumber = 0,
        pageCount = 0,

        results = {},

        itemPercentage = 0,
        itemSlotsUsed = 0,
        itemSlotsTotal = 0,
        itemCount = 0,
        itemTotal = 0,
    }

    gui.drawBase = function()
        term.clear()
    
        local w, h = term.getSize()
    
        -- Draw header
        paintutils.drawBox(1, 1, w, 1, colours.main.colour)
        paintutils.drawBox(1, 2, w, 2, colours.accent.colour)

        -- Add label
        local label = "IRIS"
        term.setCursorPos(w-#label, 1)
        term.write(label)

        -- Add search
        term.setCursorPos(1, 2)
        term.write(gui.searchQuery)

        local paginationDisplay = " < " .. tostring(gui.pageNumber) .. "/" .. tostring(gui.pageCount) .. " > "

        local isSmallDisplay = w < 39 -- When enabled, the pagination and item count will be on seperate lines

        if isSmallDisplay then
            paintutils.drawBox(1, h-1, w, h-1, colours.main.colour)
            gui.drawPercentage(1, h-2, w)
        else
            paintutils.drawBox(w - #paginationDisplay, h-1, w, h-1, colours.main.colour)
            gui.drawPercentage(1, h-1, w - #paginationDisplay)
        end
    end
    
    gui.drawPercentage = function(x, y, w)
        term.setCursorPos(x, y)

        if gui.iris.isScanning and gui.itemSlotsTotal == 0 then
            term.write("Scanning...")
        elseif not gui.iris.isInitialized then
            term.write("Getting Ready...")
        end

        local text = (" %.0f%% - (%d/%d) [%d/%d] "):format(gui.itemPercentage, gui.itemSlotsUsed, gui.itemSlotsTotal, gui.itemCount, gui.itemTotal)
        if #text > w then
            text = (" %.0f%% - (%d/%d) "):format(gui.itemPercentage, gui.itemSlotsUsed, gui.itemSlotsTotal, gui.itemCount, gui.itemTotal)
            if #text > w then
                text = (" %.0f%% "):format(gui.itemPercentage, gui.itemSlotsUsed, gui.itemSlotsTotal, gui.itemCount, gui.itemTotal)
            end
        end

        text = text .. (" "):rep(w - #text) -- Add any missing padding

        local barCharCount = math.floor((gui.itemPercentage/100) * w)
        local barColour

        if (gui.itemSlotsTotal - gui.itemSlotsUsed) <= 3 then
            barColour = colours.noStorage
        elseif (gui.itemSlotsTotal - gui.itemSlotsUsed) <= (9*3) then
            barColour = colours.lowStorage
        else
            barColour = colours.highStorage
        end

        -- We use blit to draw the entire bar at once.
        -- We will apply the background like normal then apply white when on background
        -- and black when on the bar.
        term.blit(
            text,
            colours.toBlit(colours.background.colour):rep(barCharCount) ..
            colours.toBlit(colours.contrast.colour):rep(w - barCharCount),
            colours.toBlit(barColour):rep(barCharCount) ..
            colours.toBlit(colours.background.colour):rep(w - barCharCount)
        )
    end

    gui.splashScreen = function()
        -- Wait for init
        local sleepTimer = os.startTimer(1)
        while true do
            local timerId = os.pullEvent("timer")
            if timerId == sleepTimer then
                if gui.iris.isInitialized then
                    break
                end

                gui.drawBase()
            end
        end

        os.cancelTimer(sleepTimer)
    end

    gui._syncTask = function()
        local ok = gui.iris.fullScan()
        if not ok then
            return
        end

        local itemPercentage = 0
        local itemSlotsUsed = 0
        local itemSlotsTotal = 0
        local itemCount = 0
        local itemTotal = 0

        for _, chestData in pairs(iris.irisData.chests) do
            itemSlotsTotal = itemSlotsTotal + chestData.total
            itemSlotsUsed = itemSlotsUsed + #chestData.items
            for _, item in pairs(chestData.items) do
                itemTotal = itemTotal + item.max
                itemCount = itemCount + item.count
            end
        end

        gui.itemPercentage = itemPercentage
        gui.itemSlotsUsed = itemSlotsUsed
        gui.itemSlotsTotal = itemSlotsTotal
        gui.itemCount = itemCount
        gui.itemTotal = itemTotal

        gui.drawBase()

        coroutine.yield()
    end
    gui.syncTask = coroutine.create(gui._syncTask)


    gui.mainScreen = function()
        local syncTimer = os.startTimer(15)
        while true do
            local timerId = os.pullEvent("timer")
            if timerId == syncTimer then
                coroutine.resume(gui.syncTask)
            end
        end
    end

    gui.run = function ()
        setupPalette()

        gui.splashScreen()
        gui.mainScreen()
    end

    return gui
end

return {
    NewGUI = NewGUI
}