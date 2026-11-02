import QtQuick
import QtMultimedia
import "../"
import "js/sounds.mjs" as Sounds

// Her sounds (capri-desktop voice.js): the synthesized cues, rendered to sounds/ by
// scripts/build-capri-sounds.py, or your own file for a cue from the custom sounds folder.
Item {
    id: voice
    readonly property bool muted: Config.getSetting("addonsV2CapriMuted", false)
    property real volume: 0.7
    property var custom: ({})   // cue -> file path, from the custom sounds folder
    property var pool: ({})     // wav -> [SoundEffect]
    property real lastBlip: 0

    function key(cue, opts) {
        opts = opts || {};
        if (cue === "blip") return "blip:" + (opts.mood === "alert" || opts.mood === "error" ? opts.mood : "talk");
        if (cue === "bolt" && opts.soft) return "bolt:soft";
        if (cue === "throw" || cue === "crash") {
            const p = typeof opts.power === "number" ? opts.power : 0.6;
            return cue + ":" + (p <= 0.3 ? 0 : p <= 0.6 ? 1 : 2);
        }
        return cue;
    }

    function play(cue, opts) {
        if (muted) return;
        if (cue === "blip") {
            if (Date.now() - lastBlip < 45) return;
            lastBlip = Date.now();
        }
        if (custom[cue]) {
            player.stop();
            player.source = "file://" + custom[cue];
            player.play();
            return;
        }
        const files = Sounds.SOUNDS[key(cue, opts)];
        if (!files) return;
        const wav = files[Math.floor(Math.random() * files.length)];
        const list = pool[wav] || (pool[wav] = []);
        let effect = list.find(e => !e.playing);
        if (!effect) {
            if (list.length >= 3) effect = list[0];
            else list.push(effect = effectComponent.createObject(voice, { source: Qt.resolvedUrl("sounds/" + wav) }));
        }
        effect.volume = volume;
        effect.play();
    }

    function loadCustom(list) {
        const next = {};
        for (const item of list || []) if (item && typeof item.name === "string" && typeof item.file === "string") next[item.name] = item.file;
        custom = next;
    }

    Component { id: effectComponent; SoundEffect {} }
    MediaPlayer { id: player; audioOutput: AudioOutput { volume: voice.volume } }
}
