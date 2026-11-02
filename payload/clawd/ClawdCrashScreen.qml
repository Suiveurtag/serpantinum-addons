import QtQuick
import "../"

// A crashed machine, full screen, a pure function of t (seconds since the screen came up), shared by the limit scene
// (ClawdCrash) and the two nightmares (ClawdDream). kind "bsod": the Windows 10 blue screen as it really looks (":(", the
// message, "N% complete" climbing in steps, the QR code, the stop code and what failed). kind "panic": a Linux console,
// kernel log lines running in, then the oops, the call trace and "Kernel panic - not syncing"; the cursor blinks, nothing
// ever comes back; at drmAt the console is replaced by the blue "KERNEL PANIC!" screen (Tux, a big QR code). `nightmare` changes only the words (and the % stalls at 99); `length` is how long the screen plays.
Item {
    id: screen
    property real t: 0
    property string kind: "bsod"
    property bool nightmare: false
    property real seed: 0
    property bool reduced: false

    readonly property bool bsod: kind === "bsod"
    readonly property real length: bsod ? 12.0 : 14.5
    readonly property real drmAt: 9.6                    // the panic: the console gives way to the blue screen with Tux and its QR code
    readonly property real u: height / 1080
    function clamp01(v) { return Math.max(0, Math.min(1, v)); }
    function seg(a, b) { return clamp01((t - a) / (b - a)); }
    function hash(n) { const s = Math.sin(n * 127.1 + screen.seed * 3.3) * 43758.5453; return s - Math.floor(s); }
    function pad(v, n, ch) { let s = String(v); while (s.length < n) s = ch + s; return s; }

    // ── Windows 10 ─────────────────────────────────────────────────────────────────────────────────
    // "N% complete": it climbs in irregular steps over 9 s, then the screen holds; in the nightmare it stops at 99
    readonly property real bar: seg(0.8, 9.8)
    readonly property int percent: Math.min(nightmare ? 99 : 100, Math.floor(100 * (0.55 * bar + 0.45 * Math.floor(bar * 11) / 11)) + (bar >= 1 && !nightmare ? 1 : 0))
    readonly property string stopCode: nightmare ? "CLAWD_DIED_IN_HIS_SLEEP" : "FIVE_HOUR_LIMIT_EXCEEDED"
    readonly property string failed: nightmare ? "dream.sys" : "claude.sys"
    readonly property var qr: {          // a 25x25 code: the three finder squares and a seeded scatter
        const out = [], n = 25;
        for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
            const f = (cx, cy) => { const dx = x - cx, dy = y - cy; if (dx < 0 || dy < 0 || dx > 6 || dy > 6) return -1; const ring = Math.max(Math.abs(dx - 3), Math.abs(dy - 3)); return ring === 3 || ring <= 1 ? 1 : 0; };
            let v = f(0, 0); if (v < 0) v = f(n - 7, 0); if (v < 0) v = f(0, n - 7);
            if (v < 0) { const nearFinder = (x < 8 && y < 8) || (x > n - 9 && y < 8) || (x < 8 && y > n - 9); v = nearFinder ? 0 : hash(y * n + x) > 0.52 ? 1 : 0; }
            if (v === 1) out.push({ x, y });
        }
        return out;
    }

    Item {
        anchors.fill: parent
        visible: screen.bsod
        Rectangle { anchors.fill: parent; color: "#0078D7" }
        readonly property string face: "Segoe UI"
        Text {
            x: screen.width * 0.115; y: screen.height * 0.105
            text: ":("
            color: "white"
            font.family: parent.face; font.weight: Font.Light; font.pixelSize: Math.round(192 * screen.u)
        }
        Text {
            x: screen.width * 0.115; y: screen.height * 0.43
            width: screen.width * 0.62
            wrapMode: Text.WordWrap
            text: screen.nightmare ? "Your PC ran into a problem and it is not going to restart. We're just collecting some error info, and then you'll wake up."
                                   : "Your PC ran into a problem and needs to restart. We're just collecting some error info, and then we'll restart for you."
            color: "white"
            font.family: parent.face; font.pixelSize: Math.round(36 * screen.u)
            lineHeight: 1.12
        }
        Text {
            x: screen.width * 0.115; y: screen.height * 0.43 + 120 * screen.u
            text: screen.percent + "% complete"
            color: "white"
            font.family: parent.face; font.pixelSize: Math.round(36 * screen.u)
        }
        // the QR code, with its quiet zone
        Rectangle {
            id: qrBox
            x: screen.width * 0.115; y: screen.height * 0.43 + 240 * screen.u
            width: 126 * screen.u; height: width
            color: "white"
            readonly property real m: width / 29
            Repeater {
                model: screen.qr
                delegate: Rectangle {
                    required property var modelData
                    x: (modelData.x + 2) * qrBox.m; y: (modelData.y + 2) * qrBox.m
                    width: Math.ceil(qrBox.m); height: width
                    color: "#0078D7"
                }
            }
        }
        Column {
            x: qrBox.x + qrBox.width + 24 * screen.u; y: qrBox.y - 4 * screen.u
            spacing: 10 * screen.u
            Text {
                width: screen.width * 0.5
                wrapMode: Text.WordWrap
                text: "For more information about this issue and possible fixes, visit https://www.windows.com/stopcode"
                color: "white"
                font.family: parent.parent.face; font.pixelSize: Math.round(15 * screen.u)
            }
            Text {
                width: screen.width * 0.5
                wrapMode: Text.WordWrap
                text: "If you call a support person, give them this info:"
                color: "white"
                font.family: parent.parent.face; font.pixelSize: Math.round(15 * screen.u)
            }
            Text {
                width: screen.width * 0.5
                text: "Stop code: " + screen.stopCode + "\nWhat failed: " + screen.failed
                color: "white"
                font.family: parent.parent.face; font.pixelSize: Math.round(15 * screen.u)
            }
        }
    }

    // ── a Linux console ────────────────────────────────────────────────────────────────────────────
    readonly property string why: nightmare ? "Attempted to kill init! exitcode=0x00000009" : "Fatal exception: 5-hour usage limit reached"
    // [seconds the line appears at, text]; the time stamps are added when it is drawn
    readonly property var log: {
        const quiet = [
            "Linux version 6.8.0-quota (clawd@serpantinum) (gcc 13.2.0) #1 SMP PREEMPT_DYNAMIC",
            "Command line: BOOT_IMAGE=/vmlinuz root=/dev/nvme0n1p2 rw quiet splash",
            "x86/fpu: Supporting XSAVE feature 0x001: 'x87 floating point registers'",
            "clawd: pet daemon started, 21x14 sprite, scale 3",
            "claude_quota: window five_hour: 62% used",
            "claude_quota: window five_hour: 81% used",
            "claude_quota: window five_hour: 97% used",
            "claude_quota: window five_hour: 99% used",
            "claude_quota: window five_hour: 100% used, nothing left to give"
        ];
        const oops = [
            "BUG: unable to handle kernel NULL pointer dereference at 0000000000000000",
            "#PF: supervisor read access in kernel mode",
            "#PF: error_code(0x0000) - not-present page",
            "PGD 0 P4D 0",
            "Oops: 0000 [#1] PREEMPT SMP NOPTI",
            "CPU: 3 PID: 4242 Comm: clawd Tainted: G           OE      6.8.0-quota #1",
            "Hardware name: Serpantinum Desktop/Wayland, BIOS 2026.11 11/02/2026",
            "RIP: 0010:rate_limit_check+0x2a/0x80 [claude_quota]",
            "Code: 48 8b 47 08 48 85 c0 74 1e 48 8b 00 48 85 c0 74 15 <48> 8b 00 4c 89 e7 e8 5c 00 00 00 85 c0 75 d4 31 c0 5b 41 5c c3",
            "RSP: 0018:ffffb4a1c1f4be58 EFLAGS: 00010246",
            "RAX: 0000000000000000 RBX: ffff9a3e4a1c2800 RCX: 0000000000000064",
            "RDX: 0000000000000064 RSI: 0000000000000000 RDI: ffff9a3e4a1c2800",
            "Call Trace:",
            " <TASK>",
            " ? __die_body+0x1a/0x60",
            " ? page_fault_oops+0x15a/0x2d0",
            " ? exc_page_fault+0x7f/0x180",
            " five_hour_window_exceeded+0x5c/0x90 [claude_quota]",
            " token_burn+0x131/0x2a0 [claude_quota]",
            " vfs_write+0xf2/0x430",
            " do_syscall_64+0x5b/0xe0",
            " entry_SYSCALL_64_after_hwframe+0x6e/0x76",
            " </TASK>",
            "---[ end trace 0000000000000000 ]---",
            "Kernel panic - not syncing: " + why,
            "Kernel Offset: disabled",
            "---[ end Kernel panic - not syncing: " + why + " ]---"
        ];
        const out = [];
        let stamp = 0.0;
        for (let i = 0; i < quiet.length; i++) { stamp += 0.12 + 0.9 * hash(i + 40) * (i > 3 ? 2.2 : 0.3); out.push({ at: 0.3 + i * 0.32, stamp, text: quiet[i], panic: false }); }
        stamp += 3.1;
        for (let i = 0; i < oops.length; i++) {
            const last = i >= oops.length - 3;
            stamp += 0.0001 * (1 + Math.floor(hash(i + 90) * 9));
            out.push({ at: last ? 8.2 + (i - (oops.length - 3)) * 0.3 : 4.6 + i * 0.12, stamp, text: oops[i], panic: i >= oops.length - 4 });
        }
        return out;
    }
    readonly property real lineH: Math.round(19 * u)
    readonly property int fit: Math.max(8, Math.floor(height / lineH) - 1)
    readonly property int shown: { let n = 0; for (let i = 0; i < log.length; i++) if (log[i].at <= t) n = i + 1; return n; }
    readonly property string mono: typeof ThemeBackend !== "undefined" ? ThemeBackend.fontFamily : "monospace"

    Item {
        anchors.fill: parent
        visible: !screen.bsod
        Rectangle { anchors.fill: parent; color: "#000000" }
        Repeater {
            model: screen.log
            delegate: Text {
                required property var modelData
                required property int index
                readonly property int first: Math.max(0, screen.shown - screen.fit)
                visible: index < screen.shown && index >= first
                x: Math.round(14 * screen.u); y: Math.round(10 * screen.u) + (index - first) * screen.lineH
                text: "[" + screen.pad((11.2 + modelData.stamp).toFixed(6), 12, " ") + "] " + modelData.text
                color: modelData.panic ? (screen.nightmare ? "#ff4b4b" : "#ffffff") : "#c8c8c8"
                font.family: screen.mono; font.pixelSize: Math.round(15 * screen.u)
                font.bold: modelData.panic
            }
        }
        // the cursor, after the last line, blinking
        Rectangle {
            readonly property int row: Math.min(screen.shown, screen.fit)
            visible: screen.shown >= 1 && (screen.reduced || Math.floor(screen.t * 2.2) % 2 === 0)
            x: Math.round(14 * screen.u); y: Math.round(10 * screen.u) + row * screen.lineH + 2 * screen.u
            width: Math.round(9 * screen.u); height: Math.round(15 * screen.u)
            color: "#c8c8c8"
        }
    }

    // ── the blue panic screen: Tux, a big QR code, "Please reboot your computer." ───────────────────
    Item {
        id: drm
        anchors.fill: parent
        visible: !screen.bsod && screen.t >= screen.drmAt
        // the 4:3 picture the screen is drawn in, centred
        readonly property real ph: screen.height
        readonly property real pw: ph * 4 / 3
        readonly property real pl: (screen.width - pw) / 2
        readonly property var tux: ["    .--.", "   |o_o |", "   |:_/ |", "  //   \\ \\", " (|     | )", "/'\\_   _/`\\", "\\___)=(___/"]
        readonly property var tag: [" _", "| |", "| |", "|_|", " _", "(_)"]
        Rectangle { anchors.fill: parent; color: "#0000A8" }
        Text {
            x: drm.pl + drm.pw * 0.0; y: drm.ph * 0.0
            text: drm.tux.join("\n")
            color: "white"; lineHeight: 0.92
            font.family: screen.mono; font.pixelSize: Math.round(drm.ph * 0.037)
        }
        Text {
            x: drm.pl + drm.pw * 0.2; y: drm.ph * 0.0
            text: drm.tag.join("\n")
            color: "white"; lineHeight: 0.92
            font.family: screen.mono; font.pixelSize: Math.round(drm.ph * 0.037)
        }
        Canvas {
            id: qrc
            x: drm.pl + drm.pw * 0.3; y: drm.ph * 0.12
            width: drm.ph * 0.55; height: width
            visible: parent.visible
            onWidthChanged: requestPaint()
            onVisibleChanged: if (visible) requestPaint()
            onPaint: {
                const c = getContext("2d"), n = 89, quiet = 3, m = width / (n + 2 * quiet);
                c.fillStyle = "#ffffff"; c.fillRect(0, 0, width, height);
                c.fillStyle = "#0000A8";
                const finder = (x, y, fx, fy) => { const dx = x - fx, dy = y - fy; if (dx < 0 || dy < 0 || dx > 6 || dy > 6) return -1; const r = Math.max(Math.abs(dx - 3), Math.abs(dy - 3)); return r === 3 || r <= 1 ? 1 : 0; };
                for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
                    let v = finder(x, y, 0, 0); if (v < 0) v = finder(x, y, n - 7, 0); if (v < 0) v = finder(x, y, 0, n - 7);
                    if (v < 0) v = ((x < 8 && y < 8) || (x > n - 9 && y < 8) || (x < 8 && y > n - 9)) ? 0 : screen.hash(y * n + x + 5) > 0.5 ? 1 : 0;
                    if (v === 1) c.fillRect((x + quiet) * m, (y + quiet) * m, Math.ceil(m), Math.ceil(m));
                }
            }
        }
        Column {
            x: drm.pl; width: drm.pw
            y: drm.ph * 0.7
            spacing: drm.ph * 0.045
            Repeater {
                model: ["KERNEL PANIC!", "Please reboot your computer.", screen.nightmare ? "Attempted to kill init!" : "Fatal exception in interrupt"]
                delegate: Text {
                    required property string modelData
                    required property int index
                    width: drm.pw; horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: screen.nightmare && index === 2 ? "#ff6060" : "white"
                    font.family: screen.mono; font.bold: true; font.pixelSize: Math.round(drm.ph * 0.03)
                }
            }
        }
    }
}
