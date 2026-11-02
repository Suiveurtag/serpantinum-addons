import QtQuick
import Quickshell
import "../"

// Right-click menu, drawn as a terminal box. Escape or an outside click (the overlay's focus grab) closes it.
FocusScope {
    id: menu
    required property var pet
    property Item anchor: null
    property int current: 0
    readonly property int cols: 12
    readonly property var rows: (!pet.dead && Clawd.chat ? ["talk"] : []).concat([pet.dead ? "revive" : pet.asleep ? "wake" : "sleep", "dreams", "hide", "settings"])
    readonly property color accent: ThemeBackend.primary
    width: box.implicitWidth
    height: box.implicitHeight
    x: anchor && parent ? Math.max(8, Math.min(parent.width - width - 8, anchor.x + (anchor.width - width) / 2)) : 0
    y: anchor ? (anchor.y - height - 8 >= 8 ? anchor.y - height - 8 : anchor.y + anchor.height + 8) : 0

    onVisibleChanged: if (visible) { current = 0; forceActiveFocus(); }
    Keys.onEscapePressed: pet.menuOpen = false
    Keys.onUpPressed: current = (current + rows.length - 1) % rows.length
    Keys.onDownPressed: current = (current + 1) % rows.length
    Keys.onReturnPressed: choose(current)
    Keys.onEnterPressed: choose(current)

    function choose(i) {
        pet.menuOpen = false;
        if (rows[i] === "talk") pet.chatOpen = true;
        else if (rows[i] === "sleep") pet.sleep();
        else if (rows[i] === "wake") pet.wake();
        else if (rows[i] === "dreams") { pet.journalTab = "dreams"; pet.journalOpen = true; }
        else if (rows[i] === "revive") pet.revive();
        else if (rows[i] === "hide") Config.setSetting("addonsV2Clawd", false);
        else Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/settings.sh", "open", "addons", "addons_general"]);
    }

    FontMetrics { id: metrics; font.family: ThemeBackend.fontFamily; font.pixelSize: 14 }
    Rectangle {
        // fills inside the glyph border: box-drawing strokes sit mid-cell
        anchors { fill: parent; leftMargin: metrics.averageCharacterWidth / 2; rightMargin: metrics.averageCharacterWidth / 2
            topMargin: metrics.height / 2; bottomMargin: metrics.height / 2 }
        color: ThemeBackend.base
        radius: 3
    }
    Column {
        id: box
        Text {
            text: "╭─ ✻ clawd " + "─".repeat(menu.cols - 8) + "╮"
            color: menu.accent
            font: metrics.font
        }
        Repeater {
            model: menu.rows
            Text {
                required property string modelData
                required property int index
                readonly property bool active: menu.current === index
                text: "│ " + (active ? "> " : "  ") + modelData + " ".repeat(Math.max(0, menu.cols - 2 - modelData.length)) + " │"
                color: active ? menu.accent : ThemeBackend.subtext0
                font: metrics.font
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: menu.current = parent.index
                    onClicked: menu.choose(parent.index)
                }
            }
        }
        Text {
            text: "╰" + "─".repeat(menu.cols + 2) + "╯"
            color: menu.accent
            font: metrics.font
        }
    }
}
