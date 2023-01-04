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
            local total = #waitGroup.threads
            for t = 1, total do
                local thread = waitGroup.threads[t]
                if not thread then break end
                if waitGroup._check(thread, e[1]) then
                    thread.ev = waitGroup._resume(thread, e)
                end
                if coroutine.status(thread.coro) == "dead" then
                    table.remove(waitGroup.threads, t)
                    total = #waitGroup.threads
                    t = t - 1
                    if total == 0 then
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
