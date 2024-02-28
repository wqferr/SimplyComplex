package.path = "lua/?.lua;lua/?/?.lua;lua/?/init.lua;" .. package.path

local js = require "js"
_G.im = require "imagine"
_G.sd = require "symdiff"
local im = _G.im
local sd = _G.sd
local Bounds = require "bounds"
local App = require "app"
require "constants"
require "im-sd-bridge"

-- TODO: add actual line smoothing to input
local document = js.global.document

local inputCanvas = document:getElementById "inputBoard"
local outputCanvas = document:getElementById "outputBoard"
local toolbar = document:getElementById "toolbar"

local penSizeButtons = document:getElementById "penSizeButtons"

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

local app = App.new {
    inputCanvas = inputCanvas,
    outputCanvas = outputCanvas,
    inputBounds = inputBounds,
    outputBounds = outputBounds
}

local strokeStyleComponent = document:getElementById "strokeColor"
local strokeStyle = strokeStyleComponent.color

-- TODO: use [mathquill](https://github.com/mathquill/mathquill) instead of a raw text field.
-- this will require parsing latex into a lua expression, which shouldnt be too bad
local funcTextField = document:getElementById "func"

local z = sd.var "z"
local exportedValues = {
    z = z,
    i = sd.const(im.i),
    e = sd.const(math.exp(1)),
    pi = sd.const(math.pi),
    tau = sd.const(2*math.pi),
    real = sd.real,
    imag = sd.imag,
    conj = sd.conj,
    exp = sd.exp,
    ln = sd.ln,
    sqrt = sd.sqrt,
    -- roots = sd.roots, -- TODO: add multifunctions, this would be awesome
    abs = sd.abs,
    arg = sd.arg,
    sin = sd.sin,
    cos = sd.cos,
    tan = sd.tan,
    -- asin = sd.asin,
    -- acos = sd.acos,
    -- atan = sd.atan,
    sinh = sd.sinh,
    cosh = sd.cosh,
    tanh = sd.tanh,
    -- arsinh = sd.arsinh,
    -- arcosh = sd.arcosh,
    -- artanh = sd.artanh,
}

local errorTextBox = js.global.document:getElementById "errorText"
local function reportError(message)
    errorTextBox.innerText = message
end

local function clearError()
    errorTextBox.innerText = ""
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
        reportError "Could not compile"
        return nil
    end
    local ok, result = pcall(chunk)
    if not ok then
        reportError(result)
        return nil
    end
    if tostring(result) == tostring(app:getFunc()) then
        return nil
    end
    clearError()
    return result
end

local function getPageScroll()
    if js.global.pageYOffset then
        return js.global.pageXOffset, js.global.pageYOffset
    elseif js.global.document.documentElement and js.global.document.documentElement.scrollTop then
        return js.global.document.documentElement.scrollLeft, js.global.document.documentElement.scrollTop
    elseif js.global.document.body.scrollTop then
        return js.global.document.body.scrollLeft, js.global.document.body.scrollTop
    else
        return 0, 0
    end
end

local function getEventCoords(event)
    local x, y
    if event.clientX then
        x, y = event.clientX, event.clientY
    else
        -- TODO: multiple touches?
        x, y = event.touches[0].clientX, event.touches[0].clientY
    end
    local scrollX, scrollY = getPageScroll()
    x = x + scrollX - inputCanvas.offsetLeft
    y = y + scrollY - inputCanvas.offsetTop
    return x, y
end

local lastLoadedFunc
local function updateFuncToLuaExpression(luaExpr)
    local newFunc = loadFunc(luaExpr)
    if newFunc then
        if type(newFunc) == "number" then
            newFunc = im.asComplex(newFunc)
        end
        if im.isComplex(newFunc) then
            newFunc = sd.const(newFunc)
        end
        if sd.isExpression(newFunc) then
            lastLoadedFunc = luaExpr
            app:setFunc(newFunc)
            clearError()
        else
            reportError "Incomplete expression"
        end
    end
end

local function loadFuncFromTextField()
    -- TODO: update this to convert MathQuill into a Lua expression in this function
    updateFuncToLuaExpression(funcTextField.value)
end

funcTextField.value = DEFAULT_FUNC
loadFuncFromTextField()

js.global:setInterval(function()
    if lastLoadedFunc ~= funcTextField.value then
        loadFuncFromTextField()
    end
end, 1000)

local periodOf60Hz = 1000 / 60
local function renderApp()
    app:render()
    js.global:setTimeout(renderApp, periodOf60Hz)
end
renderApp()

toolbar:addEventListener("click", function(_, event)
    if event.target.id == "clear" then
        app:clear()
    elseif event.target.id == "undo" then
        app:removeLastSquiggle()
    end
end)

local unselectedPenSizeColor = "#555"
local selectedPenSizeColor = "#ddd"
local lineWidth = nil
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
    selectPenSize(nil, event.target.parentElement)
end)
resizePenSizeCanvases()

-- this is 0-indexed, so this picks the middle button
selectPenSize(nil, penSizeButtons.children[1])

strokeStyleComponent:addEventListener("change", function(_, event)
    strokeStyle = event.target.hex
end)

local function userStartPath(_, event)
    local cx, cy = getEventCoords(event)
    app:startDrawing(strokeStyle, lineWidth, cx, cy)
end
inputCanvas:addEventListener("touchstart", userStartPath, {passive = false})
inputCanvas:addEventListener("mousedown", userStartPath)

local function userFinishPath(enableTracking)
    app:finishDrawing()
    app:setCursorTrackingEnabled(enableTracking)
end

inputCanvas:addEventListener("mouseup", function()
    userFinishPath(true)
end)
inputCanvas:addEventListener("touchend", function()
    userFinishPath(false)
end)
inputCanvas:addEventListener("mouseout", function()
    userFinishPath(false)
end)

local function cursorMove(_, event)
    local cx, cy = getEventCoords(event)
    app:updateCursorPosition(cx, cy)
end
inputCanvas:addEventListener("mousemove", function(_, event)
    cursorMove(nil, event)
    app:setCursorTrackingEnabled(true)
end)

inputCanvas:addEventListener("touchmove", function(_, event)
    cursorMove(nil, event)
    event:preventDefault()
end, {passive = false})

local function functTextInputChange()
    loadFuncFromTextField()
end
funcTextField:addEventListener("input", functTextInputChange)
