import QtQuick
import QtQuick.Layouts
import "../"

// Section of a column that grows open and shut. Put the content in a single child (usually a ColumnLayout with `width: parent.width`).
Item {
    id: root
    property bool open: false
    default property alias content: holder.data
    Layout.fillWidth: true
    Layout.preferredHeight: open ? holder.childrenRect.height : 0
    Behavior on Layout.preferredHeight { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
    visible: Layout.preferredHeight > 0.5
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 220 } }
    clip: true
    Item { id: holder; width: root.width; height: childrenRect.height }
}
