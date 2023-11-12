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