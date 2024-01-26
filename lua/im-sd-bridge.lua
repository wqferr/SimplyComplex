local sd = _G.sd
local im = _G.im
sd.setNumericChecks {
    isNumeric = function(x)
        return type(x) == "number" or im.isComplex(x)
    end,
    isZero = function(x)
        return x == 0 or x == im.zero
    end,
    isOne = function(x)
        return x == 1 or x == im.one
    end
}

sd.exp.func = im.exp
sd.ln.func = im.log
sd.sqrt.func = im.sqrt

local constOne = sd.func(function() return sd.const(im.one) end)
sd.real = sd.func(function(z) return im(z.real, 0) end, true, "real")
sd.real:setDerivative(constOne)
sd.imag = sd.func(function(z) return im(z.imag, 0) end, true, "imag")
sd.imag:setDerivative(constOne)

sd.abs = sd.func(function(z) return im(z:abs(), 0) end, true, "abs")
local sign = sd.func(function(z) return z / sd.abs(z) end)
sd.abs:setDerivative(sign)

sd.arg = sd.func(function(z) return im(z:arg(), 0) end, true, "arg")
sd.arg:setDerivative(sd.abs)

sd.conj = sd.func(function(z) return z:conj() end, true, "conj")
-- this is technically incorrect and no such derivative exists BUT we need to
-- set it to something so it knows with which thickness to draw lines
sd.conj:setDerivative(constOne)
