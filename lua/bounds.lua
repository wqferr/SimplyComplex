assert(_G.im, "imagine must be loaded before bounds")
local im = _G.im

---@class Bounds
---Represents a rectangular section of the complex plane
---@field private lowerLeft Complex lower left corner of the bounds
---@field private upperLeft Complex upper left corner of the bounds
---@field private upperRight Complex upper right corner of the bounds
---@field private lowerRight Complex lower right corner of the bounds
---@field private canvasWidth number canvas pixel width
---@field private canvasHeight number canvas pixel height
local Bounds = {}
local Bounds__meta = {__index = Bounds}

---Create a new Bounds object for the given 2 opposing points
---@param p1 Complex one of the bounds's corner, with smaller real and imaginary parts
---@param p2 Complex opposite bounds corner, with larger real and imaginary parts
---@param canvasWidth number width in pixels in the mapped canvas region
---@param canvasHeight number height in pixels in the mapped canvas region
function Bounds.new(p1, p2, canvasWidth, canvasHeight)
    local b = setmetatable({}, Bounds__meta)
    b.lowerLeft = p1
    b.upperRight = p2

    assert(p1 and p2 and canvasWidth and canvasHeight, "Not enough arguments: lowerLeft, upperRight, canvasWidth, canvasHeight")
    local sideLengths = b.upperRight - b.lowerLeft
    assert(sideLengths.real > 0 and sideLengths.imag > 0, "Invalid bounds corners: pass lower left first")

    b.upperLeft = b.upperRight - sideLengths.real
    b.lowerRight = b.lowerLeft + sideLengths.real

    assert(canvasWidth > 0 and canvasHeight > 0, "Invalid canvas dimensions")
    b.canvasWidth = canvasWidth
    b.canvasHeight = canvasHeight
    return b
end

---Finds t such that lerp(a, b, t) = x
---@param a number lerp low end
---@param b number lerp high end
---@param x number lerp result to be backfed
---@return number t the original lerp parameter
local function inverseLerp(a, b, x)
    return (x - a) / (b - a)
end

---Linear interpolation of complex numbers
---@param p1 number origin point
---@param p2 number destination point
---@param alpha number ratio parameter of the linear interpolation
---@param extrapolate boolean? whether to allow extrapolation (alpha < 0 or alpha > 1)
---@return number
local function lerp(p1, p2, alpha, extrapolate)
    assert(type(alpha) == "number", "Linear interpolation alpha must be a number")
    if alpha < 0 or alpha > 1 then
        if not extrapolate then
            alpha = math.min(math.max(0, alpha), 1)
        end
    end
    return p1 * (1 - alpha) + p2 * alpha
end

---Convert a point on the complex plane to its corresponding point on the canvas
---@param c Complex the point in the complex plane
---@return number x x coordinate of the corresponding canvas point
---@return number y y coordinate of the corresponding canvas point
function Bounds:complexToPixel(c)
    local x = inverseLerp(self.lowerLeft.real, self.lowerRight.real, c.real)
    local y = inverseLerp(self.lowerLeft.imag, self.upperLeft.imag, c.imag)
    x, y = x * self.canvasWidth, y * self.canvasHeight
    return x, y
end

---Convert a point on the canvas to its corresponding complex number
---@param px number x position in the canvas
---@param py number y position in the canvas
---@return Complex point the corresponding point
function Bounds:pixelToComplex(px, py)
    px, py = px / self.canvasWidth, py / self.canvasHeight
    local x = lerp(self.lowerLeft.real, self.lowerRight.real, px)
    local y = lerp(self.lowerLeft.imag, self.upperLeft.imag, py)
    return im(x, y)
end

return Bounds