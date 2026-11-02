import QtQuick
import QtQuick.Controls.Basic
import "../"

FocusScope {
    id: panel
    required property var brain
    required property var engine
    readonly property var msg: brain.message || ({})
    readonly property var report: msg.report || null
    readonly property color accent: msg.kind === "error" || msg.kind === "alert" ? "#ff245d" : msg.kind === "remind" ? "#2e79f5" : ["done", "work", "report", "chat"].indexOf(msg.kind) >= 0 ? "#36ff73" : msg.kind === "idle" ? "#9c8ca0" : "#7d3af5"
    readonly property string face: msg.face || ({
            alert: "many",
            done: "look",
            error: "laugh",
            work: "calm",
            idle: "calm",
            report: "smug",
            remind: "look"
        })[msg.kind] || "grin"
    readonly property bool below: brain.head.top - height + 14 < 14
    readonly property bool reduced: !Capri.animationEnabled
    property string decoded: ""
    property bool caretOn: true
    property int letters: 0
    property real messageAt: -1
    property real enteredAt: 0
    property real counter: 1
    property real faceShift: 0
    width: Math.min(engine.width - 28, msg.chat ? Math.max(320, Math.min(420,engine.width*.24)) : msg.reply ? Math.max(340, Math.min(520, engine.width * .3)) : report ? Math.max(340, Math.min(440, engine.width * .26)) : Math.max(290, Math.min(380, engine.width * .21)))
    height: Math.min(engine.height - 28, content.implicitHeight + 30)
    x: Math.max(14, Math.min(engine.width - width - 14, brain.head.x > engine.width / 2 ? brain.head.x - width + 46 : brain.head.x - 46))
    y: Math.max(14, Math.min(engine.height - height - 14, below ? brain.head.y + 40 : brain.head.top - height + 14))
    visible: brain.message !== null && !brain.suspended && (!brain.dnd || !!msg.chat || !!msg.guide || !!msg.asked) && !brain.chatController.hiddenForShot
    opacity: reduced ? 1 : enter.value
    property real tailX: Math.max(24, Math.min(width - 24, brain.head.x - x))
    FontLoader {
        id: displayFont
        source: Qt.resolvedUrl("fonts/ChakraPetch-SemiBold.ttf")
    }
    function refresh() {
        letters = reduced ? String(msg.line || "").length : 0;
        decoded = reduced ? String(msg.line || "") : "";
        enteredAt = Date.now();
        counter = reduced ? 1 : 0;
        if (visible && !reduced) {
            enter.restart();
            decode.restart();
            counts.restart();
            glitch.restart();
        } else {
            decode.stop();
            counts.stop();
        }
        if (engine.capri && visible && !reduced)
            engine.capri.perform("talk");
    }
    onMsgChanged: {
        if(msg.at !== messageAt) {messageAt=msg.at||0;refresh();}
        else if(msg.chat) {if(reduced)decoded=msg.line||"";else if(visible)decode.restart();}
    }
    function submit(text) { if(!brain.runtime.panel.send(text)) brain.chatController.submit(text); }
    function focusChat() { if(visible && msg.chat) chatEntry.forceActiveFocus(); }
    Keys.onEscapePressed: brain.runtime.panel.hide()
    onVisibleChanged: if (visible) {
        refresh();
        if(msg.chat) Qt.callLater(panel.focusChat);
        else if (msg.actions && msg.actions.length) Qt.callLater(() => panel.forceActiveFocus());
    } else {
        decode.stop(); counts.stop(); glitch.stop();
    }
    onReducedChanged: refresh()
    QtObject {
        id: enter
        property real value: 1
        function restart() {
            animation.restart();
        }
    }
    NumberAnimation {
        id: animation
        target: enter
        property: "value"
        from: .2
        to: 1
        duration: 210
        easing.type: Easing.OutExpo
    }
    SequentialAnimation {
        id: glitch
        NumberAnimation {
            target: panel
            property: "faceShift"
            to: 3
            duration: 72
        }
        NumberAnimation {
            target: panel
            property: "faceShift"
            to: -4
            duration: 72
        }
        NumberAnimation {
            target: panel
            property: "faceShift"
            to: 0
            duration: 456
        }
    }
    Timer {
        id: decode
        interval: 28
        repeat: true
        onTriggered: {
            const line = String(panel.msg.line || ""), noise = "▚▞▙▟░▒#%&/\\<>01XZ";
            panel.letters = Math.min(line.length, panel.letters + (panel.msg.chat ? Math.max(2,Math.ceil((line.length-panel.letters)/14)) : 2));
            let tail = "";
            for (let i = panel.letters; i < Math.min(line.length, panel.letters + 6); i++)
                tail += line[i] === " " ? " " : noise[Math.floor(Math.random() * noise.length)];
            panel.decoded = line.slice(0, panel.letters) + tail;
            if (engine.voice && line[panel.letters - 1] && line[panel.letters - 1] !== " ") engine.voice.play("blip", { mood: panel.msg.kind });
            if (panel.letters >= line.length)
                stop();
        }
    }
    Timer {
        interval:600;repeat:true;running:panel.visible && !!panel.msg.chatBusy && !panel.reduced
        onTriggered:panel.caretOn=!panel.caretOn
    }
    Timer {
        id: counts
        interval: 83
        repeat: true
        onTriggered: {
            panel.counter = Math.min(1, (Date.now() - panel.enteredAt) / 1000);
            if (panel.counter >= 1)
                stop();
        }
    }
    CapriPlate {
        anchors.fill: parent
        fillColor: "#7d3af5"
        jagged: true
        transform: Translate {
            x: 6
            y: 6
        }
    }
    CapriPlate {
        anchors.fill: parent
        jagged: true
    }
    Canvas {
        x: panel.tailX - 15
        y: panel.below ? -20 : panel.height - 1
        width: 30
        height: 22
        rotation: panel.below ? 180 : 0
        onPaint: {
            const c = getContext("2d");
            c.fillStyle = ThemeBackend.base;
            c.beginPath();
            c.moveTo(0, 0);
            c.lineTo(30, 0);
            c.lineTo(18.6, 22);
            c.lineTo(15, 10.5);
            c.lineTo(9, 16);
            c.closePath();
            c.fill();
        }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: {if(panel.msg.chat)panel.focusChat();else brain.runtime.panel.hide();}
        onWheel: wheel => wheel.accepted = true
    }
    Flickable {
        anchors.fill: parent
        anchors.margins: 14
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        Column {
            id: content
            width: parent.width
            spacing: 10
            Row {
                width: parent.width
                spacing: 12
                Rectangle {
                    width: 58
                    height: 58
                    color: "#7d3af5"
                    Image {
                        x: 2 + panel.faceShift
                        y: 2
                        width: 54
                        height: 54
                        sourceSize: Qt.size(116, 116)
                        fillMode: Image.PreserveAspectCrop
                        source: Qt.resolvedUrl("assets/" + (panel.face === "grin" ? "capri-face" : "face-" + panel.face) + ".png")
                    }
                }
                Column {
                    width: parent.width - 70
                    spacing: 6
                    Row {
                        width: parent.width
                        spacing: 6
                        Text {
                            text: "CAPRI"
                            color: "#fcf2f6"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                        }
                        Text {
                            width: Math.max(0, parent.width - badge.width - 55)
                            text: panel.msg.tag ? "/ " + panel.msg.tag : ""
                            color: "#b7a4bd"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            id: badge
                            width: badgeText.implicitWidth + 10
                            height: 16
                            color: panel.accent
                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: panel.msg.badge || (brain.labels.state ? brain.labels.state[panel.msg.kind] || "" : "")
                                color: panel.msg.kind === "info" ? "#fcf2f6" : "#120c1c"
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                            }
                            SequentialAnimation on opacity {
                                running: panel.visible && panel.msg.kind === "alert" && !panel.reduced
                                loops: Animation.Infinite
                                NumberAnimation {
                                    to: .3
                                    duration: 450
                                }
                                NumberAnimation {
                                    to: 1
                                    duration: 450
                                }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        text: panel.decoded + (panel.msg.chatBusy && (panel.reduced || panel.caretOn) ? "▌" : "")
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: "#fcf2f6"
                        font.family: brain.lang === "ru" ? ThemeBackend.fontFamily : displayFont.name
                        font.pixelSize: Math.max(15, Math.min(19, engine.width * .0045 + 8.5))
                        font.weight: Font.DemiBold
                    }
                }
            }
            Text {
                visible: !!panel.msg.quote
                width: parent.width
                text: panel.msg.quote || ""
                textFormat: Text.PlainText
                color: "#d6c5d0"
                font.family: ThemeBackend.fontFamily
                font.pixelSize: 11
                wrapMode: Text.Wrap
                maximumLineCount: panel.msg.kind === "alert" || panel.msg.guide ? 12 : 3
                elide: Text.ElideRight
            }
            Rectangle {
                visible: typeof panel.msg.progress === "number"
                width: parent.width
                height: 7
                color: "#20182f"
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, panel.msg.progress || 0))
                    height: parent.height
                    color: "#36ff73"
                }
            }
            Flickable {
                visible: !!panel.msg.reply
                width: parent.width
                height: Math.min(420, engine.height * .44, reply.implicitHeight)
                contentHeight: reply.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                Text {
                    id: reply
                    width: parent.width - 12
                    text: panel.msg.reply || ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: "#d6c5d0"
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: 12
                    lineHeight: 1.6
                }
            }
            Rectangle {
                visible: !!panel.report
                width: parent.width
                height: reportContent.implicitHeight + 24
                color: "#20182f"
                Rectangle {
                    width: parent.width
                    height: 2
                    color: panel.accent
                }
                Column {
                    id: reportContent
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 12
                    }
                    spacing: 10
                    Text {
                        width: parent.width
                        text: panel.report ? brain.labels.report.title + "  /  " + panel.report.date : ""
                        color: "#36ff73"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: 10
                        wrapMode: Text.Wrap
                    }
                    Text {
                        text: panel.report ? Math.round(panel.report.hero.value * (1 - Math.pow(1 - panel.counter, 4))) : ""
                        color: "#36ff73"
                        font.family: displayFont.name
                        font.pixelSize: 56
                        font.bold: true
                    }
                    Text {
                        text: panel.report ? panel.report.hero.label : ""
                        color: "#d6c5d0"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: 11
                    }
                    Row {
                        width: parent.width
                        Repeater {
                            model: panel.report ? panel.report.stats : []
                            Column {
                                required property var modelData
                                width: reportContent.width / 3
                                spacing: 4
                                Text {
                                    text: Math.round(modelData.value * (1 - Math.pow(1 - panel.counter, 4)))
                                    color: modelData.hot ? "#ff245d" : "#fcf2f6"
                                    font.family: displayFont.name
                                    font.pixelSize: 22
                                }
                                Text {
                                    width: parent.width
                                    text: modelData.label
                                    color: "#d6c5d0"
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: 10
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                    Text {
                        visible: !!panel.report && !!panel.report.longest
                        width: parent.width
                        text: visible ? panel.report.longest.label + " · " + panel.report.longest.project + " · " + panel.report.longest.time : ""
                        color: "#ff8fab"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                    Text {
                        width: parent.width
                        text: panel.report ? panel.report.foot + "\nCAPRI // PROJECT CAPRICORN" : ""
                        color: "#b7a4bd"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: 9
                        wrapMode: Text.Wrap
                    }
                }
            }
            Text {
                visible: !!panel.msg.summary
                width: parent.width
                text: "◆ " + (panel.msg.summary || "")
                color: panel.accent
                font.family: ThemeBackend.fontFamily
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
            Column {
                width: parent.width
                spacing: 4
                Repeater {
                    model: (panel.msg.log || []).slice(-4)
                    Text {
                        required property var modelData
                        width: content.width
                        text: modelData.verb + "  " + modelData.target
                        textFormat: Text.PlainText
                        color: modelData.error ? "#ff8fab" : "#d6c5d0"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }
            Column {
                visible:!!panel.msg.chat;width:parent.width;spacing:8
                TextField {
                    id:chatEntry;width:parent.width;maximumLength:2000
                    enabled:!panel.msg.chatBusy
                    placeholderText:panel.msg.chat ? panel.msg.chat.placeholder : ""
                    Accessible.name:placeholderText
                    echoMode:panel.msg.chat && panel.msg.chat.secret ? TextInput.Password : TextInput.Normal
                    color:"#fcf2f6";placeholderTextColor:"#d6c5d0";selectByMouse:true
                    font.family:ThemeBackend.fontFamily
                    background:Rectangle {color:"#2a203b";border.color:chatEntry.activeFocus?"#36ff73":"#7d3af5"}
                    onAccepted: {if(text.trim()){panel.submit(text);clear();}}
                }
                Flow {
                    width:parent.width;spacing:8
                    CapriButton {text:panel.msg.chat?panel.msg.chat.send:"";primary:true;enabled:!panel.msg.chatBusy && !!chatEntry.text.trim();onClicked:{panel.submit(chatEntry.text);chatEntry.clear();}}
                    CapriButton {text:panel.msg.chat?panel.msg.chat.close:"";onClicked:brain.runtime.panel.hide()}
                }
                Text {
                    width:parent.width;visible:!!text;text:panel.msg.chat ? [panel.msg.chat.noteTag,panel.msg.chat.note].filter(Boolean).join(" · ") : ""
                    color:"#b7a4bd";font.family:ThemeBackend.fontFamily;font.pixelSize:10;wrapMode:Text.Wrap
                }
            }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: panel.msg.actions || []
                    CapriButton {
                        required property var modelData
                        text: modelData.label
                        primary: !!modelData.primary
                        accent: panel.accent
                        onClicked: brain.runtime.panel.action(modelData.id)
                    }
                }
            }
        }
    }
}
