import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"
import "../reusables/guide"

// A bare SettingsRow around the card: Settings search finds "christmas" and its highlight lands on the card.
SettingsRow {
    id: root
    required rootObj
    settingId: "addons_christmas"; searchTab: "addons"
    searchKeywords: "christmas noël noel xmas festive fêtes lights guirlande lumières garland holly houx gift cadeau ribbon ruban bauble boule frost givre sparkle étincelles seasonal saisonnier december décembre ipc call christmas toggle"
    title: "Christmas"; description: "Fairy lights, ribbons and holly across the shell"; icon: "󰉿"; showIcon: false
    baseColor: "transparent"; hoverColor: "transparent"
    horizontalPadding: 0; verticalPadding: 0; spacing: 0; controlSpacing: 0
    customLeftContent: ChristmasCard {
        objectName: "christmasCard"
        rootObj: root.rootObj
        highlight: root.highlightFlash
    }
}
