import QtQuick
import "../"

// A window that takes the focus is wrapped in lights: they run along its top from the middle, down both sides, and
// meet again in the middle of its bottom edge, then fade. The bulbs hang into the window from its border.
Item {
    id: wrap
    enabled: false
    property rect frame: Qt.rect(0, 0, 0, 0)
    readonly property bool playing: run.running
    readonly property real unit: Scaler.s(1)
    readonly property real band: unit * 34
    property real topLit: 0
    property real sideLit: 0
    property real bottomLit: 0

    function play(rect: rect): void {
        if (!Christmas.motion) return;
        frame = rect;
        run.restart();
    }

    SequentialAnimation {
        id: run
        PropertyAction { target: wrap; property: "opacity"; value: 1 }
        PropertyAction { targets: [wrap]; properties: "topLit,sideLit,bottomLit"; value: 0 }
        ParallelAnimation {
            NumberAnimation { target: wrap; property: "topLit"; to: 1; duration: 440; easing.type: Easing.Linear }
            SequentialAnimation {
                PauseAnimation { duration: 330 }
                NumberAnimation { target: wrap; property: "sideLit"; to: 1; duration: 520; easing.type: Easing.Linear }
            }
            SequentialAnimation {
                PauseAnimation { duration: 760 }
                NumberAnimation { target: wrap; property: "bottomLit"; to: 1; duration: 420; easing.type: Easing.Linear }
            }
        }
        PauseAnimation { duration: 260 }
        NumberAnimation { target: wrap; property: "opacity"; to: 0; duration: 520; easing.type: Easing.InQuad }
    }

    component Edge: ChristmasLights {
        on: false
        live: false
        opacity: Christmas.effectOpacity
        transformOrigin: Item.TopLeft
        height: wrap.band
        spacing: wrap.unit * 26
        swag: spacing
        sag: 0
        wireY: 0
        bulb: wrap.unit * 3.3
        glow: 0.75
        visible: wrap.playing
    }
    Edge { x: wrap.frame.x; y: wrap.frame.y; width: wrap.frame.width; lit: wrap.topLit; origin: 0.5; seed: 1 }
    Edge { x: wrap.frame.x + wrap.frame.width; y: wrap.frame.y; width: wrap.frame.height; rotation: 90; lit: wrap.sideLit; origin: 0; seed: 2 }
    Edge { x: wrap.frame.x; y: wrap.frame.y + wrap.frame.height; width: wrap.frame.height; rotation: -90; lit: wrap.sideLit; origin: 1; seed: 3 }
    Edge { x: wrap.frame.x + wrap.frame.width; y: wrap.frame.y + wrap.frame.height; width: wrap.frame.width; rotation: 180
           lit: wrap.bottomLit; origin: 0.5; inward: true; seed: 4 }
}
