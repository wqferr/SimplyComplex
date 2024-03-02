local function thread(f)
    local co = coroutine.create(f)
    local timeoutId
    local function continue(...)
        local rets = { coroutine.resume(co, ...) }
        timeoutId = js.global:setTimeout(continue, 0)
        return table.unpack(rets)
    end
    local function pause()
        js.global:clearTimeout(timeoutId)
    end
    return continue, pause
end

return thread
