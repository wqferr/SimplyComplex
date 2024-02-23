// let MQ = MathQuill.getInterface(2);
//
let doRenderMath = () => {
    for (e of document.getElementsByClassName("math")) {
        MQ.StaticMath(e);
    }
}

// document.body.addEventListener("ready", doRenderMath)
doRenderMath()
