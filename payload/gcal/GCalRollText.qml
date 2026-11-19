import QtQuick
import "../"

// Text that rolls to its new value: the old label slides out and fades while the new one slides in.
// `direction` picks the roll direction (1 = up, -1 = down); width follows the new text smoothly.
Item {
    id: root
    property string text: ""
    property color color: ThemeBackend.text
    property real pixelSize: Scaler.s(14)
    property int weight: Font.Bold
    property string family: ThemeBackend.fontFamily
    property int direction: 1
    property int horizontalAlignment: Text.AlignLeft
    property int elide: Text.ElideRight
    property real maxWidth: 0
    property int duration: 420

    property bool flip: false
    readonly property Text current: flip ? b : a
    readonly property real naturalWidth: current.implicitWidth
    implicitWidth: maxWidth > 0 ? Math.min(maxWidth, animWidth) : animWidth
    implicitHeight: a.implicitHeight
    clip: true

    property real animWidth: naturalWidth
    Behavior on animWidth { NumberAnimation { duration: root.duration; easing.type: Easing.OutCubic } }

    property bool ready: false
    Component.onCompleted: { a.text = root.text; ready = true; }

    onTextChanged: {
        if (!ready) return;
        if (root.current.text === root.text) return;
        const incoming = flip ? a : b;
        const outgoing = flip ? b : a;
        incoming.text = root.text;
        roll.stop();
        inY.target = incoming; inO.target = incoming;
        outY.target = outgoing; outO.target = outgoing;
        inY.from = root.height * 0.9 * root.direction;
        outY.to = -root.height * 0.9 * root.direction;
        flip = !flip;
        roll.start();
    }

    ParallelAnimation {
        id: roll
        NumberAnimation { id: inY; property: "y"; to: 0; duration: root.duration; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
        NumberAnimation { id: inO; property: "opacity"; from: 0; to: 1; duration: root.duration * 0.7; easing.type: Easing.OutCubic }
        NumberAnimation { id: outY; property: "y"; from: 0; duration: root.duration * 0.8; easing.type: Easing.InCubic }
        NumberAnimation { id: outO; property: "opacity"; to: 0; duration: root.duration * 0.5; easing.type: Easing.InCubic }
    }

    Text {
        id: a
        
        x: root.horizontalAlignment === Text.AlignRight ? root.width - width : (root.horizontalAlignment === Text.AlignHCenter ? (root.width - width) / 2 : 0)
        width: Math.min(implicitWidth, root.width)
        horizontalAlignment: root.horizontalAlignment
        color: root.color
        font.family: root.family
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        elide: root.elide
        maximumLineCount: 1
    }
    Text {
        id: b
        opacity: 0
        x: root.horizontalAlignment === Text.AlignRight ? root.width - width : (root.horizontalAlignment === Text.AlignHCenter ? (root.width - width) / 2 : 0)
        width: Math.min(implicitWidth, root.width)
        horizontalAlignment: root.horizontalAlignment
        color: root.color
        font.family: root.family
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        elide: root.elide
        maximumLineCount: 1
    }
}
