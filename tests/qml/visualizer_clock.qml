import QtQuick
Item {
    property bool settling: true
    FrameAnimation {
        id: levelAnimation
        property real pendingTime: 0.0
        running: root.settling && root.visible
        onTriggered: {
            levelAnimation.pendingTime += frameTime;
            if (levelAnimation.pendingTime + frameTime / 2 < 1 / 60) return;
            let elapsed = levelAnimation.pendingTime;
            levelAnimation.pendingTime = 0.0;

            let target = root.targets;
        }
    }
}
