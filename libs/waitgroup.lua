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
        return coroutine.status(thread.coro) == "suspended" and (thread.event == nil or thread.event == name)
    end

    waitGroup._resume = function(thread, event)
        local success, result = coroutine.resume(thread.coro, table.unpack(event, 1, event.n))
        assert(success, result)
        return result
    end

    waitGroup.Wait = function()
        local e = {}

        while true do
            local total = #waitGroup.threads
            for t = 1, total do
                local thread = waitGroup.threads[t]
                if waitGroup._check(thread, e[1]) then
                    thread.event = waitGroup._resume(thread, e)
                end
                if coroutine.status(thread.coro) == "dead" then
                    for k = 1, #waitGroup.threads do
                        if waitGroup.threads[k] == thread then
                            table.remove(waitGroup.threads, k)
                            t = t - 1
                            break
                        end
                    end
                    if #waitGroup.threads == 0 then return end
                    total = #waitGroup.threads
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
