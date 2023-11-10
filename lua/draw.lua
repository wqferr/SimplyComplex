-- package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local js = require "js"
local im = require "lua.imagine"
local sd = require "lua.symdiff"
local CPath = require "lua.complexpath"
local Bounds = require "lua.bounds"
require "lua.constants"

require "lua.imagineSDBridge"(im, sd)


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

local inputBounds = Bounds.new(im(-2, -2), im(2, 2), inputCanvas.width, inputCanvas.height)
local outputBounds = Bounds.new(im(-4, -4), im(4, 4), outputCanvas.width, outputCanvas.height)

---@type ComplexPath[]
local inputSquiggles = {}

---@type ComplexPath?
local currentInputSquiggle = nil
---@type ComplexPath?
local currentOutputSquiggle = nil

local lineWidth = js.global.document:getElementById "strokeWidth".value
local strokeStyle = js.global.document:getElementById "strokeColor".value

local z = sd.var "z"
local func = z*z

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
    local dz = func:derivative():evaluate(c):abs()
    local originalThickness = currentInputSquiggle:endThickness() / BASE_PATH_THICKNESS
    currentOutputSquiggle:pushPoint(fc, dz * originalThickness)
end

local function redraw()
    inputCtx:clearRect(0, 0, inputCanvas.width, inputCanvas.height)
    outputCtx:clearRect(0, 0, outputCanvas.width, outputCanvas.height)

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
    -- inputCtx:beginPath()
    -- outputCtx:beginPath()
    currentInputSquiggle = CPath.new(strokeStyle, lineWidth)
    currentOutputSquiggle = CPath.new(strokeStyle)
    pushMousePoint(event)
end)

inputCanvas:addEventListener("mouseup", function(_, event)
    table.insert(inputSquiggles, currentInputSquiggle)
    currentInputSquiggle = nil
    currentOutputSquiggle = nil
end)

inputCanvas:addEventListener("mousemove", function(_, event)
    if not currentInputSquiggle then
        return
    end
    ---@cast currentOutputSquiggle ComplexPath

    pushMousePoint(event)

    local x, y = event.clientX - canvasOffsetX, event.clientY - canvasOffsetY
    inputCtx.lineWidth = lineWidth
    inputCtx.lineCap = "round"
    inputCtx.strokeStyle = strokeStyle
    local p = currentInputSquiggle:penultimatePoint()
    if p then
        inputCtx:beginPath()
        inputCtx:moveTo(inputBounds:complexToPixel(p))
        inputCtx:lineTo(x, y)
        inputCtx:stroke()
    end

    local e = currentOutputSquiggle:endPoint()
    outputCtx.lineWidth = currentOutputSquiggle:endThickness()
    outputCtx.lineCap = "round"
    outputCtx.strokeStyle = strokeStyle
    p = currentOutputSquiggle:penultimatePoint()
    if p then
        outputCtx:beginPath()
        outputCtx:moveTo(outputBounds:complexToPixel(p))
        outputCtx:lineTo(outputBounds:complexToPixel(e))
        outputCtx:stroke()
    end
end)