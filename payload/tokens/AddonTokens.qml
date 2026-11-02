import QtQuick
import QtQuick.Layouts
import Quickshell
import "../reusables"
import "../widgets"
import "../bar"
import "../"

// Direct ShellRoot child: adds "tokens" to the native widget registry (Widgets editor) and bar module registry (Settings → Bar → Modules).
Scope {
    // "New / from the addon" marker: the animated outline of the v1 topbar-button-effects around the button that places the widget.
    Component {
        id: toolbarButton
        ColumnLayout {
            id: itemCol
            property var typeData: null
            property var redactor: null
            // Once hovered or used, the outline never comes back (the id is kept in settings.json; a fresh install clears it).
            property bool seen: {
                const ids = Config.getSetting("addonsV2SeenNew", []);
                return Array.isArray(ids) && ids.indexOf("tokens") !== -1;
            }
            function markSeen() {
                if (seen) return;
                seen = true;
                const ids = Config.getSetting("addonsV2SeenNew", []);
                Config.setSetting("addonsV2SeenNew", (Array.isArray(ids) ? ids : []).concat(["tokens"]));
            }
            spacing: Scaler.s(6)
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Scaler.s(52)

            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Scaler.s(48)
                Layout.preferredHeight: Scaler.s(48)
                IconButton {
                    anchors.fill: parent
                    size: Scaler.s(48)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonIcon: itemCol.typeData && itemCol.typeData.icon ? itemCol.typeData.icon : ""
                    iconFontSize: Scaler.s(22)
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.text
                    onClicked: {
                        itemCol.markSeen();
                        if (itemCol.redactor && itemCol.typeData) itemCol.redactor.addWidget(itemCol.typeData.id);
                    }
                }
                HoverHandler { onHoveredChanged: if (hovered) itemCol.markSeen() }
                AddonButtonEffect {
                    anchors.fill: parent
                    active: !itemCol.seen
                    cornerRadius: ThemeBackend.borderRadius
                    palette: [ThemeBackend.blue, ThemeBackend.mauve, ThemeBackend.pink, ThemeBackend.peach, ThemeBackend.teal]
                }
            }
            Text {
                text: itemCol.typeData && itemCol.typeData.name ? itemCol.typeData.name : ""
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(11)
                font.bold: true
                color: ThemeBackend.subtext0
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Scaler.s(52)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                Layout.bottomMargin: Scaler.s(2)
            }
        }
    }

    Component.onCompleted: {
        BarModuleRegistry.registerModule("tokens", {
            name: qsTr("AI Tokens"),
            icon: Qt.resolvedUrl("assets/token.svg").toString(),
            defaultVariant: "default",
            face: "../tokens/TokensBarFace.qml"
        });
        WidgetRegistry.registerType("tokens", {
            name: qsTr("AI Tokens"),
            icon: String.fromCodePoint(0xF0A2C),
            toolbarComponent: toolbarButton,
            defaultWidth: 360,
            defaultHeight: 150,
            defaultVariant: "default",
            variants: { "default": { file: "../tokens/TokensFace.qml", icon: "1", label: qsTr("Default") } }
        });
    }
    Component.onDestruction: {
        BarModuleRegistry.unregisterModule("tokens");
        WidgetRegistry.unregisterType("tokens");
    }
}
