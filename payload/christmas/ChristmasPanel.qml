import QtQuick
import "../"

// A panel opens like a present. Two satin ribbons cross it with a bow on the knot; the bow pops, the ribbons are
// pulled apart toward the edges and the bow flies off in a puff of gold. Then a sprig of holly settles on the corner
// away from the bar and stays there while the panel is open. On closing the holly folds up, whatever is still in
// flight fades, and the host sends the panel off as a parcel (ChristmasSendOff). Sits over the panel in a
// window-sized layer, never takes input, and is static between the two.
Item {
    id: gift
    enabled: false
    property rect panelRect: Qt.rect(0, 0, width, height)
    property string edge: "center"      // the side the panel comes from
    property string scene: ""
    property int serial: 0
    property bool open: true
    property real cornerRadius: 0
    property string screenName: ""

    readonly property real unit: Scaler.s(1)
    readonly property real band: Math.max(unit * 9, Math.min(unit * 20, Math.min(panelRect.width, panelRect.height) * 0.055))
    // where the ribbons cross: a little off centre, as a ribbon is tied
    readonly property real knotX: panelRect.width * 0.5
    readonly property real knotY: panelRect.height * (edge === "bottom" ? 0.58 : 0.42)
    property real t: 1                  // the unwrapping, 0 tied .. 1 gone
    property real sprigGrowth: 0
    property real veil: 1               // fades the whole layer out while the panel leaves
    readonly property real sheer: Christmas.effectOpacity   // of the wrapping; the holly stays solid

    function play(): void {
        if (!open) return;
        Christmas.panelOpened(screenName);
        fold.stop();
        veil = 1;
        if (!Christmas.motion) { t = 1; sprigGrowth = 1; return; }
        if (!Christmas.allow("unwrap", 260)) {
            if (!unwrap.running) { t = 1; sprigGrowth = 1; }
            return;
        }
        unwrap.restart();
    }
    function leave(): void {
        unwrap.stop();
        Christmas.panelClosed(screenName, panelRect, edge, cornerRadius);
        if (Christmas.motion) fold.restart();
        else veil = 0;
    }
    // A closing panel bumps the serial too, just before `open` drops: look again once both have settled.
    onSerialChanged: Qt.callLater(play)
    onOpenChanged: open ? play() : leave()
    Component.onCompleted: play()

    ParallelAnimation {
        id: fold
        NumberAnimation { target: gift; property: "sprigGrowth"; to: 0; duration: 180; easing.type: Easing.InQuad }
        SequentialAnimation {
            PauseAnimation { duration: 60 }
            NumberAnimation { target: gift; property: "veil"; to: 0; duration: 120; easing.type: Easing.InQuad }
        }
    }

    SequentialAnimation {
        id: unwrap
        PropertyAction { target: gift; property: "t"; value: 0 }
        PropertyAction { target: gift; property: "sprigGrowth"; value: 0 }
        PauseAnimation { duration: 40 }
        ScriptAction { script: sparkle.play() }
        ParallelAnimation {
            NumberAnimation { target: gift; property: "t"; to: 1; duration: 980; easing.type: Easing.Linear }
            SequentialAnimation {
                PauseAnimation { duration: 340 }
                NumberAnimation { target: gift; property: "sprigGrowth"; to: 1; duration: 900; easing.type: Easing.OutCubic }
            }
        }
    }

    // stages of the unwrapping, eased on their own
    function phase(from: real, span: real): real { return Math.max(0, Math.min(1, (t - from) / span)); }
    // the ribbons slide, rather than snap, off the edges
    readonly property real pull: { const k = phase(0.16, 0.64); return k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2; }
    readonly property real pop: phase(0, 0.22)
    readonly property real lift: { const k = phase(0.3, 0.6); return k * k; }

    // ── the ribbons, clipped to the panel ────────────────────────────────────
    Item {
        x: gift.panelRect.x; y: gift.panelRect.y
        width: gift.panelRect.width; height: gift.panelRect.height
        clip: true
        visible: gift.t < 1
        opacity: (1 - gift.phase(0.7, 0.3)) * gift.veil * gift.sheer
        layer.enabled: visible

        component Satin: Rectangle {
            property bool across: true
            gradient: Gradient {
                orientation: across ? Gradient.Vertical : Gradient.Horizontal
                GradientStop { position: 0; color: Christmas.deepRed }
                GradientStop { position: 0.12; color: Qt.alpha(Christmas.gold, 0.9) }
                GradientStop { position: 0.2; color: Christmas.cranberry }
                GradientStop { position: 0.48; color: Qt.lighter(Christmas.cranberry, 1.3) }
                GradientStop { position: 0.8; color: Christmas.cranberry }
                GradientStop { position: 0.88; color: Qt.alpha(Christmas.gold, 0.9) }
                GradientStop { position: 1; color: Christmas.deepRed }
            }
        }
        // each half of each ribbon shrinks back toward the edge it is pulled from
        Satin { across: true; y: gift.knotY - gift.band / 2; height: gift.band
                x: gift.knotX * gift.pull; width: gift.knotX * (1 - gift.pull) }
        Satin { across: true; y: gift.knotY - gift.band / 2; height: gift.band
                x: gift.knotX; width: (parent.width - gift.knotX) * (1 - gift.pull) }
        Satin { across: false; x: gift.knotX - gift.band / 2; width: gift.band
                y: gift.knotY * gift.pull; height: gift.knotY * (1 - gift.pull) }
        Satin { across: false; x: gift.knotX - gift.band / 2; width: gift.band
                y: gift.knotY; height: (parent.height - gift.knotY) * (1 - gift.pull) }
    }

    // ── the bow: pops, then flies up and away ────────────────────────────────
    ChristmasBow {
        readonly property real size: Math.max(gift.unit * 44, Math.min(gift.unit * 86, gift.band * 4.4))
        width: size; height: size * 0.8
        x: gift.panelRect.x + gift.knotX - width / 2 + gift.lift * width * 0.35
        y: gift.panelRect.y + gift.knotY - height * 0.38 - gift.lift * height * 1.4
        visible: gift.t < 1
        rotation: gift.lift * 28
        scale: (gift.pop < 1 ? 1.18 * Math.sin(gift.pop * Math.PI * 0.6) / Math.sin(Math.PI * 0.6) : 1.18 - 0.18 * gift.phase(0.22, 0.1)) * (1 - 0.35 * gift.lift)
        opacity: (1 - gift.lift) * gift.veil * gift.sheer
        layer.enabled: visible
        layer.smooth: true
    }
    Loader {
        id: sparkle
        readonly property real span: gift.unit * 170
        x: gift.panelRect.x + gift.knotX - span / 2
        y: gift.panelRect.y + gift.knotY - span / 2
        width: span; height: span
        active: false
        opacity: gift.veil * gift.sheer
        function play(): void { active = false; active = true; }
        sourceComponent: ChristmasBurst {
            count: 9
            onFinished: sparkle.active = false
            Component.onCompleted: play()
        }
    }

    // ── holly on the far corner ──────────────────────────────────────────────
    ChristmasHolly {
        readonly property real size: gift.unit * 64
        readonly property string corner: gift.edge === "top" ? "bottom-left" : gift.edge === "bottom" ? "top-left"
            : gift.edge === "left" ? "bottom-right" : gift.edge === "right" ? "bottom-left" : "top-left"
        readonly property bool atRight: corner.indexOf("right") >= 0
        readonly property bool atBottom: corner.indexOf("bottom") >= 0
        readonly property real inset: Math.max(gift.unit * 6, gift.cornerRadius * 0.45)
        width: size; height: size
        x: gift.panelRect.x + (atRight ? gift.panelRect.width - inset : inset) - size / 2
        y: gift.panelRect.y + (atBottom ? gift.panelRect.height - inset : inset) - size / 2
        rotation: (atRight ? 1 : -1) * (atBottom ? 1 : -1) * 12 * (1 - gift.sprigGrowth)
        grown: gift.sprigGrowth
        opacity: gift.veil
        visible: gift.sprigGrowth > 0 && gift.veil > 0 && gift.panelRect.width > size * 2
    }
}
