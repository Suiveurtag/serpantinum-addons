import QtQuick
import Quickshell
import "../"

Scope {
    id: surface

    required property string name
    required property string kind
    required property var screen
    required property rect bounds
    property real radius: 0
    property bool shown: true
    property string publishedKey: ""

    readonly property var record: {
        if (!SnowHush.enabled || !shown || !screen || bounds.width < 32 || bounds.height < 14)
            return null;
        return {
            id: screen.name + "/" + kind + "/" + name,
            output: screen.name,
            kind: kind,
            x: Math.round(bounds.x), y: Math.round(bounds.y),
            w: Math.round(bounds.width), h: Math.round(bounds.height),
            radius: Math.round(radius)
        };
    }

    function publish(): void {
        const key = surface.record ? surface.record.id : "";
        if (surface.publishedKey && surface.publishedKey !== key)
            SnowHush.removeSurface(surface.publishedKey);
        if (surface.record) SnowHush.setSurface(key, surface.record);
        surface.publishedKey = key;
    }

    onRecordChanged: publish()
    Component.onCompleted: publish()
    Component.onDestruction: if (publishedKey) SnowHush.removeSurface(publishedKey)
}
