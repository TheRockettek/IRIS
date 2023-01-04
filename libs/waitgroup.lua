--[[ Modified Raising to make a simple interface ]] --
--[[ Raisin by Hugeblank
    This code is my property, but I will let you use it so long as you don't redistribute this manager for
    monetary gain and leave this comment block untouched. Add/remove code as you wish. Should you decide to freely
    distribute with additional modifications, please credit yourself. :)

    Raisin can be found on github at:
    `https://github.com/hugeblank/raisin`

    Demonstrations of the library can also be found at:
    `https://github.com/hugeblank/raisin-demos`
]]
local function copy(t)
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            out[k] = copy(v)
        else
            out[k] = v
        end
    end
    return out
end

local function manager(listener)
    local this = {}

    local threads = {}

    local assert = function(condition, message, level)
        if not condition then
            level = level or 0
            error(message, 3 + level)
        end
    end

    assert(type(listener) == "function")

    local function sort(unsorted)
        local sorted = {}
        sorted[#sorted + 1] = unsorted[1]
        for i = 1, #unsorted do
            table.insert(sorted, unsorted[i])
        end

        return sorted
    end

    local function resume(thread, event)
        local suc, err = coroutine.resume(thread.coro, table.unpack(event, 1, event.n))
        assert(suc, err, 2)
        if suc then
            return err
        end
    end

    local function check(thread, name)
        return thread.enabled and coroutine.status(thread.coro) == "suspended" and
            (thread.event == nil or thread.event == name)
    end

    local interface = function(coro, filter)
        filter = filter or {}
        if type(filter) == "string" then
            filter = {
                [filter] = true
            }
        end
        assert(type(filter) == "table")
        if #filter == 0 then
            filter = nil
        else
            filter = copy(filter)
            for i = 1, #filter do
                filter[(filter[i])] = true
                filter[i] = nil
            end
        end
        local internal = {
            coro = coro,
            queue = {},
            filter = filter,
            enabled = true,
            event = nil
        }
        internal.instance = {
            state = function()
                return internal.enabled
            end,
            toggle = function(value)
                internal.enabled = value or not internal.enabled
            end,
            remove = function()
                for i = 1, #threads do
                    if threads[i] == internal then
                        table.remove(threads, i)
                        return true
                    end
                end
                return false
            end
        }
        threads[#threads + 1] = internal
        return internal.instance
    end

    this.run = function()
        local e = {}

        while true do
            local s_threads = sort(threads)
            local total = #s_threads
            for j = 1, total do
                local thread = s_threads[j]
                if not thread then break end

                while #thread.queue ~= 0 do
                    if check(thread, thread.queue[1][1]) then
                        thread.event = resume(thread, thread.queue[1])
                    end
                    table.remove(thread.queue, 1)
                end
                if check(thread, e[1]) then
                    thread.event = resume(thread, e)
                elseif not thread.enabled then
                    if thread.filter and thread.filter[(e[1])] then
                        thread.queue[#thread.queue + 1] = e
                    elseif not thread.filter then
                        thread.queue[#thread.queue + 1] = e
                    end
                end
                if coroutine.status(thread.coro) == "dead" then
                    for k = 1, #threads do
                        if threads[k] == thread then
                            table.remove(threads, k)
                            j = j - 1
                        end
                    end
                    if #threads == 0 then
                        return
                    end
                end
                total = #s_threads
            end
            e = table.pack(listener())
        end
    end

    this.thread = function(func, ...)
        assert(type(func) == "function")
        return interface(coroutine.create(func), ...)
    end

    this.group = function(...)
        local subman = manager(listener)
        local ii = interface(...)
        ii.run = subman.run
        ii.thread = subman.thread
        ii.group = subman.group
        return ii
    end

    return this
end

local function NewWaitGroup()
    local raisin = manager(os.pullEvent)
    local waitGroup = {
        group = raisin.group()
    }

    waitGroup.Add = function(func)
        waitGroup.group.thread(func)
    end

    waitGroup.Wait = function()
        raisin.run()
    end

    return waitGroup
end

return {
    NewWaitGroup = NewWaitGroup
}
