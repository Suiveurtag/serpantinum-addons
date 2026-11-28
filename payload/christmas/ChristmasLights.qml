import QtQuick
import "../"

// A string of fairy lights on a wire (shaders/lights.frag). When `on` turns true the bulbs light one after the
// other from `origin`; when it turns false they go out together. The wire runs along the top of the item and the
// bulbs hang below it.
Item {
    id: string
    enabled: false

    property bool on: Christmas.enabled
    property bool live: true            // twinkles with the shared clock; false keeps every bulb steady
    property bool instant: false        // light up at once instead of cascading
    property real spacing: 22
    property real swag: spacing * 3
    property real sag: 4
    property real wireY: 3
    property real bulb: 3.2
    property real glow: 0.55
    property real origin: 0.5
    property bool inward: false
    property real seed: 0
    property int cascade: 1400
    property color wireColor: Christmas.wire
    property real lit: 0
    property bool keepDark: false       // draw the unlit string while off
    property int style: Christmas.lightsIndex
    property bool randomStyle: Christmas.randomLights
    readonly property int randomStyleIndex: Math.floor(Math.random() * 4)
    property bool ready: false
    onStyleChanged: if (ready && !randomStyle) relight()
    onRandomStyleChanged: if (ready) relight()
    readonly property bool shown: visible && width > 1 && height > 1 && (on || lit > 0.001 || keepDark)

    function relight(): void {
        if (!on) return;
        fall.stop();
        if (!Christmas.motion) { lit = 1; return; }
        lit = 0;
        rise.restart();
    }
    onOnChanged: {
        if (on) {
            fall.stop();
            if (Christmas.motion && !instant) rise.restart();
            else lit = 1;
        } else {
            rise.stop();
            if (Christmas.motion) fall.restart();
            else lit = 0;
        }
    }
    Component.onCompleted: {
        ready = true;
        if (on) {
            if (Christmas.motion && !instant) rise.restart();
            else lit = 1;
        }
        syncClock();
    }
    NumberAnimation { id: rise; target: string; property: "lit"; to: 1; duration: string.cascade; easing.type: Easing.InOutSine }
    NumberAnimation { id: fall; target: string; property: "lit"; to: 0; duration: 420; easing.type: Easing.InQuad }

    readonly property bool clocked: shown && on && live
    property bool registered: false
    function syncClock(): void {
        if (clocked === registered) return;
        registered = clocked;
        Christmas.requestClock(clocked);
    }
    onClockedChanged: syncClock()
    Component.onDestruction: if (registered) Christmas.requestClock(false)

    ShaderEffect {
        anchors.fill: parent
        visible: string.shown
        blending: true
        readonly property size extent: Qt.size(width, height)
        readonly property real spacing: string.spacing
        readonly property real swag: Math.max(string.spacing, string.swag)
        readonly property real sag: string.sag
        readonly property real wireY: string.wireY
        readonly property real bulb: string.bulb
        readonly property real phase: Christmas.phase
        readonly property real twinkle: string.live && Christmas.twinkle && Christmas.motion ? 0.85 : 0
        readonly property real lit: string.lit
        readonly property real origin: string.origin
        readonly property real inward: string.inward ? 1 : 0
        readonly property real lights: string.randomStyle ? string.randomStyleIndex : string.style
        readonly property real glow: string.glow
        readonly property real seed: string.seed
        readonly property color wireColor: string.wireColor
        fragmentShader: Qt.resolvedUrl("shaders/lights.frag.qsb")
    }
}
