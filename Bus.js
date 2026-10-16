.pragma library

// A .pragma library script has one instance per QML engine, so every part of
// this plugin in the shell sees the same list: a drawer that saves tells the
// others to read the settings again.
var drawers = []

function addDrawer(drawer) { if (drawers.indexOf(drawer) === -1) drawers.push(drawer) }

function removeDrawer(drawer) {
    var i = drawers.indexOf(drawer)
    if (i !== -1) drawers.splice(i, 1)
}
