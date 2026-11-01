import QtQuick
import Quickshell
import "../widgets"
import "../bar"
import "../"

// Direct ShellRoot child: adds "tokens" to the native widget registry (Widgets editor) and bar module registry (Settings → Bar → Modules).
Scope {
    Component.onCompleted: {
        BarModuleRegistry.registerModule("tokens", {
            name: qsTr("AI Tokens"),
            icon: "󰧑",
            defaultVariant: "default",
            face: "../tokens/TokensBarFace.qml"
        });
        WidgetRegistry.registerType("tokens", {
            name: qsTr("AI Tokens"),
            icon: String.fromCodePoint(0xF0A2C),
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
