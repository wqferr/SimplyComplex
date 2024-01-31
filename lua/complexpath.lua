---@class PathPointInfo
---@field package point Complex the point the path passes through
---@field package thickness number the thickness of the line at that point

---@class ComplexPath
---@field private points PathPointInfo[] the points composing this path
---@field private defaultThickness number the default thickness for the path
---@field private interpSegments number of segments to insert for every pushPoint operation
---@field public color string the color to draw this path with
local ComplexPath = {}
local ComplexPath__meta = {__index = ComplexPath}

---Create a new Complex Path
---@param color string strokeStyle for drawing with a Context2D
---@param defaultThickness number thickness of segments which dont specify one
---@param interpSegments integer? number of segments to insert to split each pushPoint operation; defaults to 1
---@return ComplexPath
function ComplexPath.new(color, defaultThickness, interpSegments)
    local p = setmetatable({}, ComplexPath__meta)
    p.points = {}
    p.color = color
    p.defaultThickness = defaultThickness
    p.interpSegments = interpSegments or 1
    return p
end

local function pushSinlgePoint(path, c, thickness)
    table.insert(path.points, {point = c, thickness = thickness or path.defaultThickness})
end

---Add a new point to the path, or multiple if interpSegments was given to the constructor
---@param c Complex the point to add
---@param thickness number? the relative line thickness at that point
function ComplexPath:pushPoint(c, thickness)
    if #self.points == 0 then
        pushSinlgePoint(self, c, thickness)
        return
    end
    local lerpStart = self:endPoint()
    local lerpEnd = c
    for segment = 1, self.interpSegments do
        local lerpT = segment / self.interpSegments
        local lerpedPoint = (1-lerpT) * lerpStart + lerpT * lerpEnd
        pushSinlgePoint(self, lerpedPoint, thickness)
    end
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
function ComplexPath:drawLastAddedSegments(ctx, bounds)
    for i = self.interpSegments, 1, -1 do
        self:drawSegment(ctx, bounds, #self.points - i)
    end
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
    local p = ComplexPath.new(self.color, self.defaultThickness)
    for _, pointInfo in ipairs(self.points) do
        local point = pointInfo.point
        local originalThickness = self:endThickness() * OUTPUT_AREA / INPUT_AREA
        p:pushPoint(expr:evaluate(point), expr:derivative(point):abs() * originalThickness)
    end
    return p
end

return ComplexPath
