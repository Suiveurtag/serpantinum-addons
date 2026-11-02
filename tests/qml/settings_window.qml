import QtQuick
import Quickshell
import "./"

ShellRoot {
    FloatingWindow {
        id: host
        visible: true
        implicitWidth: 1100
        implicitHeight: 700
        Item {
            id: root
            anchors.fill: parent
            property bool standalone: true
            property bool compact: false
            property bool rtl: false
            Item { id: sidebar; width: root.compact ? 64 : 232; height: parent.height }
            Item {
                id: contentArea
                x: root.rtl ? 0 : sidebar.width
                width: parent.width - sidebar.width
                height: parent.height
            }
        }
        Timer {
            interval: 180; running: true; repeat: true
            property int step: 0
            function expect(value, message) { if (!value) { console.error("SEASONAL_FAIL", step, message); Qt.exit(1); } }
            function checkBounds() {
                expect(seasonalSettingsAtmosphere.parent === contentArea, "effects must belong to the content viewport");
                expect(seasonalSettingsAtmosphere.width === contentArea.width && seasonalSettingsAtmosphere.height === contentArea.height, "effects must follow the content size");
                expect(seasonalSettingsAtmosphere.mapToItem(root, 0, 0).x === contentArea.x, "effects must follow sidebar direction and width");
            }
            onTriggered: {
                switch (step++) {
                case 0:
                    expect(seasonalSettingsAtmosphere.item !== null && Halloween.instances >= 2, "Settings must load the hearth, web and crossings");
                    checkBounds(); root.compact = true; host.implicitWidth = 480; break;
                case 1: checkBounds(); root.rtl = true; break;
                case 2: checkBounds(); Config.setSetting("addonsV2Halloween", false); break;
                case 3:
                    expect(seasonalSettingsAtmosphere.item === null && Halloween.instances === 0 && Halloween.ambientUsers === 0, "OFF must destroy effects and release the clock");
                    Config.setSetting("addonsV2Halloween", true); break;
                case 4: expect(seasonalSettingsAtmosphere.item !== null, "effects must reload on enable"); root.visible = false; break;
                case 5:
                    expect(seasonalSettingsAtmosphere.item === null && Halloween.ambientUsers === 0, "hidden Settings must unload effects");
                    Config.setSetting("general.performance", true); root.visible = true; break;
                case 6:
                    expect(seasonalSettingsAtmosphere.item !== null && Halloween.ambientUsers === 0, "performance mode must retain still effects without the animation clock");
                    contentArea.width = 0; break;
                case 7:
                    expect(seasonalSettingsAtmosphere.item === null, "zero width must unload effects");
                    console.log("SEASONAL_PASS"); Qt.quit();
                }
            }
        }
    }
}
