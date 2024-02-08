package.path = "lua/?.lua;lua/?/?.lua;lua/?/init.lua;" .. package.path

local js = require "js"
_G.im = require "imagine"
_G.sd = require "symdiff"
local im = _G.im
local sd = _G.sd
local CPath = require "complexpath"
local Bounds = require "bounds"
local Axes = require "axes"
require "constants"
require "im-sd-bridge"


local inputCanvas = js.global.document:getElementById "inputBoard"
local outputCanvas = js.global.document:getElementById "outputBoard"
local precomputedInputCanvas = js.global.document:createElement "canvas"
local precomputedOutputCanvas = js.global.document:createElement "canvas"
local toolbar = js.global.document:getElementById "toolbar"

local inputCtx = inputCanvas:getContext "2d"
local outputCtx = outputCanvas:getContext "2d"
local precomputedInputCtx = precomputedInputCanvas:getContext "2d"
local precomputedOutputCtx = precomputedOutputCanvas:getContext "2d"

local function setCanvasSizes(canvas)
    canvas.width = CANVAS_SIDE_LEN
    canvas.height = CANVAS_SIDE_LEN
end
setCanvasSizes(inputCanvas)
setCanvasSizes(outputCanvas)
setCanvasSizes(precomputedInputCanvas)
setCanvasSizes(precomputedOutputCanvas)

local inputBounds = Bounds.new(
    im(INPUT_MIN[1], INPUT_MIN[2]),
    im(INPUT_MAX[1], INPUT_MAX[2]),
    inputCanvas.width,
    inputCanvas.height
)

local outputBounds = Bounds.new(
    im(OUTPUT_MIN[1], OUTPUT_MIN[2]),
    im(OUTPUT_MAX[1], OUTPUT_MAX[2]),
    outputCanvas.width,
    outputCanvas.height
)

local inputAxes = Axes(inputBounds, inputCanvas, inputCtx)
local outputAxes = Axes(outputBounds, outputCanvas, outputCtx)

---@type ComplexPath[]
local inputSquiggles = {}
---@type ComplexPath[]
local outputSquiggles = {}

local lineWidth = BASE_PATH_THICKNESS
js.global.document:getElementById "strokeWidth".value = tostring(lineWidth)
local strokeStyle = js.global.document:getElementById "strokeColor".value

local funcTextField = js.global.document:getElementById "func"
local func
local shouldRedraw

local z = sd.var "z"
local exportedValues = {
    z = z,
    i = sd.const(im.i),
    e = sd.const(math.exp(1)),
    real = sd.real,
    imag = sd.imag,
    exp = sd.exp,
    log = sd.ln,
    conj = sd.conj,
    sqrt = sd.sqrt,
    -- roots = sd.roots, -- TODO: add multifunctions, this would be awesome
    abs = sd.abs,
    arg = sd.arg,
    sin = sd.sin,
    cos = sd.cos,
    tan = sd.tan,
    asin = sd.asin,
    acos = sd.acos,
    atan = sd.atan,
    sinh = sd.sinh,
    cosh = sd.cosh,
    tanh = sd.tanh,
    asinh = sd.asinh,
    acosh = sd.acosh,
    atanh = sd.atanh,
}

local lastMouseX, lastMouseY
local redraw
local userDrawing

local function currentInputSquiggle()
    return inputSquiggles[#inputSquiggles]
end

local function currentOutputSquiggle()
    return outputSquiggles[#outputSquiggles]
end

local function markDirty()
    shouldRedraw = true
end

local function loadFunc(text)
    if #text > 100 then
        return nil, "Input text too long, won't compile"
    end
    text = text:gsub("(%d+%.%d+)i%f[%W]", "(%1*i)")
    text = text:gsub("%.(%d+)i%f[%W]", "(0.%1*i)")
    text = text:gsub("(%d+)i%f[%W]", "(%1*i)")
    -- TODO: wrap this into a multiexpression
    -- TODO: create multiexpression in symdiff
    -- local wrappedText = "{"..text.."}"
    -- local s, e = wrappedText:find "%b{}"
    -- if s ~= 1 or e ~= #wrappedText then
    --     return nil, "Unbalanced brackets"
    -- end

    local chunk = load("return "..text, "user function", "t", exportedValues)
    if not chunk then
        return nil, "Could not compile"
    end
    return chunk()
end

local function calculateFuncAndThickness(c)
    ---@type Complex
    local fc = func:evaluate(c)
    local dz = func:derivative():evaluate(c):abs()
    local originalThickness = lineWidth * OUTPUT_AREA / INPUT_AREA
    return fc, originalThickness * dz
end

local function updateLastPoint(c)
    currentInputSquiggle():updateLastPoint(c)
    currentOutputSquiggle():updateLastPoint(calculateFuncAndThickness(c))
    markDirty()
end

local function shouldCreateNewMousePoint(x, y)
    if not lastMouseX or not lastMouseY then
        return true
    end
    return math.sqrt((x-lastMouseX)^2 + (y-lastMouseY)^2) > MIN_PIXEL_DIST_FOR_NEW_POINT
end

local function pushPointPair(inputPoint, outputPoint, outputThickness, discontinuity)
    currentInputSquiggle():pushPoint(inputPoint)
    currentInputSquiggle():drawLastAddedSegment(precomputedInputCtx, inputBounds)

    if not outputPoint or not outputThickness then
        outputPoint, outputThickness = calculateFuncAndThickness(inputPoint)
    end
    -- print(inputPoint, '->', outputPoint)
    currentOutputSquiggle():pushPoint(outputPoint, outputThickness, discontinuity)
    currentOutputSquiggle():drawLastAddedSegment(precomputedOutputCtx, outputBounds)
end

-- FIXME: update this when user zooms out
local maxTolerableDistanceForInterp = outputBounds:pixelsToMeasurement(MAX_PIXEL_DISTANCE_BEFORE_INTERP)
local function recursivelyPushPointsIfNeeded(depth, targetInputPoint, targetOutputPoint, endThickness)
    if not targetOutputPoint or not endThickness then
        targetOutputPoint, endThickness = calculateFuncAndThickness(targetInputPoint)
    end
    local dist = (targetOutputPoint - currentOutputSquiggle():endPoint()):abs()
    local interpStart = currentInputSquiggle():endPoint()
    local interpEnd = targetInputPoint
    if dist >= MAX_PIXEL_DISTANCE_BEFORE_DISCONTINUITY then
        pushPointPair(targetInputPoint, targetOutputPoint, endThickness, true)
    elseif dist >= maxTolerableDistanceForInterp and depth < MAX_INTERP_TRIES then
        for i = 1, INTERP_STEPS do
            local interpT = i / INTERP_STEPS
            local interpPoint = (1-interpT) * interpStart + interpT * interpEnd
            local interpF, interpThickness = calculateFuncAndThickness(interpPoint)
            recursivelyPushPointsIfNeeded(depth+1, interpPoint, interpF, interpThickness)
        end
    else
        pushPointPair(targetInputPoint, targetOutputPoint, endThickness, false)
    end
end

local function simplePushPoint(x, y, c)
    pushPointPair(c)
    lastMouseX, lastMouseY = x, y
    markDirty()
end

local function createNewMousePoint(x, y, c)
    recursivelyPushPointsIfNeeded(1, c)
    lastMouseX, lastMouseY = x, y
    markDirty()
end

local function pushComplexPoint(c, x, y, forceNewPoint)
    if forceNewPoint then
        simplePushPoint(x, y, c)
    elseif shouldCreateNewMousePoint(x, y) then
        createNewMousePoint(x, y, c)
        simplePushPoint(x, y, c)
    end
end

local function pushMousePoint(mouseEvent, forceNewPoint)
    if not userDrawing then
        return
    end

    local x, y = mouseEvent.clientX - inputCanvas.offsetLeft, mouseEvent.clientY -  inputCanvas.offsetTop
    local c = inputBounds:pixelToComplex(x, y)
    if shouldCreateNewMousePoint(x, y) then
        pushComplexPoint(c, x, y, forceNewPoint)
    else
        -- TODO: this call breaks the path into tiny insufferable and arrogant sausages
        -- updateLastPoint(c)
    end
end

local function drawGuides()
    inputAxes:draw()
    outputAxes:draw()
end
drawGuides()

local function redrawOldPaths(canvas, ctx, paths, bounds)
    ctx:clearRect(0, 0, canvas.width, canvas.height)
    for _, squiggle in ipairs(paths) do
        squiggle:draw(ctx, bounds)
    end
end

function redraw(recalculateOldPaths)
    inputCtx:clearRect(0, 0, inputCanvas.width, inputCanvas.height)
    outputCtx:clearRect(0, 0, outputCanvas.width, outputCanvas.height)
    drawGuides()
    if recalculateOldPaths then
        redrawOldPaths(precomputedInputCanvas, precomputedInputCtx, inputSquiggles, inputBounds)
        redrawOldPaths(precomputedOutputCanvas, precomputedOutputCtx, outputSquiggles, outputBounds)
    end
    inputCtx:drawImage(precomputedInputCanvas, 0, 0)
    outputCtx:drawImage(precomputedOutputCanvas, 0, 0)
    if userDrawing then
        currentInputSquiggle():drawLastAddedSegment(inputCtx, inputBounds)
        currentOutputSquiggle():drawLastAddedSegment(outputCtx, outputBounds)
    end
    shouldRedraw = false
end

local function startPath(mode, arg, color, thickness)
    userDrawing = true

    table.insert(inputSquiggles, CPath.new(color, thickness))
    table.insert(outputSquiggles, CPath.new(color, thickness, MAX_PATH_THICKNESS))
    if mode == "user" then
        pushMousePoint(arg, true)
        -- twice, for end point manipulation
        pushMousePoint(arg, true)
    else
        pushComplexPoint(arg, nil, nil, true)
    end
end

local function finishPath()
    userDrawing = false
end

local lockUserInput = false
local function fullyRecalculate()
    local oldInputSquiggles = inputSquiggles
    inputSquiggles, outputSquiggles = {}, {}
    lockUserInput = true
    for _, squiggle in ipairs(oldInputSquiggles) do
        startPath("prog", squiggle:startPoint(), squiggle.color, squiggle.defaultThickness)
        for point in squiggle:tail() do
            recursivelyPushPointsIfNeeded(1, point)
        end
        finishPath()
    end
    lockUserInput = false
    redraw(true)
end

local function updateFunc()
    local newFunc, reason = loadFunc(funcTextField.value)
    if newFunc then
        func = newFunc
        if type(func) == "number" then
            func = im.asComplex(func)
        end
        if im.isComplex(func) then
            func = sd.const(func)
        end
        fullyRecalculate()
    else
        print(reason)
    end
end
funcTextField.value = DEFAULT_FUNC
updateFunc()

toolbar:addEventListener("click", function(_, event)
    if event.target.id == "clear" then
        precomputedInputCtx:clearRect(0, 0, precomputedInputCanvas.width, precomputedInputCanvas.height)
        precomputedOutputCtx:clearRect(0, 0, precomputedOutputCanvas.width, precomputedOutputCanvas.height)
        inputCtx:clearRect(0, 0, inputCanvas.width, inputCanvas.height)
        outputCtx:clearRect(0, 0, outputCanvas.width, outputCanvas.height)
        inputSquiggles = {}
        outputSquiggles = {}
        drawGuides()
    elseif event.target.id == "undo" then
        table.remove(inputSquiggles)
        table.remove(outputSquiggles)
        -- TODO: also keep history of precomputed canvases to make undo instant
        redraw(true)
    end
end)

toolbar:addEventListener("input", function(_, event)
    if event.target.id == "strokeColor" then
        strokeStyle = event.target.value
    elseif event.target.id == "strokeWidth" then
        lineWidth = tonumber(event.target.value) or BASE_PATH_THICKNESS
    end
end)

inputCanvas:addEventListener("mousedown", function(_, event)
    startPath("user", event, strokeStyle, lineWidth)
end)

local function userFinishPath()
    if lockUserInput then
        return
    end
    finishPath()
end
inputCanvas:addEventListener("mouseup", userFinishPath)
inputCanvas:addEventListener("mouseout", userFinishPath)

-- TODO: add coordinates of mouse to some part of the UI
inputCanvas:addEventListener("mousemove", function(_, event)
    if not userDrawing or lockUserInput then
        return
    end

    pushMousePoint(event)
end)

local function functTextInputChange()
    if lockUserInput then
        return
    end
    updateFunc()
end
funcTextField:addEventListener("input", functTextInputChange)

local function redrawIfDirty()
    if shouldRedraw then
        redraw()
    end
end

js.global:setInterval(redrawIfDirty, 1000 / 60)
