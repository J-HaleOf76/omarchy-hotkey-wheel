.pragma library

// A .pragma library script has one instance per QML engine, so every part of
// this plugin in the shell sees the same list. That lets the overlay's IPC
// hand an agent's suggestion straight to the bar drawer.
var drawers = []

function addDrawer(drawer) { if (drawers.indexOf(drawer) === -1) drawers.push(drawer) }

function removeDrawer(drawer) {
    var i = drawers.indexOf(drawer)
    if (i !== -1) drawers.splice(i, 1)
}

// The drawer on the focused monitor, else any.
function drawerFor(screenName) {
    for (var i = 0; i < drawers.length; ++i)
        if (drawers[i].screenName === screenName) return drawers[i]
    return drawers[0] || null
}
