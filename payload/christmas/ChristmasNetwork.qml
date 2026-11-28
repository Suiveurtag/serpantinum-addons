import QtQuick
import QtQuick.Shapes
import "../"

// The network panel strung for Christmas: a garland sags from each hub to each of its cards, and the hub wears a
// wreath with a bow. While connected the bulbs chase from the hub outward, like the data does, a star crowns the
// wreath and a new connection bursts into gold; otherwise the lights only breathe. Follows the cards as they move and
// never takes input.
Item {
    id: web
    enabled: false
    required property var cores
    required property var nodes
    property bool connected: false
    property int generation: 0          // re-reads the repeaters' items as they come and go
    readonly property real unit: Scaler.s(1)
    Connections {
        target: web.nodes
        function onItemAdded() { web.generation++; }
        function onItemRemoved() { web.generation++; }
    }
    Connections {
        target: web.cores
        function onItemAdded() { web.generation++; }
        function onItemRemoved() { web.generation++; }
    }
    property bool clocked: false
    function syncClock(): void {
        const want = visible && Christmas.motion;
        if (want === clocked) return;
        clocked = want;
        Christmas.requestClock(want);
    }
    onVisibleChanged: syncClock()
    Component.onCompleted: syncClock()
    Component.onDestruction: if (clocked) Christmas.requestClock(false)
    Connections { target: Christmas; function onMotionChanged() { web.syncClock(); } }

    onConnectedChanged: if (connected && Christmas.motion) cheer++
    property int cheer: 0

    // ── garlands from hub to card ────────────────────────────────────────────
    Repeater {
        model: web.nodes ? Math.min(16, web.nodes.count) : 0
        delegate: Item {
            id: strand
            required property int index
            anchors.fill: parent
            readonly property var node: { web.generation; return web.nodes.itemAt(index); }
            readonly property var core: { web.generation; return node && node.myParentIdx >= 0 ? web.cores.itemAt(node.myParentIdx) : web.cores.itemAt(0); }
            readonly property point origin: {
                if (!core) return Qt.point(0, 0);
                core.x + core.y + core.scale;       // follow its pose
                return core.mapToItem(web, core.width / 2, core.height / 2);
            }
            readonly property point destination: {
                if (!node) return Qt.point(0, 0);
                node.x + node.y + node.scale;
                return node.mapToItem(web, node.width / 2, node.height / 2);
            }
            readonly property real dx: destination.x - origin.x
            readonly property real dy: destination.y - origin.y
            readonly property real span: Math.max(1, Math.hypot(dx, dy))
            // from the wreath to the card's edge
            readonly property real startInset: core ? core.width * core.scale / 2 + web.unit * 14 : 0
            readonly property real endInset: node ? Math.min(
                node.width * node.scale / (2 * Math.max(0.01, Math.abs(dx / span))),
                node.height * node.scale / (2 * Math.max(0.01, Math.abs(dy / span)))) + web.unit * 2 : 0
            readonly property point from: Qt.point(origin.x + dx / span * startInset, origin.y + dy / span * startInset)
            readonly property point to: Qt.point(destination.x - dx / span * endInset, destination.y - dy / span * endInset)
            readonly property real run: Math.max(0, span - startInset - endInset)
            readonly property point control: Qt.point((from.x + to.x) / 2, (from.y + to.y) / 2 + Math.min(web.unit * 34, run * 0.22))
            readonly property int bulbs: visible ? Math.max(1, Math.min(14, Math.floor(run / (web.unit * 24)))) : 0
            property real lit: Christmas.motion ? 0 : 1
            NumberAnimation on lit { running: Christmas.motion && strand.visible; from: 0; to: 1; duration: 900 + strand.index * 90; easing.type: Easing.InOutSine }
            visible: !!(node && core && node.isLoaded && core.visible && run > web.unit * 8)
            opacity: node && core ? node.opacity * core.opacity : 0
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Qt.alpha(Christmas.holly, 0.85)
                    strokeWidth: web.unit * 1.6
                    startX: strand.from.x; startY: strand.from.y
                    PathQuad { x: strand.to.x; y: strand.to.y; controlX: strand.control.x; controlY: strand.control.y }
                }
            }
            Repeater {
                model: strand.bulbs
                delegate: Item {
                    id: lamp
                    required property int index
                    readonly property real p: (index + 0.5) / Math.max(1, strand.bulbs)
                    readonly property real q: 1 - p
                    readonly property real wave: !Christmas.motion ? 1
                        : web.connected ? Math.pow(0.5 + 0.5 * Math.sin(Christmas.phase * 6 - index * 1.1 + strand.index), 3)
                        : 0.3 + 0.2 * Math.sin(Christmas.phase * 1.4 + index + strand.index * 2)
                    readonly property real power: strand.lit > p ? 0.3 + 0.7 * wave : 0
                    readonly property color tint: Christmas.bulb(index + strand.index)
                    x: q * q * strand.from.x + 2 * q * p * strand.control.x + p * p * strand.to.x
                    y: q * q * strand.from.y + 2 * q * p * strand.control.y + p * p * strand.to.y + web.unit * 3.5
                    Rectangle {
                        anchors.centerIn: parent
                        width: web.unit * 15; height: width; radius: width / 2
                        color: Qt.alpha(lamp.tint, 0.26); opacity: lamp.power
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: web.unit * 5; height: web.unit * 6.5; radius: width / 2
                        color: Qt.tint("#3a423d", Qt.alpha(lamp.tint, lamp.power))
                    }
                }
            }
        }
    }

    // ── a wreath around each hub ─────────────────────────────────────────────
    Repeater {
        model: web.cores ? web.cores.count : 0
        delegate: Item {
            id: wreath
            required property int index
            readonly property var core: { web.generation; return web.cores.itemAt(index); }
            readonly property point center: {
                if (!core) return Qt.point(0, 0);
                core.x + core.y + core.scale;
                return core.mapToItem(web, core.width / 2, core.height / 2);
            }
            readonly property real ring: core ? core.width * core.scale / 2 + web.unit * 7 : 0
            x: center.x; y: center.y
            visible: !!(core && core.visible && ring > web.unit * 20)
            opacity: core ? core.opacity : 0
            property real grown: Christmas.motion ? 0 : 1
            NumberAnimation on grown { running: Christmas.motion && wreath.visible; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }

            // tufts of needles all round, as one path
            function needles(radius: real, reach: real, turn: real): string {
                const count = Math.max(24, Math.min(90, Math.round(radius / web.unit * 0.75)));
                let path = "";
                for (let i = 0; i < count; i++) {
                    const a = i / count * Math.PI * 2 - Math.PI / 2;
                    const x = Math.cos(a) * radius, y = Math.sin(a) * radius;
                    for (const side of [-1, 1]) {
                        const heading = a + Math.PI / 2 + side * (0.8 + 0.25 * Math.sin(i * 2.3 + turn));
                        const long = reach * (0.75 + 0.25 * Math.sin(i * 5.7 + side + turn));
                        path += "M" + x.toFixed(1) + "," + y.toFixed(1) + " l" + (Math.cos(heading) * long).toFixed(1)
                            + "," + (Math.sin(heading) * long).toFixed(1) + " ";
                    }
                }
                return path;
            }
            Item {
                scale: 0.8 + 0.2 * wreath.grown
                opacity: wreath.grown
                rotation: -40 * (1 - wreath.grown)
                Shape {
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Christmas.pine; strokeWidth: web.unit * 3; capStyle: ShapePath.RoundCap; fillColor: "transparent"
                        PathSvg { path: wreath.visible ? wreath.needles(wreath.ring, web.unit * 13, 0) : "" }
                    }
                    ShapePath {
                        strokeColor: Christmas.holly; strokeWidth: web.unit * 1.4; capStyle: ShapePath.RoundCap; fillColor: "transparent"
                        PathSvg { path: wreath.visible ? wreath.needles(wreath.ring, web.unit * 9, 2) : "" }
                    }
                }
                Repeater {      // berries and baubles
                    model: 10
                    Rectangle {
                        required property int index
                        readonly property real a: (index + 0.5) / 10 * Math.PI * 2 - Math.PI / 2
                        width: web.unit * 7; height: width; radius: width / 2
                        x: Math.cos(a) * wreath.ring - width / 2; y: Math.sin(a) * wreath.ring - height / 2
                        color: web.connected ? Christmas.bulb(index) : "#8e2434"
                        opacity: web.connected && Christmas.motion ? 0.75 + 0.25 * Math.sin(Christmas.phase * 2.6 + index * 1.9) : 1
                    }
                }
            }
            ChristmasBow {
                width: Math.max(web.unit * 30, wreath.ring * 0.55); height: width * 0.8
                x: -width / 2; y: wreath.ring - height * 0.4
                scale: wreath.grown
            }
            Text {      // the star, once connected
                text: "★"; color: Christmas.gold
                style: Text.Outline; styleColor: Christmas.paleGold
                font.pixelSize: web.unit * 30
                x: -width / 2; y: -wreath.ring - height * 0.62
                scale: web.connected ? 1 : 0
                rotation: web.connected ? 0 : -140
                Behavior on scale { enabled: Christmas.motion; NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
                Behavior on rotation { enabled: Christmas.motion; NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            }
            Loader {
                id: burst
                width: wreath.ring * 3.4; height: width; x: -width / 2; y: -height / 2
                active: false
                Connections {
                    target: web
                    function onCheerChanged() { burst.active = false; burst.active = true; }
                }
                sourceComponent: ChristmasBurst {
                    count: 18; confetti: true; duration: 1100
                    onFinished: burst.active = false
                    Component.onCompleted: play()
                }
            }
        }
    }
}
