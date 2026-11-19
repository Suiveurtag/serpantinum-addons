import QtQuick
import QtQuick.Window
import "../"

// Mounted inside calendar/CalendarPopup.qml (the Meta+S clock panel). Adds the "Today" column and morphs the
// whole panel into the agenda: the panel size springs to the agenda size while the clock shrinks and fades,
// then the agenda cascades in. Going back plays it in reverse and the native clock replays its intro.
Item {
    id: gl
    required property Item host
    anchors.fill: parent
    function s(v) { return Scaler.s(v); }

    readonly property bool showColumn: !host.vertical
    readonly property real columnWidth: s(292)
    Binding { target: gl.host; property: "addonWidth"; value: gl.showColumn ? gl.columnWidth + gl.s(28) : 0 }

    // Agenda target size: as large as comfortable on this screen.
    readonly property real screenW: Screen.width > 0 ? Screen.width : s(1920)
    readonly property real screenH: Screen.height > 0 ? Screen.height : s(1080)
    readonly property real agendaW: Math.round(Math.max(host.baseWidth, Math.min(screenW - s(64), s(1580))))
    readonly property real agendaH: Math.round(Math.max(host.baseHeight, Math.min(screenH - s(130), s(900))))

    // 0 = clock, 1 = agenda.
    property real morph: 0
    property bool animateMorph: false
    Behavior on morph {
        enabled: gl.animateMorph
        NumberAnimation {
            duration: GCal.agendaOpen ? 760 : 560
            easing.type: Easing.BezierSpline
            easing.bezierCurve: GCal.agendaOpen ? [0.16, 1.0, 0.3, 1.0, 1, 1] : [0.3, 0.0, 0.1, 1.0, 1, 1]
        }
    }
    readonly property real target: GCal.agendaOpen ? 1 : 0
    onTargetChanged: morph = target

    function ease(a, b, x) { const t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t); }
    // Size overshoots a touch on open (spring feel) while the content crossfades.
    readonly property real sizeT: morph
    Binding { target: gl.host; property: "morphWidth"; value: gl.morph > 0.0005 ? gl.host.baseWidth + (gl.agendaW - gl.host.baseWidth) * gl.sizeT : -1 }
    Binding { target: gl.host; property: "morphHeight"; value: gl.morph > 0.0005 ? gl.host.baseHeight + (gl.agendaH - gl.host.baseHeight) * gl.sizeT : -1 }
    Binding { target: gl.host; property: "nativeOpacity"; value: 1 - gl.ease(0.0, 0.42, gl.morph) }
    Binding { target: gl.host; property: "nativeScale"; value: 1 - 0.08 * gl.ease(0, 0.6, gl.morph) }
    Binding { target: gl.host; property: "nativeActive"; value: gl.morph < 0.999 }

    // Opening the dashboard straight into the agenda (Super+G, notification click) skips the morph: the
    // dashboard's own reveal animates it.
    Connections {
        target: gl.host
        function onVisibleChanged() {
            gl.animateMorph = false;
            // The dashboard flips its content off/on when opening: only a real close resets to the clock.
            if (!gl.host.visible && !DashboardController.isVisible) GCal.agendaOpen = false;
            gl.morph = gl.target;
            Qt.callLater(() => gl.animateMorph = true);
        }
    }
    Component.onCompleted: { morph = target; Qt.callLater(() => animateMorph = true); }

    GCalTodayColumn {
        visible: gl.showColumn && gl.host.nativeOpacity > 0.001
        active: gl.host.visible && gl.host.nativeActive
        x: gl.host.nativeFrame.x + gl.host.nativeFrame.width - gl.columnWidth - gl.s(28)
        y: gl.host.nativeFrame.y + gl.s(28)
        width: gl.columnWidth
        height: gl.host.nativeFrame.height - gl.s(56)
        opacity: gl.host.nativeOpacity
        scale: gl.host.nativeScale
        accent: {
            const h = GCal.now ? new Date(GCal.now).getHours() : 12;
            if (h >= 5 && h < 12) return ThemeBackend.yellow;
            if (h >= 12 && h < 17) return ThemeBackend.teal;
            if (h >= 17 && h < 21) return ThemeBackend.pink;
            return ThemeBackend.mauve;
        }
    }

    Loader {
        id: agendaLoader
        anchors.fill: parent
        active: gl.morph > 0.001 || GCal.agendaOpen
        visible: gl.morph > 0.2
        sourceComponent: GCalAgenda {
            reveal: gl.ease(0.28, 1.0, gl.morph)
            shown: gl.morph > 0.999 && gl.host.visible
        }
    }
}
