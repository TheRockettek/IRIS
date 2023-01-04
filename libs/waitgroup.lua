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

local function NewWaitGroup()
    local waitGroup = {
        threads = {}
    }

    waitGroup.Add = function(func)
        local thread = {
            coro = coroutine.create(func)
        }
        table.insert(waitGroup.threads, thread)
    end

    waitGroup.Wait = function()
        while true do
            local threads = waitGroup.threads
            for t = 1, #threads do
                local status = coroutine.status(threads[t].coro)
                if status == "suspended" then
                    print(coroutine.resume(threads[t].coro))
                elseif status == "dead" then
                    table.remove(threads, t)
                    if #threads <= 1 then
                        return
                    end
                end
            end
            sleep(0)
        end
    end

    return waitGroup
end

return {
    NewWaitGroup = NewWaitGroup
}
