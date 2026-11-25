import QtQuick

// The blast KO off a screen edge, drawn by shaders/smash.frag on his pixel grid; click-through.
ShaderEffect {
    id: fx
    property real t: -1                 // s since the blast; < 0 = nothing
    property real ox: 0                 // exit point, px
    property real oy: 0
    property real angle: 0              // rad, into the screen
    property color color: "#D97757"     // his effort colour tints the jet
    property bool reducedMotion: false
    property real pixel: 1
    property real seed: 0
    property real power: 0              // 0..1, how hard he was thrown: the blast is small at 0 and grows to full size
    readonly property int life: reducedMotion ? 250 : 1350   // ms
    visible: t >= 0 && t * 1000 < life

    property size uSize: Qt.size(width, height)
    property point uOrigin: Qt.point(ox, oy)
    property point uDir: Qt.point(Math.cos(angle), Math.sin(angle))
    property color uColor: color
    property real uTime: t
    property real uPixel: pixel
    property real uSeed: seed
    property real uScale: 0.3 + 0.9 * Math.max(0, Math.min(1, power))
    property real uLow: reducedMotion ? 1 : 0
    fragmentShader: Qt.resolvedUrl("shaders/smash.frag.qsb")  // resolved here, not in the user's file
}
