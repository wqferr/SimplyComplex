local sd = _G.sd
local im = _G.im

local one = sd.const(im.one)
local constOne = sd.func(function() return one end)
sd.real = sd.func(function(z) return im(z.real, 0) end, true, "real")
sd.real:setDerivative(constOne)
sd.imag = sd.func(function(z) return im(z.imag, 0) end, true, "imag")
sd.imag:setDerivative(constOne)

sd.abs = sd.func(function(z) return im(z--[[@as Complex]]:abs(), 0) end, true, "abs")
local sign = sd.func(function(z) return z / sd.abs(z) end)
sd.abs:setDerivative(sign)

sd.arg = sd.func(function(z) return im(z--[[@as Complex]]:arg(), 0) end, true, "arg")
sd.arg:setDerivative(sd.abs)

sd.conj = sd.func(function(z) return z--[[@as Complex]]:conj() end, true, "conj")
-- this is technically incorrect and no such derivative exists BUT we need to
-- set it to something so it knows with which thickness to draw lines
sd.conj:setDerivative(constOne)
