return function(im, sd)
    sd.setNumericChecks({
        isNumeric = function(x)
            return type(x) == "number" or im.isComplex(x)
        end,
        isZero = function(x)
            return x == 0 or x == im.zero
        end,
        isOne = function(x)
            return x == 1 or x == im.one
        end
    })
end