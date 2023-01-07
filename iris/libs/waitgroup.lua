local function NewWaitGroup()
    local this = {
        _type = "waitgroup:waitgroup",
        _defaultBurst = 20,

        threads = {}
    }

    this.Add = function(func)
        local thread = {
            coro = coroutine.create(func),
            ev = nil
        }

        table.insert(this.threads, thread)
    end

    this._check = function(thread, name)
        return coroutine.status(thread.coro) == "suspended" and (thread.event == nil or thread.event == name)
    end

    this._resume = function(thread, event)
        local success, result = coroutine.resume(thread.coro, table.unpack(event, 1, event.n))
        assert(success, result)
        return result
    end

    this.Wait = function(coroutineBurst)
        if coroutineBurst == nil then coroutineBurst = this._defaultBurst end

        assert(type(coroutineBurst) == "number")

        local e = {}

        while true do
            local total = #this.threads
            local t = 0
            while t < math.min(total, coroutineBurst) do
                t = t + 1
                local thread = this.threads[t]
                if this._check(thread, e[1]) then
                    thread.event = this._resume(thread, e)
                end
                if coroutine.status(thread.coro) == "dead" then
                    for k = 1, #this.threads do
                        if this.threads[k] == thread then
                            table.remove(this.threads, k)
                            t = t - 1
                            break
                        end
                    end
                    if #this.threads == 0 then return end
                    total = #this.threads
                end
            end
            e = table.pack(os.pullEvent())
        end
    end

    return this
end

return {
    NewWaitGroup = NewWaitGroup
}
