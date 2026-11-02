import QtQuick
import "../"

// One animation strip from sprites/clawd.json. Set running: false and bind frame to drive it from another clock.
Item {
    id: sprite
    property string animation: "idle"
    property bool mirrored: false
    property bool reverse: false
    property real speed: 1         // playback rate: the clip's fps times this
    property real pixelScale: Clawd.unit(clip)
    property bool running: true
    property int frame: 0
    readonly property var size: clip && clip.w && clip.h ? { w: clip.w, h: clip.h } : Clawd.manifest ? Clawd.manifest.frame : null  // specials have their own canvas
    readonly property var clip: Clawd.manifest && Clawd.manifest.animations[animation] || null
    readonly property int frames: clip ? Math.max(1, clip.frames) : 1
    property bool done: false
    signal finished()

    implicitWidth: size ? Math.round(size.w * pixelScale) : 0
    implicitHeight: size ? Math.round(size.h * pixelScale) : 0

    function restart() {
        if (!running) return;
        frame = 0;
        done = false;
        ticker.restart();
    }
    onAnimationChanged: restart()
    onReverseChanged: restart()

    Image {
        anchors.fill: parent
        visible: !!sprite.clip
        source: sprite.clip ? Qt.resolvedUrl("sprites/" + sprite.clip.file) : ""
        sourceClipRect: sprite.size ? Qt.rect((sprite.reverse ? sprite.frames - 1 - Math.min(sprite.frame, sprite.frames - 1) : Math.min(sprite.frame, sprite.frames - 1)) * sprite.size.w, 0, sprite.size.w, sprite.size.h) : Qt.rect(0, 0, 0, 0)
        smooth: false
        mipmap: false
        transform: Scale { origin.x: sprite.width / 2; xScale: sprite.mirrored ? -1 : 1 }
    }

    Timer {
        id: ticker
        interval: sprite.clip ? Math.max(16, Math.round(1000 / (sprite.clip.fps || 8) / (sprite.speed > 0 ? sprite.speed : 1))) : 125
        repeat: true
        running: sprite.running && sprite.visible && !!sprite.clip && !sprite.done && !(sprite.clip.loop && sprite.frames < 2)
        onTriggered: {
            if (sprite.frame < sprite.frames - 1) sprite.frame++;
            else if (sprite.clip.loop) sprite.frame = 0;
            else { sprite.done = true; sprite.finished(); }
        }
    }
}
