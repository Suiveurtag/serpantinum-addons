import QtQuick
import "../../"
import "AddonCalcEngine.js" as Engine

// Typeset view of a calculator expression: stacked fractions, radicals, superscripts, with an optional caret
// and selection. Layout comes from AddonCalcEngine.layout(); this item only draws its primitives.
Item {
    id: view

    property string text: ""
    property real fontSize: 22
    property int cursor: -1
    property int selectionStart: -1
    property int selectionEnd: -1
    property bool showCaret: false
    property bool caretBlink: true
    property bool ghost: true
    property string placeholder: ""
    property int alignment: Qt.AlignRight
    property real minScale: 0.55
    property bool dimmed: false

    property color textColor: ThemeBackend.text
    property color operatorColor: ThemeBackend.blue
    property color functionColor: ThemeBackend.sapphire
    property color constantColor: ThemeBackend.mauve
    property color ansColor: ThemeBackend.peach
    property color errorColor: ThemeBackend.red
    property color mutedColor: ThemeBackend.overlay1
    property color caretColor: ThemeBackend.blue

    readonly property bool showingPlaceholder: view.text === "" && view.placeholder !== ""

    FontMetrics {
        id: fm
        font.family: ThemeBackend.fontFamily
        font.pixelSize: 100
    }

    readonly property var metrics: {
        let family = fm.font.family;
        let cache = ({});
        return {
            w: function (str) {
                if (cache[str] === undefined) cache[str] = fm.advanceWidth(str) / 100;
                return cache[str];
            },
            asc: fm.ascent / 100,
            desc: fm.descent / 100
        };
    }

    readonly property var lay: Engine.layout(view.showingPlaceholder ? view.placeholder : view.text, {
        size: view.fontSize, metrics: view.metrics, ghost: view.ghost
    })

    readonly property real naturalWidth: lay.width
    readonly property real naturalHeight: lay.height
    readonly property real fit: Math.max(view.minScale, Math.min(1, view.width > 0 ? view.width / Math.max(1, lay.width) : 1))

    implicitWidth: lay.width
    implicitHeight: lay.height * fit

    readonly property var caretBox: (view.cursor >= 0 && view.cursor < lay.carets.length) ? lay.carets[view.cursor] : null

    // Horizontal placement: aligned when it fits, otherwise scrolled so the caret stays visible.
    readonly property real overflow: lay.width * fit - view.width
    readonly property real contentX: {
        if (overflow <= 0) return view.alignment === Qt.AlignLeft ? 0 : (view.alignment === Qt.AlignHCenter ? -overflow / 2 : -overflow);
        if (!caretBox) return -overflow;
        let target = view.width * 0.88 - caretBox.x * fit;
        return Math.max(-overflow, Math.min(0, target));
    }

    function indexAt(px, py) {
        let lx = (px - content.x) / view.fit;
        let ly = (py - content.y) / view.fit;
        return Engine.hitTest(view.lay, lx, ly);
    }

    function roleColor(role) {
        switch (role) {
        case "op": return view.operatorColor;
        case "fn": return view.functionColor;
        case "const": return view.constantColor;
        case "ans": return view.ansColor;
        case "error": return view.errorColor;
        case "ghost": return Qt.alpha(view.mutedColor, 0.55);
        case "delim": return Qt.alpha(view.textColor, 0.85);
        }
        return view.textColor;
    }

    clip: true

    Item {
        id: content
        width: view.lay.width
        height: view.lay.height
        transformOrigin: Item.TopLeft
        scale: view.fit
        x: view.contentX
        y: Math.max(0, (view.height - view.lay.height * view.fit) / 2)
        opacity: view.showingPlaceholder ? 0.4 : (view.dimmed ? 0.75 : 1)

        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Repeater {
            model: (view.selectionStart >= 0 && view.selectionEnd > view.selectionStart) ? view.lay.glyphs : []
            delegate: Rectangle {
                required property var modelData
                visible: modelData.s >= view.selectionStart && modelData.e <= view.selectionEnd && modelData.s >= 0
                x: modelData.x - 1
                y: modelData.y + modelData.lineH * 0.08
                width: modelData.w + 2
                height: modelData.lineH * 0.84
                radius: 3
                color: Qt.alpha(view.caretColor, 0.28)
            }
        }

        Repeater {
            model: view.lay.holes
            delegate: Rectangle {
                required property var modelData
                x: modelData.x
                y: modelData.y
                width: modelData.w
                height: modelData.h
                radius: Math.max(2, modelData.w * 0.12)
                color: Qt.alpha(view.mutedColor, 0.12)
                border.width: Math.max(1, view.fontSize * 0.045)
                border.color: Qt.alpha(view.mutedColor, 0.7)
            }
        }

        Repeater {
            model: view.lay.glyphs
            delegate: Text {
                required property var modelData
                x: modelData.x
                y: modelData.y
                height: modelData.lineH
                text: modelData.str
                color: view.roleColor(modelData.role)
                font.family: ThemeBackend.fontFamily
                font.pixelSize: modelData.size
                font.italic: modelData.italic
                renderType: Text.QtRendering
                transform: Scale {
                    origin.y: modelData.lineH / 2
                    yScale: modelData.sy
                }
            }
        }

        Repeater {
            model: view.lay.rules
            delegate: Rectangle {
                required property var modelData
                x: modelData.x
                y: modelData.y
                width: modelData.w
                height: modelData.h
                radius: modelData.h / 2
                color: view.textColor
            }
        }

        Repeater {
            model: view.lay.lines
            delegate: Rectangle {
                required property var modelData
                readonly property real dx: modelData.x2 - modelData.x1
                readonly property real dy: modelData.y2 - modelData.y1
                x: modelData.x1
                y: modelData.y1 - modelData.t / 2
                width: Math.sqrt(dx * dx + dy * dy)
                height: modelData.t
                radius: modelData.t / 2
                antialiasing: true
                color: view.textColor
                transformOrigin: Item.Left
                rotation: Math.atan2(dy, dx) * 180 / Math.PI
            }
        }

        Rectangle {
            id: caret
            visible: view.showCaret && view.caretBox !== null
            width: Math.max(2, view.fontSize * 0.07)
            radius: width / 2
            color: view.caretColor
            x: view.caretBox ? view.caretBox.x - width / 2 : 0
            y: view.caretBox ? view.caretBox.y : 0
            height: view.caretBox ? view.caretBox.h : 0

            Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
            Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
            Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

            SequentialAnimation on opacity {
                id: blink
                running: caret.visible && view.caretBlink
                loops: Animation.Infinite
                PauseAnimation { duration: 520 }
                NumberAnimation { to: 0; duration: 110; easing.type: Easing.InQuad }
                PauseAnimation { duration: 380 }
                NumberAnimation { to: 1; duration: 110; easing.type: Easing.OutQuad }
            }
        }
    }

    // Restart the blink on every move so the caret is solid while typing.
    onCursorChanged: {
        blink.stop();
        caret.opacity = 1;
        if (caret.visible && view.caretBlink) blink.start();
    }
}
