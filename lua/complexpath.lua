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

---Draw the last segment in the Path
---@param ctx Context2D Drawing context
---@param bounds Bounds Bounds of the canvas
function ComplexPath:drawLastSegment(ctx, bounds)
    self:drawSegment(ctx, bounds, #self.points - 1)
end

---Draw a specific segment of the path.
---@param ctx Context2D Drawing context
---@param bounds Bounds Bounds of the canvas
---@param idx integer Which segment to draw
function ComplexPath:drawSegment(ctx, bounds, idx)
    if idx < 1 or idx > #self.points then
        return
    end
    ctx.lineWidth = self.points[idx].thickness
    ctx.lineCap = "round"
    ctx.strokeStyle = self.color

    local segmentStart = self.points[idx].point
    local segmentEnd = self.points[idx+1].point
    ctx:beginPath()
    ctx:moveTo(bounds:complexToPixel(segmentStart))
    ctx:lineTo(bounds:complexToPixel(segmentEnd))
    ctx:stroke()
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
    for i = 1, #self.points - 1 do
        self:drawSegment(ctx, bounds, i)
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
