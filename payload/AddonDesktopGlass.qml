pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "./"

Item {
    id: root
    readonly property bool enabled: Config.getSetting("addonsV2DesktopGlass", false) && ThemeBackend.liquidGlass
        && Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== "" && Quickshell.env("SERPANTINUM_STANDALONE") !== "1"
    property string moduleUrl: ""
    onEnabledChanged: if (!enabled) moduleUrl = ""
    Loader {
        active: root.enabled
        sourceComponent: Component {
            Item {
                Process {
                    id: build
                    running: true
                    command: ["python3", (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/serpantinum-addons-v2/scripts/desktop_glass/build.py"]
                    stdout: StdioCollector { id: output }
                    stderr: StdioCollector { id: errors }
                    onExited: function(code) {
                        if (code === 0 && root.enabled) root.moduleUrl = "file://" + output.text.trim();
                        else if (code !== 0) console.warn("Desktop glass capture unavailable:", errors.text);
                    }
                }
            }
        }
    }
}
