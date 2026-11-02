import QtQuick
import "../"

Item {
    id: ticker
    required property var brain
    required property var engine
    readonly property var action: brain.ticker || ({})
    width: Math.min(340, engine.width - 28, tickerVerb.implicitWidth + tickerTarget.implicitWidth + 54)
    height: 28
    x: Math.max(14, Math.min(engine.width - width - 14, brain.head.x - width / 2))
    y: Math.max(14, brain.head.top - height - 10)
    visible: !!brain.ticker && !brain.message && !brain.suspended // silent work cue: kept under DND
    CapriPlate {
        anchors.fill: parent
        fillColor: "#7d3af5"
        transform: Translate {
            x: 3
            y: 3
        }
    }
    CapriPlate {
        anchors.fill: parent
    }
    Row {
        id: row
        x: 9
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Rectangle {
            width: 6
            height: 6
            anchors.verticalCenter: parent.verticalCenter
            color: ticker.action.error ? "#ff245d" : ticker.action.thinking ? "#7d3af5" : "#36ff73"
            SequentialAnimation on opacity {
                running: ticker.visible && Capri.animationEnabled
                loops: Animation.Infinite
                NumberAnimation {
                    to: .25
                    duration: ticker.action.thinking ? 700 : 350
                }
                NumberAnimation {
                    to: 1
                    duration: ticker.action.thinking ? 700 : 350
                }
            }
        }
        Text {
            id: tickerVerb
            text: (ticker.action.verb || "").toUpperCase() + (ticker.action.thinking ? "…" : "")
            color: ticker.action.thinking ? "#fcf2f6" : "#36ff73"
            font.family: ThemeBackend.fontFamily
            font.pixelSize: 11
            font.bold: true
        }
        Text {
            id: tickerTarget
            width: Math.min(200, Math.max(0, ticker.width - x - 12))
            text: ticker.action.target || ""
            textFormat: Text.PlainText
            color: "#d6c5d0"
            font.family: ThemeBackend.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }
}
