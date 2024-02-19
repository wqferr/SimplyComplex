local js = require "js"
local arrowCanvas = js.global.document:getElementById "arrowCanvas"
local arrowCtx = arrowCanvas:getContext "2d"
local canvasLength = arrowCanvas.width
local canvasBreadth = arrowCanvas.height

local MARGIN_FRAC = 0.2

local function formatResolution()
    return ("%d,%d"):format(canvasLength, canvasBreadth)
end

---Rounds one or two coordinates
---@param x number
---@param y number?
---@return integer
---@return integer?
local function roundPoint(x, y)
    if y then
        return math.floor(x) + 0.5, math.floor(y) + 0.5
    else
        return math.floor(x) + 0.5
    end
end

local function getFracPoint(px, py)
    return roundPoint(px * canvasLength, py * canvasBreadth)
end

local function setCanvasOrientation()
    if arrowCanvas.width >= arrowCanvas.height then
        arrowCtx:setTransform(1, 0, 0, 1, 0, 0)
        canvasLength = arrowCanvas.width
        canvasBreadth = arrowCanvas.height
    else
        arrowCtx:setTransform(0, 1, -1, 0, arrowCanvas.width, 0)
        canvasLength = arrowCanvas.height
        canvasBreadth = arrowCanvas.width
    end
end

local lastResolutionDrawn
local function drawMapsTo()
    arrowCtx:clearRect(0, 0, arrowCanvas.width, arrowCanvas.height)
    arrowCtx.lineWidth = 3

    arrowCtx:beginPath()

    local baseX1, baseY1 = getFracPoint(MARGIN_FRAC, MARGIN_FRAC)
    local baseX2, baseY2 = getFracPoint(MARGIN_FRAC, 1 - MARGIN_FRAC)
    print(baseX1, baseY1)
    arrowCtx:moveTo(baseX1, baseY1)
    arrowCtx:lineTo(baseX2, baseY2)

    local baseYMid = roundPoint((baseY1 + baseY2) / 2)
    local baseXmid = baseX1
    local tipX, _ = getFracPoint(1 - MARGIN_FRAC, 0)
    local tipY = baseYMid

    arrowCtx:moveTo(baseXmid, baseYMid)
    arrowCtx:lineTo(tipX, tipY)

    local arrowArmY1 = baseY1
    local arrowArmY2 = baseY2
    local dist = arrowArmY2 - tipY
    local arrowArmX = tipX - dist

    arrowCtx:moveTo(arrowArmX, arrowArmY1)
    arrowCtx:lineTo(tipX, tipY)
    arrowCtx:lineTo(arrowArmX, arrowArmY2)

    arrowCtx:stroke()
end

js.global:setInterval(function()
    local newResolution = formatResolution()
    if newResolution ~= lastResolutionDrawn then
        lastResolutionDrawn = newResolution
        setCanvasOrientation()
        drawMapsTo()
    end
end, 100)
