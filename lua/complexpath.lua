---@class PathPointInfo
---@field package point Complex the point the path passes through
---@field package thickness number the thickness of the line at that point

---@class ComplexPath
---@field private points PathPointInfo[] the points composing this path
---@field private maxThickness number the maximum allowed thickness for the path
---@field private discontinuities {number: boolean} points at which the path is discontinuous
---@field public color string the color to draw this path with
---@field public defaultThickness number the default thickness for the path
local ComplexPath = {}
local ComplexPath__meta = {__index = ComplexPath}

---Create a new Complex Path
---@param color string strokeStyle for drawing with a Context2D
---@param defaultThickness number thickness of segments which dont specify one
---@param maxThickness number? maximum allowed value for thickness
---@return ComplexPath
function ComplexPath.new(color, defaultThickness, maxThickness)
    local p = setmetatable({}, ComplexPath__meta)
    p.points = {}
    p.color = color
    p.defaultThickness = defaultThickness
    p.discontinuities = {}
    p.maxThickness = maxThickness or math.huge
    return p
end

-- local function pushSinglePoint(path, c, thickness)
--     table.insert(path.points, {point = c, thickness = thickness or path.defaultThickness})
-- end

---Add a new point to the path, or multiple if interpSegments was given to the constructor
---@param c Complex the point to add
---@param thickness number? the relative line thickness at that point
---@param discont boolean? if this is a discontinuity
function ComplexPath:pushPoint(c, thickness, discont)
    thickness = thickness or self.defaultThickness
    if thickness and thickness > self.maxThickness then
        thickness = self.maxThickness
    end
    table.insert(self.points, {point = c, thickness = thickness})
    if discont then
        self:setDiscontinuityAtEndPoint()
    end
end

---Mark the current end point as a discontinuity
function ComplexPath:setDiscontinuityAtEndPoint()
    self.discontinuities[#self.points] = true
end

---Iterate through all but the first and last of the path's points
---@return function iter the iterator
function ComplexPath:nonEndPoints()
    local i = 1
    return function()
        i = i + 1
        return self.points[i+1] and self.points[i]
    end
end

---Iterate through all but the first of the path's points
---@return function iter the iterator
function ComplexPath:tail()
    local i = 1
    return function()
        i = i + 1
        return self.points[i] and self.points[i].point
    end
end

---Replace last point with new values
---@param c any
---@param thickness any
function ComplexPath:updateLastPoint(c, thickness)
    if #self.points == 0 then
        error("Cannot update last point that doesn't exist", 2)
    end
    local p = self.points[#self.points]
    p.point = c
    p.thickness = math.min(thickness or p.thickness or self.defaultThickness, self.maxThickness)
end

---Get the starting point of this Path
---@return Complex start the start point
function ComplexPath:startPoint()
    return self.points[1].point
end

---Get the ending point of this Path
---@return Complex end the end point
function ComplexPath:endPoint()
    if #self.points == 0 then
        error("No points exist in this path", 2)
    end
    return self.points[#self.points].point
end

---Check whether this path has any points
---@return boolean
function ComplexPath:hasPoints()
    return #self.points > 0
end

local function drawSegment(ctx, bounds, segmentStart, segmentEnd, thickness, color)
    if bounds:contains(segmentStart) or bounds:contains(segmentEnd) then
        ctx.lineWidth = thickness
        ctx.lineCap = "round"
        ctx.strokeStyle = color

        ctx:beginPath()
        ctx:moveTo(bounds:complexToPixel(segmentStart))
        ctx:lineTo(bounds:complexToPixel(segmentEnd))
        ctx:stroke()
    end
end

---Draw a specific segment of the path.
---@param ctx Context2D Drawing context
---@param bounds Bounds Bounds of the canvas
---@param idx integer Which segment to draw
function ComplexPath:drawSegment(ctx, bounds, idx)
    if idx < 1 or idx >= #self.points or self.discontinuities[idx+1] then
        return
    end
    drawSegment(ctx, bounds, self.points[idx].point, self.points[idx+1].point, self.points[idx].thickness)
end

function ComplexPath:endThickness()
    if self.points[1] then
        return self.points[#self.points].thickness or self.defaultThickness
    else
        return nil
    end
end

---Set the color of this Path
---@param color string new color for the Path
function ComplexPath:setColor(color)
    self.color = color
end

function ComplexPath:drawUpToLastSegment(ctx, bounds)
    for i = 1, #self.points - 2 do
        self:drawSegment(ctx, bounds, i)
    end
end

---Draw the last segment in the Path
---@param ctx Context2D Drawing context
---@param bounds Bounds Bounds of the canvas
function ComplexPath:drawLastSegment(ctx, bounds)
    self:drawSegment(ctx, bounds, #self.points - 1)
end

function ComplexPath:drawVirtualSegment(ctx, bounds, newEndPoint)
    if not self.points[1] then
        return
    end
    local currentEndPoint = self.points[#self.points]
    drawSegment(ctx, bounds, currentEndPoint.point, newEndPoint, currentEndPoint.thickness, self.color)
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
