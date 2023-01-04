local function NewWaitGroup()
    local waitGroup = {
        threads = {}
    }

    waitGroup.Add = function(func)
        local thread = {
            coro = coroutine.create(func),
            ev = nil
        }

        table.insert(waitGroup.threads, thread)
    end

    waitGroup._check = function(thread, name)
        return coroutine.status(thread.coro) == "suspended" and (thread.ev == nil or thread.ev == name)
    end

    waitGroup._resume = function(thread, event)
        local success, result = coroutine.resume(thread.coro, table.unpack(event, 1, event.n))
        assert(success, result)
        return result
    end

    waitGroup.Wait = function()
        local e = {}

        while true do
            local threads = waitGroup.threads
            for t = 1, #threads do
                local thread = threads[t]
                if thread == nil then break end

                if waitGroup._check(thread, e[1]) then
                    thread.ev = waitGroup._resume(thread, e)
                end
                if coroutine.status(thread.coro) == "dead" then
                    table.remove(threads, t)
                    if #threads == 0 then
                        return
                    end
                end
            end
            e = table.pack(os.pullEvent())
        end
    end

    return waitGroup
end

return {
    NewWaitGroup = NewWaitGroup
}
