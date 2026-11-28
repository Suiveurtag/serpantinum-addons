import QtQuick
import "../"

// Fairy lights strung inside a bar section, along its edge nearest the screen border: from the top edge of a
// horizontal bar they hang down into it, on a side bar they point in from the outer edge.
Item {
    id: garland
    enabled: false
    property real cornerRadius: 0
    property string edge: "top"
    property real seed: 0
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property real unit: Scaler.s(1)
    readonly property real inset: Math.max(unit * 4, cornerRadius * 0.7)

    ChristmasLights {
        id: lights
        transformOrigin: Item.TopLeft
        width: Math.max(0, (garland.vertical ? garland.height : garland.width) - 2 * garland.inset)
        height: garland.vertical ? garland.width : garland.height
        rotation: garland.edge === "left" ? -90 : garland.edge === "right" ? 90 : 0
        x: garland.edge === "right" ? garland.width : garland.vertical ? 0 : garland.inset
        y: garland.edge === "left" ? garland.height - garland.inset : garland.vertical ? garland.inset : 0
        spacing: garland.unit * 17
        swag: spacing * 2
        sag: garland.unit * 2.4
        wireY: garland.unit * 1.4
        bulb: garland.unit * 2.3
        glow: 0.6
        seed: garland.seed
        cascade: 1500
        Connections {
            target: Christmas
            function onLightsOnSerialChanged() { lights.relight(); }
        }
    }
}
