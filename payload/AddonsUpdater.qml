pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Serpantinum Addons release state. Mirrors upstream singletons/system/Updater.qml:
// one Process, a startup delay, an hourly Timer. The check itself is
// scripts/addons_release.py, which prints one JSON line.
QtObject {
    id: root

    property string state: "unknown"
    property string localVersion: ""
    property string remoteVersion: ""
    property string serpantinumVersion: ""
    property string compat: "unknown"
    property string notesUrl: ""
    property string error: ""
    property string checkedAt: ""
    property bool checking: false

    readonly property bool updateAvailable: state === "available"
    readonly property bool needsReinstall: state === "reinstall_needed"
    readonly property bool attention: updateAvailable || needsReinstall

    readonly property var knownStates: ["not_installed", "reinstall_needed", "error", "serpantinum_outdated", "incompatible", "available", "dev", "up_to_date"]
    readonly property var knownCompat: ["ok", "too_old", "newer_than_tested", "unknown"]
    // The only arguments launch() will ever pass to install.sh.
    readonly property var allowedArgs: ["update", "reinstall", "--focus uninstall"]

    readonly property string installerBase: "https://raw.githubusercontent.com/Suiveurtag/serpantinum-addons/"
    // Pinned to the release tag when a version is known (validated, so nothing can be injected); main otherwise.
    readonly property string installerRef: {
        let ok = /^[0-9]+(\.[0-9]+)*$/;
        if (ok.test(root.remoteVersion)) return "v" + root.remoteVersion;
        if (ok.test(root.localVersion)) return "v" + root.localVersion;
        return "main";
    }
    readonly property string installerUrl: root.installerBase + root.installerRef + "/install/install.sh"
    readonly property string localInstaller: "$HOME/.local/share/serpantinum-addons-v2/source/install/install.sh"

    property bool forceNext: false

    function check(force) {
        if (proc.running) return;
        root.forceNext = force === true;
        root.checking = true;
        proc.running = true;
    }

    function fail(message) {
        root.state = "error";
        root.error = message;
        root.checking = false;
    }

    function apply(text) {
        let out = text ? text.trim() : "";
        if (out === "") {
            root.fail("no answer from the release checker");
            return;
        }
        let data;
        try {
            data = JSON.parse(out);
        } catch (e) {
            root.fail("unreadable answer from the release checker");
            return;
        }
        if (data === null || typeof data !== "object" || root.knownStates.indexOf(data.state) === -1) {
            root.fail("unexpected answer from the release checker");
            return;
        }
        root.localVersion = data.local ? String(data.local) : "";
        root.remoteVersion = data.remote ? String(data.remote) : "";
        root.serpantinumVersion = data.serpantinum ? String(data.serpantinum) : "";
        root.compat = root.knownCompat.indexOf(data.compat) !== -1 ? data.compat : "unknown";
        root.notesUrl = data.notes_url ? String(data.notes_url) : "";
        root.checkedAt = data.checked_at ? String(data.checked_at) : "";
        root.error = data.error ? String(data.error) : "";
        root.state = data.state;
        root.checking = false;
    }

    // Shell command run inside the terminal. Falls back to the local copy of the
    // installer when curl cannot fetch the script (offline, GitHub down).
    function installCommand(args) {
        if (root.allowedArgs.indexOf(args) === -1) return "";
        return 'if s=$(curl -fsSL ' + root.installerUrl + ') && [ -n "$s" ]; then bash -c "$s" _ ' + args + '; '
            + 'elif [ -f "' + root.localInstaller + '" ]; then bash "' + root.localInstaller + '" ' + args + '; '
            + 'else src=$(python3 "$HOME/.local/share/serpantinum-addons-v2/scripts/addons_release.py" source); '
            + 'if [ -n "$src" ] && [ -f "$src/addons.py" ]; then echo "Using local checkout: $src"; python3 "$src/addons.py" ' + args + '; '
            + 'else echo "Installer unavailable: GitHub unreachable and no local copy found."; '
            + 'echo "Run: bash -c \\"\\$(curl -fsSL ' + root.installerBase + 'main/install/install.sh)\\""; fi; fi';
    }

    function terminalCommand(args) {
        let inner = root.installCommand(args);
        if (inner === "") return "";
        return "if command -v kitty >/dev/null 2>&1; then kitty --hold bash -c '" + inner + "'; "
            + "else ${TERM:-xterm} -hold -e bash -c '" + inner + "'; fi";
    }

    // args must be one of allowedArgs; anything else is refused.
    function launch(args) {
        let cmd = root.terminalCommand(args);
        if (cmd === "") return false;
        Quickshell.execDetached(["bash", "-c", cmd]);
        return true;
    }

    property Timer startupTimer: Timer {
        interval: 2500
        repeat: false
        running: true
        onTriggered: root.check(false)
    }

    property Timer periodicTimer: Timer {
        interval: 60 * 60 * 1000
        repeat: true
        running: true
        onTriggered: root.check(false)
    }

    property Process proc: Process {
        running: false
        command: ["python3", Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/addons_release.py", "check"].concat(root.forceNext ? ["--force"] : [])
        stdout: StdioCollector {
            onStreamFinished: root.apply(this.text)
        }
        onExited: root.checking = false
    }
}
