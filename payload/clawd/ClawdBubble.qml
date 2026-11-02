import QtQuick
import "../"

// One terminal line in a ╭─╮ box above Clawd, themed like his Settings card. A click raises that session's terminal and closes it.
Item {
    id: bubble
    required property Item anchor
    readonly property string text: Clawd.bubble ? Clawd.bubble.text : ""
    readonly property int cells: text.length + 4
    readonly property real cw: cell.advanceWidth
    readonly property real lh: metrics.height
    // own x/y (not anchors): the overlay mask Region only follows its item's own geometry
    x: Math.round(Math.max(0, Math.min((parent ? parent.width : 0) - width, anchor.x + (anchor.width - width) / 2)))
    y: Math.round(Math.max(0, anchor.y - height - Scaler.s(4)))
    width: Math.ceil(cells * cw)
    height: Math.ceil(3 * lh)

    TextMetrics { id: cell; text: "─"; font: label.font }
    FontMetrics { id: metrics; font: label.font }
    Rectangle { anchors.fill: parent; anchors.margins: bubble.cw / 2; radius: bubble.lh / 2; color: Qt.alpha(ThemeBackend.mantle, 0.94) }
    Text {
        font: label.font
        color: ThemeBackend.peach
        textFormat: Text.PlainText
        lineHeightMode: Text.FixedHeight; lineHeight: bubble.lh
        text: "╭" + "─".repeat(bubble.cells - 2) + "╮\n│" + " ".repeat(bubble.cells - 2) + "│\n╰" + "─".repeat(bubble.cells - 2) + "╯"
    }
    Text {
        id: label
        x: 2 * bubble.cw; y: bubble.lh
        font.family: ThemeBackend.fontFamily; font.pixelSize: Math.round(Scaler.s(12))
        color: ThemeBackend.text
        textFormat: Text.PlainText
        text: bubble.text
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { Clawd.focus(Clawd.bubble.key); Clawd.dismiss(); } }
}
