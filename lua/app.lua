---@module "app"

local js = require "js"

local Axes = require "axes"
local CPath = require "complexpath"
require "constants"

---@class App
---@field package func Expression
---@field package inputBounds Bounds
---@field package outputBounds Bounds
---@field package needsRedraw boolean
---@field package userDrawing boolean
---@field package userLocked boolean
---@field package cursorTrackingEnabled boolean
---@field package inputCtx any
---@field package outputCtx any
---@field package inputPrecomputedCtx any
---@field package outputPrecomputedCtx any
---@field package inputSquiggles ComplexPath[]
---@field package outputSquiggles ComplexPath[]
---@field package inputAxes Axes
---@field package outputAxes Axes
---@field package cursorMovePointPushThreshold number
---@field package maxTolerableDistanceForInterp number
---@field package lineWidthScalingFactor number
---@field package lastCursorPosition Complex
local App = {}
local AppMt = {__index = App}

local function copyCanvasDimensions(from, to)
    to.width, to.height = from.width, from.height
end

---@return App
function App.new(args)
    local app = {}
    setmetatable(app, AppMt)
    if not args.inputCanvas then
        error("Input canvas expected", 2)
    end
    if not args.outputCanvas then
        error("Output canvas expected", 2)
    end
    if args.func then
        app:setFunc(args.func)
    end
    app.inputCtx, app.outputCtx = args.inputCanvas:getContext "2d", args.outputCanvas:getContext "2d"
    app.inputPrecomputedCtx, app.outputPrecomputedCtx = js.global.document:createElement "canvas":getContext "2d", js.global.document:createElement "canvas":getContext "2d"
    copyCanvasDimensions(app.inputCtx.canvas, app.inputPrecomputedCtx.canvas)
    copyCanvasDimensions(app.outputCtx.canvas, app.outputPrecomputedCtx.canvas)

    if args.inputBounds then
        app:setInputBounds(args.inputBounds)
    end
    if args.outputBounds then
        app:setOutputBounds(args.outputBounds)
    end

    -- do i need this?
    -- app:setInputResolution(tonumber(app.inputCanvas.width), tonumber(app.inputCanvas.height))
    -- app:setOutputResolution(tonumber(app.outputCanvas.width), tonumber(app.outputCanvas.height))
    app.needsRedraw = false
    app.userDrawing = false
    app.userLocked = false
    app.cursorTrackingEnabled = false
    app.inputSquiggles, app.outputSquiggles = {}, {}
    return app
end

---@param app App
---@param point Complex
---@return Complex
---@return number
---@return number
local function calculateFunc(app, point, inputThickness)
    local fc = app.func:evaluate(point) --[[@as Complex]]
    local dz = app.func:derivative():evaluate(point)--[[@as Complex]]:abs()
    local thickness = inputThickness * app.lineWidthScalingFactor * dz
    return fc, dz, thickness
end

local function renderAxes(app)
    app.inputAxes:draw()
    app.outputAxes:draw()
end

local function renderOutputCursor(app)
    if not app.cursorTrackingEnabled or tostring(app.lastCursorPosition) == "nan" then
        return
    end
    local x, y = app.outputBounds:complexToPixel(app.lastCursorPosition)
    x, y = 0.5 + math.floor(x), 0.5 + math.floor(y)
    app.outputCtx.strokeStyle = "#333"
    app.outputCtx.lineWidth = 1

    local armLength = (OUTPUT_HOVER_POINT_CROSS_SIZE - 1) / 2
    app.outputCtx:moveTo(x - armLength, y)
    app.outputCtx:lineTo(x + armLength, y)
    app.outputCtx:moveTo(x, y - armLength)
    app.outputCtx:lineTo(x, y + armLength)
    app.outputCtx:stroke()
end

local function clearCtx(ctx)
    ctx:clearRect(0, 0, ctx.canvas.width, ctx.canvas.height)
end

local function renderOldPathsToPrecomputedCanvas(ctx, squiggles, bounds)
    clearCtx(ctx)
    for _, squiggle in ipairs(squiggles) do
        squiggle:drawUpToLastSegment(ctx, bounds)
        squiggle:drawLastSegment(ctx, bounds)
    end
end

local function renderOldPathsToPrecomputedCanvases(app)
    renderOldPathsToPrecomputedCanvas(app.inputPrecomputedCtx, app.inputSquiggles, app.inputBounds, app:isUserDrawing())
    renderOldPathsToPrecomputedCanvas(app.outputPrecomputedCtx, app.outputSquiggles, app.outputBounds, app:isUserDrawing())
end

local function renderPrecomputedCanvasesToRealThings(app)
    app.inputCtx:drawImage(app.inputPrecomputedCtx.canvas, 0, 0)
    app.outputCtx:drawImage(app.outputPrecomputedCtx.canvas, 0, 0)
end

local function render(app, recalcOldPaths)
    if not app.needsRedraw then
        return
    end
    clearCtx(app.inputCtx)
    clearCtx(app.outputCtx)
    renderAxes(app)
    if recalcOldPaths then
        renderOldPathsToPrecomputedCanvases(app)
    end
    renderPrecomputedCanvasesToRealThings(app)
    if app:isUserDrawing() then
        app:currentInputSquiggle():drawVirtualSegment(app.inputCtx, app.inputBounds, app.lastCursorPosition)

        local fLastCursorPosition = calculateFunc(app, app.lastCursorPosition, app:currentInputSquiggle():endThickness())
        app:currentOutputSquiggle():drawVirtualSegment(app.outputCtx, app.outputBounds, fLastCursorPosition)
    else
        renderOutputCursor(app)
    end
    app.needsRedraw = false
end

function App:render()
    render(self, false)
end

local function pixelDist(x1, y1, x2, y2)
    return math.sqrt((x1 - x2)^2 + (y1 - y2)^2)
end

---Pushes a single point onto the end of the input and output paths
---@param app App
---@param inputPoint Complex
---@param outputPoint Complex?
---@param outputThickness number?
---@param discontinuity boolean?
local function pushPointSimple(app, inputPoint, outputPoint, outputThickness, discontinuity)
    app:currentInputSquiggle():pushPoint(inputPoint)
    app:currentInputSquiggle():drawLastSegment(app.inputPrecomputedCtx, app.inputBounds)

    if not outputPoint or not outputThickness then
        outputPoint, _, outputThickness = calculateFunc(app, inputPoint, app:currentInputSquiggle():endThickness())
    end
    app:currentOutputSquiggle():pushPoint(outputPoint, outputThickness, discontinuity)
    app:currentOutputSquiggle():drawLastSegment(app.outputPrecomputedCtx, app.outputBounds)
end

---Pushes as many points as necessary to make path smooth; detects discontinuities
---@param app App
---@param args table
local function recursivelyPushPointsIfNeeded(app, args)
    local targetInputPoint = args.targetInputPoint or args[1]
    local targetOutputPoint, endThickness, derivative = args.targetOutputPoint, args.endThickness, args.derivative
    local depth = args.depth or 1
    if not targetOutputPoint or not endThickness or not derivative then
        targetOutputPoint, endThickness, derivative = calculateFunc(app, targetInputPoint, app:currentInputSquiggle():endThickness())
    end
    if not app:currentOutputSquiggle():hasPoints() then
        pushPointSimple(app, targetInputPoint, targetOutputPoint, endThickness, false)
    end

    local dist = (targetOutputPoint - app:currentOutputSquiggle():endPoint()):abs()
    local interpStart = app:currentInputSquiggle():endPoint()
    local interpEnd = targetInputPoint
    if dist <= app.maxTolerableDistanceForInterp then
        pushPointSimple(app, targetInputPoint, targetOutputPoint, endThickness, false)
    elseif depth < MAX_INTERP_TRIES then
        for i = 1, INTERP_STEPS do
            local interpT = i / INTERP_STEPS
            local interpPoint = (1-interpT) * interpStart + interpT * interpEnd
            local interpF, interpThickness, interpDeriv = calculateFunc(app, interpPoint, app:currentInputSquiggle():endThickness())
            recursivelyPushPointsIfNeeded(
                app,
                {
                    interpPoint,
                    depth = depth + 1,
                    targetOutputPoint = interpF,
                    endThickness = interpThickness,
                    derivative = interpDeriv,
                }
            )
        end
    else
        local inputDist = (targetInputPoint - app:currentInputSquiggle():endPoint()):abs()
        pushPointSimple(app, targetInputPoint, targetOutputPoint, endThickness, dist > 2 * derivative * inputDist)
    end
end

---Create new Path (for internal use only)
---@param app App
---@param color string
---@param penSize number
---@param start Complex
local function startPath(app, color, penSize, start)
    table.insert(app.inputSquiggles, CPath.new(color, penSize))
    table.insert(app.outputSquiggles, CPath.new(color, penSize, MAX_PATH_THICKNESS))
    pushPointSimple(app, start)
end

function App:clear()
    clearCtx(self.inputPrecomputedCtx)
    clearCtx(self.outputPrecomputedCtx)
    clearCtx(self.inputCtx)
    clearCtx(self.outputCtx)
    self.inputSquiggles, self.outputSquiggles = {}, {}
    self:scheduleRedraw()
    render(self, true)
end

function App:removeLastSquiggle()
    table.remove(self.inputSquiggles)
    table.remove(self.outputSquiggles)
    self:scheduleRedraw()
    render(self, true)
end

function App:startDrawing(color, penSize, canvasX, canvasY)
    if self:isUserInputLocked() then
        return
    end
    self.userDrawing = true
    local startPoint = self.inputBounds:pixelToComplex(canvasX, canvasY)
    startPath(self, color, penSize, startPoint)
    -- push a new point so it becomes visible immediately and so we can manipulate the endpoint
    -- pushPointSimple(self, startPoint)
end

function App:finishDrawing()
    if not self:isUserDrawing() or self:isUserInputLocked() then
        return
    end

    -- ensure cursor position gets commited to the actual path, not just as a virtual point
    recursivelyPushPointsIfNeeded(self, { self.lastCursorPosition })

    local startX, startY = self.inputBounds:complexToPixel(self:currentInputSquiggle():startPoint())
    local endX, endY = self.inputBounds:complexToPixel(self:currentInputSquiggle():endPoint())
    local dist = pixelDist(startX, startY, endX, endY)
    if dist <= CLOSE_PATH_DIST then
        pushPointSimple(self, self:currentInputSquiggle():startPoint())
    end
    self.userDrawing = false
end

function App:isUserDrawing()
    return self.userDrawing
end

function App:isUserInputLocked()
    return self.userLocked
end

function App:currentInputSquiggle()
    if self:isUserDrawing() then
        return self.inputSquiggles[#self.inputSquiggles]
    else
        return nil
    end
end

function App:currentOutputSquiggle()
    if self:isUserDrawing() then
        return self.outputSquiggles[#self.outputSquiggles]
    else
        return nil
    end
end

function App:setFunc(sdExpression)
  if sdExpression == self.func then
        return
    end
    self.func = sdExpression
    self:fullyRecalculate()
end

-- use with care
function App:fullyRecalculate()
    if not self.inputSquiggles[1] then
        return
    end
    -- TODO: spawn in thread
    error("TODO", 2)
end

---@param app App
local function updateLineWidthScalingFactor(app)
    if not app.inputBounds or not app.outputBounds then
        return
    end
    app.lineWidthScalingFactor = math.sqrt(app.outputBounds:area() / app.inputBounds:area())
end

function App:setInputBounds(bounds)
    if self.inputBounds then
        error("Changing bounds is not implemented yet", 2)
    end
    self.inputBounds = bounds
    self.inputAxes = Axes(self.inputBounds, self.inputCtx)
    updateLineWidthScalingFactor(self)

    self.cursorMovePointPushThreshold = self.inputBounds:pixelsToMeasurement(MAX_PIXEL_DISTANCE_BEFORE_PUSH_POINT)
end

function App:setOutputBounds(bounds)
    if self.outputBounds then
        error("Changing bounds is not implemented yet", 2)
    end
    self.outputBounds = bounds
    self.outputAxes = Axes(self.outputBounds, self.outputCtx)
    updateLineWidthScalingFactor(self)

    self.maxTolerableDistanceForInterp = self.outputBounds:pixelsToMeasurement(MAX_PIXEL_DISTANCE_BEFORE_INTERP)
end

function App:setLineWidth(newValue)
    self.lineWidth = newValue
end

function App:scheduleRedraw()
    self.needsRedraw = true
end

function App:updateCursorPosition(canvasX, canvasY)
    self.lastCursorPosition = self.inputBounds:pixelToComplex(canvasX, canvasY)
    if self:isUserDrawing() and (self.lastCursorPosition - self:currentInputSquiggle():endPoint()):abs() > self.cursorMovePointPushThreshold then
        recursivelyPushPointsIfNeeded(self, { self.lastCursorPosition })
    end
    self:scheduleRedraw()
end

function App:setCursorTrackingEnabled(enabled)
    self.cursorTrackingEnabled = enabled
end

return App
