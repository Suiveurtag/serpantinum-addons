import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"
import "../reusables/guide"

// A bare SettingsRow around the card: Settings search finds "clawd" and its highlight lands on the card.
SettingsRow {
    id: root
    required rootObj
    property var viewport: null
    settingId: "addons_clawd"; searchTab: "addons"
    searchKeywords: "clawd claude code pet mascot desktop companion compagnon mascotte pixel scale size taille speed vitesse sleep sommeil summon windows fenêtres perch follow suivre cursor curseur screens écrans Super Shift L ipc call clawd toggle"
    title: "Clawd"; description: "Claude Code's pixel mascot on your desktop"; icon: "󰚩"; showIcon: false
    baseColor: "transparent"; hoverColor: "transparent"
    horizontalPadding: 0; verticalPadding: 0; spacing: 0; controlSpacing: 0
    customLeftContent: ClawdCard {
        objectName: "clawdCard"
        rootObj: root.rootObj
        highlight: root.highlightFlash
        consumerVisible: !root.viewport || (root.viewport.width > 0 && root.viewport.height > 0
            && root.y + root.height > root.viewport.contentY && root.y < root.viewport.contentY + root.viewport.height)
    }
}
