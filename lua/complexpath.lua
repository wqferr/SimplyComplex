---@class PathPointInfo
---@field package point Complex the point the path passes through
---@field package thickness number the thickness of the line at that point

---@class ComplexPath
---@field private points PathPointInfo[] the points composing this path
---@field private defaultThickness number the default thickness for the path
---@field public color string the color to draw this path with
local ComplexPath = {}
local ComplexPath__meta = {__index = ComplexPath}

function ComplexPath.new(color, defaultThickness)
    local p = setmetatable({}, ComplexPath__meta)
    p.points = {}
    p.color = color
    p.defaultThickness = defaultThickness
    return p
end

---Add a new point to the path
---@param c Complex the point to add
---@param thickness number? the relative line thickness at that point
function ComplexPath:pushPoint(c, thickness)
    table.insert(self.points, {point = c, thickness = thickness or self.defaultThickness})
end

---Get the starting point of this Path
---@return Complex start the start point
function ComplexPath:startPoint()
    return self.points[1].point
end

---Get the ending point of this Path
---@return Complex end the end point
function ComplexPath:endPoint()
    return self.points[#self.points].point
end

function ComplexPath:penultimatePoint()
    if not self.points[2] then
        return nil
    end
    return self.points[#self.points-1].point
end

function ComplexPath:endThickness()
    if self.points[1] then
        return self.points[#self.points].thickness
    else
        return nil
    end
end

---Set the color of this Path
---@param color string new color for the Path
function ComplexPath:setColor(color)
    self.color = color
end

function ComplexPath:draw(ctx, bounds)
    if not self.points[1] then
        return
    end
    ctx.strokeStyle = self.color
    ctx.lineCap = "round"
    for i = 2, #self.points do
        ctx:beginPath()
        ctx:moveTo(bounds:complexToPixel(self.points[i-1].point))
        ctx.lineWidth = self.points[i-1].thickness
        ctx:lineTo(bounds:complexToPixel(self.points[i].point))
        ctx:stroke()
    end
end

function ComplexPath:transform(expr)
    local p = ComplexPath.new(self.color)
    for _, pointInfo in ipairs(self.points) do
        local point = pointInfo.point
        local originalThickness = self:endThickness() * OUTPUT_AREA / INPUT_AREA
        p:pushPoint(expr:evaluate(point), expr:derivative(point):abs() * originalThickness)
    end
    return p
end

return ComplexPath