import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"

// Sidebar footer button, cloned from the upstream green "Update available" one.
ClickButton {
    id: btn
    property var popup: null

    visible: AddonsUpdater.attention
    Layout.fillWidth: true
    implicitHeight: popup ? popup.s(38) : 38
    cornerRadius: ThemeBackend.borderRadius
    buttonText: (popup && popup.compact) ? "" : (AddonsUpdater.needsReinstall ? "Reinstall addons" : "Addons update")
    buttonIcon: "󰏗"
    iconFontSize: popup ? popup.s(16) : 16
    textFontSize: popup ? popup.s(13) : 13
    accentColor: ThemeBackend.peach
    textColor: ThemeBackend.crust
    onClicked: if (popup) popup.gotoTab("about")
}
