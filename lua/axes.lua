---@module "axes"
local M = {}

---@class Axes
---@field package ctx any
---@field package bounds Bounds
local Axes = {}
local AxesMt = {__index = Axes}

local TICK_WIDTH = 5.5

setmetatable(M, {
    __call = function(_, bounds, ctx)
        local axes = setmetatable({}, AxesMt)
        axes.bounds = bounds
        axes.ctx = ctx
        return axes
    end,
})


local function centerPixels(x, y)
    return math.floor(x) - 0.5, math.floor(y) - 0.5
    -- return x, y
end

local axesIterTable = {
    -- dx/dy given in pixel coords
    { direction = 1, dy = {-2.5, 0} },
    { direction = im.i, dx = {-2.5, 0} },
    { direction = -1, dy = {1.5, -1} },
    { direction = -im.i, dx = {1.5, -1} },
}
function Axes:draw()
    local x0, y0 = centerPixels(self.bounds:complexToPixel(im(0, 0)))
    local lrX, lrY = centerPixels(self.bounds:complexToPixel(self.bounds.lowerRight))

    self.ctx:beginPath()
    self.ctx.strokeStyle = "#333333"
    self.ctx.lineWidth = 1

    -- x direction
    self.ctx:moveTo(0, y0)
    self.ctx:lineTo(lrX, y0)

    -- y direction
    self.ctx:moveTo(x0, 0)
    self.ctx:lineTo(x0, lrY)
    self.ctx:stroke()

    local delta = 1

    -- displacement up and down from the axes (half the total length)
    local tickSize = self.bounds:pixelsToMeasurement(TICK_WIDTH)
    self.ctx:beginPath()
    for _, iterParams in ipairs(axesIterTable) do
        local direction = iterParams.direction
        local currentTick = im.zero
        while self.bounds:contains(currentTick) do
            currentTick = currentTick + delta * direction
            local perpendicular = direction * im.i
            local tickStart = currentTick + perpendicular * tickSize
            local tickEnd = currentTick - perpendicular * tickSize

            tickEnd = tickEnd - self.bounds:pixelsToMeasurement(1) * perpendicular
            local tickStartX, tickStartY = self.bounds:complexToPixel(tickStart)
            local tickEndX,   tickEndY   = self.bounds:complexToPixel(tickEnd)
            local dx, dy = iterParams.dx, iterParams.dy
            if dx then
                tickStartX, tickEndX = tickStartX + dx[1], tickEndX + dx[2]
                tickStartY, tickEndY = centerPixels(tickStartY, tickEndY)
            elseif dy then
                tickStartY, tickEndY = tickStartY + dy[1], tickEndY + dy[2]
                tickStartX, tickEndX = centerPixels(tickStartX, tickEndX)
            end
            if tickStartX < 0 or tickStartY < 0 then
                tickStartX, tickStartY = tickStartX + 1, tickStartY + 1
                tickEndX, tickEndY = tickEndX + 1, tickEndY + 1
            end
            self.ctx:moveTo(tickStartX, tickStartY)
            self.ctx:lineTo(tickEndX, tickEndY)
        end
    end
    self.ctx:stroke()
end



return M
