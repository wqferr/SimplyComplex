let inputCanvas = document.getElementById("inputBoard");
let outputCanvas = document.getElementById("outputBoard");

let setCanvasDimensions = function(canvas) {
    let dim = canvas.parentNode.getBoundingClientRect();
    let sideLen = Math.floor(Math.min(dim.width, dim.height));
    canvas.width = sideLen;
    canvas.height = sideLen;
}

let copyCanvasDimensions = function(canvasFrom, canvasTo) {
    canvasTo.width = canvasFrom.width;
    canvasTo.height = canvasFrom.height;
}

setCanvasDimensions(inputCanvas);
copyCanvasDimensions(inputCanvas, outputCanvas);
