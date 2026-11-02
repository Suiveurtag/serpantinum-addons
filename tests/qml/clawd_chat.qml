import QtQuick
import Quickshell

ShellRoot {
    id: shell
    AddonClawd { id: host }

    Timer {
        property int step: 0
        property int waits: 0
        property var p: host.pet
        property var ov: null
        property var chat: null
        interval: 100; running: true; repeat: true
        function expect(c, msg) { if (!c) { console.error("CLAWD_FAIL", step, msg, p ? JSON.stringify({screen: Clawd.screenName, note: chat ? chat.note : "", mode: p.mode, chatOpen: p.chatOpen, phase: p.chatPhase, hist: chat ? JSON.stringify(chat.history) : ""}) : ""); Qt.exit(1); } }
        function wait(c, msg) { if (c) { waits = 0; return true; } if (++waits > 80) expect(false, "timeout: " + msg); step--; return false; }
        function find(item, name) {
            if (item.objectName === name) return item;
            for (const c of item.children) { const r = find(c, name); if (r) return r; }
            return null;
        }
        function last() { return chat.history.length ? chat.history[chat.history.length - 1] : null; }
        onTriggered: {
            switch (step++) {
            case 0:
                Config.setSetting("addonsV2Clawd", true);
                break;
            case 1:
                if (!wait(Clawd.instances === Quickshell.screens.length && host.pet && p.mode === "idle", "pet idle")) break;
                ov = host.overlays.find(o => o.screen.name === Clawd.screenName);
                chat = ov.chat;
                expect(Clawd.chat && !p.chatOpen && !chat.visible, "chat closed at start");
                // the menu's talk row opens the chat
                p.openMenu();
                expect(p.menuOpen && ov.menu.rows[0] === "talk", "menu offers talk");
                ov.menu.choose(0);
                expect(p.chatOpen && !p.menuOpen, "talk row opens the chat");
                break;
            case 2:
                if (!wait(p.mode === "chat" && chat.visible, "chat mode and panel")) break;
                // the menu takes over from the chat
                p.openMenu();
                expect(p.menuOpen && !p.chatOpen, "opening the menu closes the chat");
                p.menuOpen = false;
                break;
            case 3:
                if (!wait(p.mode !== "chat", "leaves chat mode")) break;
                expect(!chat.visible, "panel hidden");
                // double-click on him
                p.doubleClick();
                expect(p.chatOpen, "double-click opens the chat");
                break;
            case 4:
                if (!wait(p.mode === "chat" && chat.visible, "chat reopens")) break;
                const input = find(chat, "clawdChatInput");
                expect(!!input && !!find(chat, "clawdChatLook") && !!find(chat, "clawdChatClear"), "chat controls exist");
                input.text = "salut";
                input.accepted();
                expect(p.chatPhase === "wait" && p.animation === "think", "waiting: chatPhase wait, thinking clip");
                break;
            case 5:
                if (!wait(p.chatPhase === "talk", "reply arrives, he talks")) break;
                expect(chat.history.length === 2 && last().role === "clawd" && last().text === "bonjour from fake", "reply in the panel: " + JSON.stringify(chat.history));
                expect(chat.lines.some(l => l.text.indexOf("bonjour from fake") >= 0), "reply drawn");
                break;
            case 6:
                if (!wait(p.chatPhase === "", "talk ends")) break;
                // history lives in the sidecar: wipe the view, reload
                chat.history = [];
                chat.load();
                break;
            case 7:
                if (!wait(chat.history.length === 2, "history reloaded from the sidecar")) break;
                // look sends the screenshot
                // offscreen has an unnamed screen (Clawd.screenName is ""), which the sidecar refuses: send the look with the fake monitor's name
                chat.history = chat.history.concat([{ role: "user", text: "what is this" }]);
                chat.pending = true; p.chatPhase = "wait";
                chat.reqId = chat.brain.rpc("send", { text: "what is this", context: chat.context(), look: true, output: "offscreen" }, d => chat.answer(d));
                expect(chat.pending && p.chatPhase === "wait", "look pending");
                break;
            case 8:
                if (!wait(!chat.pending && p.chatPhase === "talk", "look reply")) break;
                expect(last().text === "bonjour from fake [img]", "the image reached codex: " + last().text);
                break;
            case 9:
                if (!wait(p.chatPhase === "", "talk ends again")) break;
                chat.forget();
                expect(chat.history.length === 0, "clear empties the panel");
                chat.load();
                break;
            case 10:
                if (!wait(ov.brain.count === 0, "brain idle")) break;
                expect(chat.history.length === 0, "cleared history stays empty after reload: " + JSON.stringify(chat.history));
                // close (the Escape handler is `pet.chatOpen = false`)
                p.chatOpen = false;
                expect(!p.chatOpen, "closed");
                break;
            case 11:
                if (!wait(p.mode !== "chat" && !chat.visible, "chat mode ends")) break;
                console.log("CLAWD_PASS");
                Qt.quit();
                break;
            }
        }
    }
}
