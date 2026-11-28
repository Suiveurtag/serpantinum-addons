import QtQuick
import Quickshell

ShellRoot {
    FloatingWindow {
        id: window
        implicitWidth: 32; implicitHeight: 32; visible: true
        property bool currentConn: true
        property bool showInfoView: true
        property bool currentPower: true
        property bool activeMute: false
        property int networkFirst: 0
        property int volumeFirst: 0
        property int networkPaused: 0
        property int volumePaused: 0
        Item {
            id: coreContainer
            property bool showPassword: false
            property bool isMyDisconnecting: false
            Rectangle {
                    property real pulseOp: 0.0
                    property real pulseSc: 1.0
                    property int changes: 0
                    onPulseOpChanged: changes++
                    opacity: ((window.currentConn || coreContainer.showPassword) && window.showInfoView && window.currentPower && !coreContainer.isMyDisconnecting) ? pulseOp : 0.0
                    scale: pulseSc
                    Timer {
                        interval: 45
                        running: window.visible && parent.opacity > 0.01
                        repeat: true
                        onTriggered: {
                            var time = Date.now() / 1000;
                            parent.pulseOp = 0.3 + Math.sin(time * 2.5) * 0.15;
                            parent.pulseSc = 1.02 + Math.cos(time * 3.0) * 0.02;
                        }
                    }
            }
        }
        Rectangle {
                            property real pulseOp: 0.0
                            property real pulseSc: 1.0
                            property int changes: 0
                            onPulseOpChanged: changes++
                            opacity: window.activeMute ? 0.0 : pulseOp
                            scale: pulseSc
                            Timer {
                                interval: 45
                                running: window.visible && (parent.opacity > 0.01 || !window.activeMute)
                                repeat: true
                                onTriggered: {
                                    var time = Date.now() / 1000;
                                    parent.pulseOp = 0.12 + Math.sin(time * 2.5) * 0.05;
                                    parent.pulseSc = 1.008 + Math.cos(time * 3.0) * 0.005;
                                }
                            }
        }
        Timer { interval: 900; running: true; onTriggered: {
            window.networkFirst = networkPulse.changes; window.volumeFirst = volumePulse.changes;
            window.currentConn = false; window.activeMute = true;
        } }
        Timer { interval: 1350; running: true; onTriggered: {
            window.networkPaused = networkPulse.changes - window.networkFirst;
            window.volumePaused = volumePulse.changes - window.volumeFirst;
            window.currentConn = true; window.activeMute = false;
        } }
        Timer { interval: 2200; running: true; onTriggered: {
            console.warn("PULSE_RESULT", window.networkFirst, window.networkPaused,
                         networkPulse.changes - window.networkFirst - window.networkPaused,
                         window.volumeFirst, window.volumePaused,
                         volumePulse.changes - window.volumeFirst - window.volumePaused);
        } }
    }
}
