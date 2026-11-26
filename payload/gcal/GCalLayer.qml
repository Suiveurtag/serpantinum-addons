import QtQuick
import "../"

// Mounted inside calendar/CalendarPopup.qml (the Meta+S clock panel). Adds the day stream under the clock and morphs the
// panel into the agenda while the clock fades out.
Item {
    id: gl
    required property Item host
    anchors.fill: parent
    function s(v) { return Scaler.s(v); }

    readonly property bool showStream: !host.vertical && GCal.enabled && GCal.previewEnabled
    readonly property real streamHeight: s(236)
    Binding { target: gl.host; property: "addonHeight"; value: gl.showStream ? gl.streamHeight : 0 }

    // Agenda target size: as large as comfortable on this screen.
    readonly property real screenW: Screen.width > 0 ? Screen.width : s(1920)
    readonly property real screenH: Screen.height > 0 ? Screen.height : s(1080)
    readonly property real agendaW: Math.round(Math.min(screenW - s(64), s(1580)))
    readonly property real agendaH: Math.round(Math.min(screenH - s(130), s(900)))

    // 0 = clock, 1 = agenda.
    property real morph: 0
    property bool animateMorph: false
    Behavior on morph {
        enabled: gl.animateMorph && !GCal.reducedMotion
        NumberAnimation {
            duration: GCal.agendaOpen ? 360 : 300
            easing.type: Easing.BezierSpline
            easing.bezierCurve: GCal.agendaOpen ? [0.16, 1.0, 0.3, 1.0, 1, 1] : [0.25, 0.65, 0.35, 1.0, 1, 1]
        }
    }
    readonly property real target: GCal.agendaOpen ? 1 : 0
    onTargetChanged: morph = target

    function ease(a, b, x) { const t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t); }
    Binding { target: gl.host; property: "morphWidth"; value: gl.morph > 0.0005 ? gl.host.baseWidth + (gl.agendaW - gl.host.baseWidth) * gl.morph : -1 }
    Binding { target: gl.host; property: "morphHeight"; value: gl.morph > 0.0005 ? gl.host.baseHeight + (gl.agendaH - gl.host.baseHeight) * gl.morph : -1 }
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

    // The weather arrows (and Left / Right) move the day shown by the weather; the calendar follows them while it
    // is on today's date or already on the weather's day, and stays put once another day was picked by hand.
    property int weatherDay: 0
    // Whenever the panel opens, the weather and the calendar both start on today (the native panel would
    // keep the weather on its last day).
    function resetToToday() {
        const item = gl.host.nativeItem;
        if (item && item.targetWeatherView !== undefined) {
            item.targetWeatherView = 0;
            item.weatherView = 0;
            item.dayOpacity = 1;
            item.dayOffset = 0;
        }
        gl.weatherDay = 0;
        GCal.selectedDay = null;
    }
    Connections {
        target: gl.host
        function onVisibleChanged() { if (gl.host.visible) Qt.callLater(gl.resetToToday); }
        function onNativeItemChanged() { if (gl.host.visible) Qt.callLater(gl.resetToToday); }
    }
    Connections {
        target: gl.host.nativeItem
        ignoreUnknownSignals: true
        function onTargetWeatherViewChanged() {
            const next = gl.host.nativeItem.targetWeatherView;
            const previous = gl.weatherDay;
            gl.weatherDay = next;
            if (!GCal.enabled || next === previous) return;
            const selected = GCal.selectedDay;
            if (selected === null || GCal.sameDay(selected, GCal.addDays(GCal.today, previous)))
                GCal.selectDay(GCal.addDays(GCal.today, next));
        }
    }

    GCalDayStream {
        visible: gl.showStream && gl.host.nativeOpacity > 0.001
        active: gl.showStream && gl.host.visible && gl.host.nativeActive
        x: gl.host.nativeFrame.x
        y: gl.host.nativeFrame.y + gl.host.nativeFrame.height - gl.streamHeight
        width: gl.host.nativeFrame.width
        height: gl.streamHeight
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
        anchors.centerIn: parent
        width: gl.agendaW
        height: gl.agendaH
        active: gl.morph > 0.001 || GCal.agendaOpen
        visible: gl.morph > 0.38
        enabled: GCal.agendaOpen && DashboardController.isVisible && gl.morph > 0.999
        sourceComponent: GCalAgenda {
            reveal: gl.ease(0.42, 1.0, gl.morph)
            shown: DashboardController.isVisible && gl.morph > 0.999 && gl.host.visible
        }
    }
}
