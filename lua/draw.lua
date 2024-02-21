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

-- TODO: add actual line smoothing to input
-- TODO: use promises to fully recalculate so it doesnt hang
local document = js.global.document

local inputCanvas = document:getElementById "inputBoard"
local outputCanvas = document:getElementById "outputBoard"
local precomputedInputCanvas = document:createElement "canvas"
local precomputedOutputCanvas = document:createElement "canvas"
local toolbar = document:getElementById "toolbar"

local inputCtx = inputCanvas:getContext "2d"
local outputCtx = outputCanvas:getContext "2d"
local precomputedInputCtx = precomputedInputCanvas:getContext "2d"
local precomputedOutputCtx = precomputedOutputCanvas:getContext "2d"

local penSizeButtons = document:getElementById "penSizeButtons"

local function setCanvasSize(canvas)
    local style = js.global:getComputedStyle(canvas.parentNode)
    local width = style:getPropertyValue "width":gsub("px", "")
    local height = style:getPropertyValue "height":gsub("px", "")
    width = math.floor(math.min(tonumber(width) or 0, tonumber(height) or 0))
    canvas.width = width
    canvas.height = width
end

local function copyCanvasSize(from, to)
    to.width = from.width
    to.height = from.height
end
setCanvasSize(inputCanvas)
copyCanvasSize(inputCanvas, outputCanvas)
copyCanvasSize(inputCanvas, precomputedInputCanvas)
copyCanvasSize(outputCanvas, precomputedOutputCanvas)

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

local lineWidth

-- local lineWidthComponent = js.global.document:getElementById "strokeWidth"
-- lineWidthComponent.value = tostring(lineWidth)
local strokeStyleComponent = document:getElementById "strokeColor"
local strokeStyle = strokeStyleComponent.color

-- TODO: use [mathquill](https://github.com/mathquill/mathquill) instead of a raw text field.
-- this will require parsing latex into a lua expression, which shouldnt be too bad
local funcTextField = document:getElementById "func"
local func
local shouldRedraw

local z = sd.var "z"
local exportedValues = {
    z = z,
    i = sd.const(im.i),
    e = sd.const(math.exp(1)),
    pi = sd.const(math.pi),
    tau = sd.const(2*math.pi),
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
    local ok, result = pcall(chunk)
    if ok then
        return result
    else
        return nil, result
    end
end

local function calculateFuncAndThickness(c)
    ---@type Complex
    local fc = func:evaluate(c)
    local dz = func:derivative():evaluate(c):abs()
    local originalThickness = lineWidth * OUTPUT_AREA / INPUT_AREA
    return fc, originalThickness * dz
end

local function pixelDist(x1, y1, x2, y2)
    return math.sqrt((x1 - x2)^2 + (y1 - y2)^2)
end

local function shouldCreateNewMousePoint(x, y)
    if not lastMouseX or not lastMouseY then
        return true
    end
    return pixelDist(x, y, lastMouseX, lastMouseY) > MIN_PIXEL_DIST_FOR_NEW_POINT
end

local function pushPointPair(inputPoint, outputPoint, outputThickness, discontinuity)
    currentInputSquiggle():pushPoint(inputPoint)
    currentInputSquiggle():drawLastAddedSegment(precomputedInputCtx, inputBounds)

    if not outputPoint or not outputThickness then
        outputPoint, outputThickness = calculateFuncAndThickness(inputPoint)
    end
    currentOutputSquiggle():pushPoint(outputPoint, outputThickness, discontinuity)
    currentOutputSquiggle():drawLastAddedSegment(precomputedOutputCtx, outputBounds)
end

-- FIXME: update this when user zooms in or out
local maxTolerableDistanceForInterp = outputBounds:pixelsToMeasurement(MAX_PIXEL_DISTANCE_BEFORE_INTERP)
local function recursivelyPushPointsIfNeeded(depth, targetInputPoint, targetOutputPoint, endThickness)
    if not targetOutputPoint or not endThickness then
        targetOutputPoint, endThickness = calculateFuncAndThickness(targetInputPoint)
    end
    if not currentOutputSquiggle():hasPoints() then
        pushPointPair(targetInputPoint, targetOutputPoint, endThickness, false)
        return
    end

    local dist = (targetOutputPoint - currentOutputSquiggle():endPoint()):abs()
    local interpStart = currentInputSquiggle():endPoint()
    local interpEnd = targetInputPoint
    if dist >= MAX_PIXEL_DISTANCE_BEFORE_DISCONTINUITY then
        pushPointPair(targetInputPoint, targetOutputPoint, endThickness, true)
    elseif dist >= maxTolerableDistanceForInterp and depth <= MAX_INTERP_TRIES then
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

local function getEventCoords(event)
    if event.clientX then
        return event.clientX, event.clientY
    else
        -- TODO: multiple touches?
        return event.touches[0].clientX, event.touches[0].clientY
    end
end
local function pushMousePoint(event, forceNewPoint)
    if not userDrawing then
        return
    end

    local x, y = getEventCoords(event)
    x, y = x - inputCanvas.offsetLeft, y -  inputCanvas.offsetTop
    local c = inputBounds:pixelToComplex(x, y)
    pushComplexPoint(c, x, y, forceNewPoint)
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
    shouldRedraw = false
end

local function startPath(mode, arg, color, thickness)
    userDrawing = true

    table.insert(inputSquiggles, CPath.new(color, thickness))
    table.insert(outputSquiggles, CPath.new(color, thickness, MAX_PATH_THICKNESS))
    if mode == "user" then
        pushMousePoint(arg, true)
        -- for single dots to show immediately
        pushMousePoint(arg, true)
    elseif mode == "prog" then
        pushComplexPoint(arg, nil, nil, true)
    else
        error("Unknown startPath mode: " .. tostring(mode))
    end
end

local function finishPath()
    if currentInputSquiggle() then
        local startX, startY = inputBounds:complexToPixel(currentInputSquiggle():startPoint())
        local endX, endY = inputBounds:complexToPixel(currentInputSquiggle():endPoint())
        local dist = pixelDist(startX, startY, endX, endY)
        if dist <= CLOSE_PATH_DIST then
            pushComplexPoint(currentInputSquiggle():startPoint(), nil, nil, true)
        end
    end
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
        if type(newFunc) == "number" then
            newFunc = im.asComplex(newFunc)
        end
        if im.isComplex(newFunc) then
            newFunc = sd.const(newFunc)
        end
        if sd.isExpression(newFunc) then
            func = newFunc
            fullyRecalculate()
        else
            print("Incomplete expression")
        end
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
        redraw(true)
    end
end)

local unselectedPenSizeColor = "#555"
local selectedPenSizeColor = "#ddd"
local function rerenderPenSizeCanvases()
    local buttons = penSizeButtons.children
    for i = 0, #buttons-1 do
        local button = buttons[i]
        local canvas = button.children[0]
        local ctx = canvas:getContext "2d"
        local radius = tonumber(button.value)
        local cx, cy = math.floor(canvas.width/2) + 0.5, math.floor(canvas.height/2) + 0.5
        if button.value == tostring(lineWidth) then
            ctx.fillStyle = unselectedPenSizeColor
            ctx:fillRect(0, 0, canvas.width, canvas.height)
            ctx.fillStyle = selectedPenSizeColor
        else
            ctx:clearRect(0, 0, canvas.width, canvas.height)
            ctx.fillStyle = unselectedPenSizeColor
        end
        ctx:beginPath()
        ctx:arc(cx, cy, radius, 0, 2*math.pi)
        ctx:fill()
    end
end

local function resizePenSizeCanvases()
    local buttons = penSizeButtons.children
    for i = 0, #buttons-1 do
        local button = buttons[i]
        local canvas = button.children[0]
        local dim = button:getBoundingClientRect()
        canvas.width, canvas.height = dim.width, dim.height
    end
end

local function selectPenSize(_, button)
    if not button.value then
        return
    end
    lineWidth = tonumber(button.value)
    rerenderPenSizeCanvases()
end
penSizeButtons:addEventListener("click", function(_, event)
    -- event target is canvas element inside button
    selectPenSize(_, event.target.parentElement)
end)
resizePenSizeCanvases()
selectPenSize(_, penSizeButtons.children[1])

strokeStyleComponent:addEventListener("change", function(_, event)
    strokeStyle = event.target.hex
end)

local function userStartPath(_, event)
    startPath("user", event, strokeStyle, lineWidth)
end
inputCanvas:addEventListener("touchstart", userStartPath, {passive = false})
inputCanvas:addEventListener("mousedown", userStartPath)

local function userFinishPath(_, mouseEvent)
    if lockUserInput then
        return
    end
    pushMousePoint(mouseEvent, true)
    finishPath()
end
inputCanvas:addEventListener("mouseup", userFinishPath)
inputCanvas:addEventListener("touchend", userFinishPath)
inputCanvas:addEventListener("mouseout", userFinishPath)

-- TODO: add coordinates of mouse to some part of the UI
local function cursorMove(_, event)
    if not userDrawing or lockUserInput then
        return
    end

    pushMousePoint(event)
end
inputCanvas:addEventListener("mousemove", cursorMove)
inputCanvas:addEventListener("touchmove", cursorMove)

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
