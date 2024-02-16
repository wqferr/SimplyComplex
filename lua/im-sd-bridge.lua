local sd = _G.sd
local im = _G.im
-- sd.setNumericChecks {
--     isNumeric = function(x)
--         return type(x) == "number" or im.isComplex(x)
--     end,
--     isZero = function(x)
--         return x == 0 or x == im.zero
--     end,
--     isOne = function(x)
--         return x == 1 or x == im.one
--     end
-- }

local replacedFuncs = {
    "exp",
    ["ln"] = "log",
    "sqrt",
    "sin",
    "cos",
    "tan",
    "sinh",
    "cosh",
    "tanh",
}
for k, v in pairs(replacedFuncs) do
    if type(k) == "number" then
        sd[v].func = im[v]
    else
        sd[k].func = im[v]
    end
end

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
