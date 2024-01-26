package.path = "lua/?.lua;lua/?/?.lua;lua/?/init.lua;" .. package.path

local js = require "js"
_G.im = require "imagine"
_G.sd = require "symdiff"
local im = _G.im
local sd = _G.sd
local CPath = require "complexpath"
local Bounds = require "bounds"
require "constants"
require "im-sd-bridge"


local inputCanvas = js.global.document:getElementById "inputBoard"
local outputCanvas = js.global.document:getElementById "outputBoard"
local toolbar = js.global.document:getElementById "toolbar"

local inputCtx = inputCanvas:getContext "2d"
local outputCtx = outputCanvas:getContext "2d"
local canvasOffsetX = inputCanvas.offsetLeft
local canvasOffsetY = inputCanvas.offsetTop

-- canvas.width = js.global.innerWidth - canvasOffsetX
-- canvas.height = js.global.innerWidth - canvasOffsetY
inputCanvas.width = 600
inputCanvas.height = 600
outputCanvas.width = 600
outputCanvas.height = 600

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

---@type ComplexPath[]
local inputSquiggles = {}

-- TODO interpolate between input points if they're too far apart
-- TODO break path at discontinuities
---@type ComplexPath?
local currentInputSquiggle = nil
---@type ComplexPath?
local currentOutputSquiggle = nil

local lineWidth = BASE_PATH_THICKNESS
js.global.document:getElementById "strokeWidth".value = tostring(lineWidth)
local strokeStyle = js.global.document:getElementById "strokeColor".value

local funcTextField = js.global.document:getElementById "func"

local z = sd.var "z"

local function loadFunc(text)
    -- TODO inject imagine functions into env
    -- TODO allow for 2+3i style notation (this might be very tricky)
    if #text > 100 then
        return nil, "input text too long, won't compile"
    end
    local fenv = {z = z}
    local chunk = load("return "..text, "user function", "t", fenv)
    if not chunk then
        return nil, "could not compile"
    end
    return chunk()
end

local func

local function updateFunc()
    local newFunc, reason = loadFunc(funcTextField.value)
    print(funcTextField.value, newFunc, reason)
    if newFunc then
        func = newFunc
        -- TODO redraw paths
    end
end
funcTextField.value = DEFAULT_FUNC
updateFunc()
-- TODO updatefunc on text input change

local function pushMousePoint(mouseEvent)
    if not currentInputSquiggle then
        return
    end

    ---@cast currentOutputSquiggle ComplexPath
    local x, y = mouseEvent.clientX - canvasOffsetX, mouseEvent.clientY - canvasOffsetY
    local c = inputBounds:pixelToComplex(x, y)
    currentInputSquiggle:pushPoint(c)

    ---@type Complex
    ---@diagnostic disable-next-line: assign-type-mismatch
    local fc = func:evaluate(c)
    local dz = im.abs(func:derivative():evaluate(c))
    local originalThickness = currentInputSquiggle:endThickness() * OUTPUT_AREA / INPUT_AREA
    currentOutputSquiggle:pushPoint(fc, dz * originalThickness)
end

local function drawGuides(ctx, bounds)
    ctx:setLineDash {5, 3}
    ctx:beginPath()
    ctx.strokeStyle = "#000000"
    ctx.lineWidth = 1
    local x0, y0 = bounds:complexToPixel(im.zero)
    local lowerX, upperY = bounds:complexToPixel(bounds.upperLeft)
    local upperX, lowerY = bounds:complexToPixel(bounds.lowerRight)
    ctx:moveTo(x0, lowerY)
    ctx:lineTo(x0, upperY)
    ctx:moveTo(lowerX, y0)
    ctx:lineTo(upperX, y0)
    ctx:stroke()
end
drawGuides(inputCtx, inputBounds)
drawGuides(outputCtx, outputBounds)

local function redraw()
    inputCtx:clearRect(0, 0, inputCanvas.width, inputCanvas.height)
    outputCtx:clearRect(0, 0, outputCanvas.width, outputCanvas.height)

    drawGuides(inputCtx, inputBounds)
    drawGuides(outputCtx, outputBounds)
    for _, squiggle in ipairs(inputSquiggles) do
        squiggle:draw(inputCtx, inputBounds)
        local outputSquiggle = squiggle:transform(func)
        outputSquiggle:draw(outputCtx, outputBounds)
    end
end

toolbar:addEventListener("click", function(_, event)
    if event.target.id == "clear" then
        inputCtx:clearRect(0, 0, inputCanvas.width, inputCanvas.height)
        outputCtx:clearRect(0, 0, outputCanvas.width, outputCanvas.height)
        inputSquiggles = {}
        drawGuides(inputCtx, inputBounds)
        drawGuides(outputCtx, outputBounds)
    elseif event.target.id == "undo" then
        table.remove(inputSquiggles)
        redraw()
    elseif event.target.id == "redraw" then
        redraw()
    end
end)

toolbar:addEventListener("change", function(_, event)
    if event.target.id == "strokeColor" then
        strokeStyle = event.target.value
    elseif event.target.id == "strokeWidth" then
        lineWidth = event.target.value
    end
end)

inputCanvas:addEventListener("mousedown", function(_, event)
    currentInputSquiggle = CPath.new(strokeStyle, lineWidth, INPUT_INTERP_SEGMENTS)
    currentOutputSquiggle = CPath.new(strokeStyle)
    pushMousePoint(event)
end)

local function finishPath()
    table.insert(inputSquiggles, currentInputSquiggle)
    currentInputSquiggle = nil
    currentOutputSquiggle = nil
end
inputCanvas:addEventListener("mouseup", finishPath)
inputCanvas:addEventListener("mouseout", finishPath)

inputCanvas:addEventListener("mousemove", function(_, event)
    if not currentInputSquiggle then
        return
    end
    -- if currentInputSquiggle is not nil, the same goes for currentOutputSquiggle
    ---@cast currentOutputSquiggle ComplexPath

    pushMousePoint(event)

    currentInputSquiggle:drawLastAddedSegments(inputCtx, inputBounds)
    currentOutputSquiggle:drawLastAddedSegments(outputCtx, outputBounds)
end)
