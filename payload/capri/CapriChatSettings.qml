import QtQuick
import QtQuick.Controls.Basic
import "../"
import "js/labels.mjs" as Labels

FocusScope {
    id: root
    z: 2
    required property var brain
    required property var controller
    required property var engine
    readonly property var t: brain.labels.setup || ({})
    readonly property var custom: brain.labels.custom || ({})
    readonly property var tray: Labels.TRAY[brain.lang] || Labels.TRAY.en
    property bool personal: false
    visible: controller.settingsOpen
    width: Math.min(440,engine.width-28)
    height: Math.min(engine.height-28,560)
    x: Math.max(14,Math.min(engine.width-width-14,brain.head.x-width/2))
    y: Math.max(14,Math.min(engine.height-height-14,brain.head.y-height))
    Keys.onEscapePressed: controller.settingsOpen=false
    onVisibleChanged: if(visible) {
        forceActiveFocus();
        userName.text=brain.get("UserName","");persona.text=brain.get("Persona","");
        memories.text=brain.get("Memories",[]).join("\n");myLines.text=brain.get("MyLines",[]).join("\n");
        key.clear();
    } else key.clear()
    Connections {
        target: controller
        function onConfigurationChanged() {
            const cfg=controller.configuration;
            provider.currentIndex=Math.max(0,(cfg.providers||[]).map(p=>p.id).indexOf(cfg.provider));
            modelChoice.editText=cfg.provider==="chatgpt" ? (cfg.codexModel||"") : (cfg.chatModel||"");
            url.text=cfg.customUrl||"";
        }
    }
    CapriPlate {anchors.fill:parent;fillColor:"#7d3af5";transform:Translate{x:6;y:6}}
    CapriPlate {anchors.fill:parent}
    MouseArea {anchors.fill:parent;onWheel: w=>w.accepted=true}
    ScrollView {
        anchors.fill:parent;anchors.margins:16;clip:true;contentWidth:availableWidth
        Column {
            width:parent.width;spacing:12
            Flow {
                width:parent.width;spacing:8
                CapriButton {text:root.tray.chatModel;primary:!root.personal;onClicked:root.personal=false}
                CapriButton {text:root.tray.custom;primary:root.personal;onClicked:root.personal=true}
            }
            Column {
                visible:!root.personal;width:parent.width;spacing:10
                Text {width:parent.width;text:root.t.who||"";wrapMode:Text.Wrap;color:"#fcf2f6";font.pixelSize:16;font.family:ThemeBackend.fontFamily}
                Text {text:root.t.which||"";color:"#d6c5d0";font.pixelSize:12}
                ComboBox {
                    id:provider;palette.base:"#2a203b";palette.text:"#fcf2f6";palette.button:"#20182f";palette.buttonText:"#fcf2f6";palette.placeholderText:"#d6c5d0";width:parent.width;textRole:"label";valueRole:"id";model:controller.configuration.providers||[]
                    Accessible.name:root.t.which||""
                    enabled:!controller.configuring
                    onActivated: modelChoice.editText=""
                }
                Text {text:root.tray.chatModel;color:"#d6c5d0";font.pixelSize:12}
                ComboBox {
                    id:modelChoice;palette.base:"#2a203b";palette.text:"#fcf2f6";palette.button:"#20182f";palette.buttonText:"#fcf2f6";palette.placeholderText:"#d6c5d0";width:parent.width;editable:true;model:controller.configuration.models||[]
                    Accessible.name:root.tray.chatModel
                    enabled:!controller.configuring
                }
                Text {
                    visible:provider.currentIndex>=0 && (controller.configuration.providers||[])[provider.currentIndex] && controller.configuration.providers[provider.currentIndex].id==="chatgpt"
                    width:parent.width;text:"ChatGPT · codex login";color:"#d6c5d0";wrapMode:Text.Wrap;font.pixelSize:12
                }
                TextField {
                    id:url;width:parent.width;maximumLength:2000;placeholderText:root.t.address||"";Accessible.name:placeholderText
                    color:"#fcf2f6";placeholderTextColor:"#d6c5d0";selectByMouse:true
                    background:Rectangle {color:"#2a203b";border.color:url.activeFocus?"#36ff73":"#7d3af5"}
                }
                TextField {
                    id:key;width:parent.width;maximumLength:4096;echoMode:TextInput.Password;placeholderText:root.t.placeholder||"";Accessible.name:placeholderText
                    color:"#fcf2f6";placeholderTextColor:"#d6c5d0";selectByMouse:true
                    background:Rectangle {color:"#2a203b";border.color:key.activeFocus?"#36ff73":"#7d3af5"}
                }
                Text {width:parent.width;text:controller.feedback;visible:!!text;color:"#ff8fab";wrapMode:Text.Wrap;font.pixelSize:12;textFormat:Text.PlainText}
                Flow {
                    width:parent.width;spacing:8
                    CapriButton {
                        text:controller.configuring ? root.t.checking : root.t.save;primary:true;enabled:!controller.configuring
                        onClicked: {
                            const p=provider.currentValue || (controller.configuration.providers||[])[provider.currentIndex];
                            if(!p)return;
                            const id=typeof p==="string"?p:p.id;
                            controller.configure({provider:id,chatModel:modelChoice.editText,codexModel:id==="chatgpt"&&modelChoice.editText!=="ChatGPT"?modelChoice.editText:"",customUrl:url.text,apiKey:key.text});
                            key.clear();
                        }
                    }
                    CapriButton {text:root.t.later;onClicked:controller.settingsOpen=false}
                }
            }
            Column {
                visible:root.personal;width:parent.width;spacing:10
                Text {text:root.custom.name||"";color:"#fcf2f6";font.pixelSize:14}
                TextField {id:userName;palette.base:"#2a203b";palette.text:"#fcf2f6";palette.button:"#20182f";palette.buttonText:"#fcf2f6";palette.placeholderText:"#d6c5d0";width:parent.width;maximumLength:24;placeholderText:root.custom.namePlaceholder||"";Accessible.name:root.custom.name||""}
                Text {text:root.custom.persona||"";color:"#fcf2f6";font.pixelSize:14}
                TextArea {color:"#fcf2f6";placeholderTextColor:"#d6c5d0";background:Rectangle {color:"#2a203b";border.color:parent.activeFocus?"#36ff73":"#7d3af5"} id:persona;palette.base:"#2a203b";palette.text:"#fcf2f6";palette.button:"#20182f";palette.buttonText:"#fcf2f6";palette.placeholderText:"#d6c5d0";width:parent.width;height:90;wrapMode:TextEdit.Wrap;placeholderText:root.custom.personaPlaceholder||"";Accessible.name:root.custom.persona||"";onTextChanged:if(text.length>500)remove(500,text.length)}
                Text {text:root.custom.memories||"";color:"#fcf2f6";font.pixelSize:14}
                TextArea {color:"#fcf2f6";placeholderTextColor:"#d6c5d0";background:Rectangle {color:"#2a203b";border.color:parent.activeFocus?"#36ff73":"#7d3af5"} id:memories;palette.base:"#2a203b";palette.text:"#fcf2f6";palette.button:"#20182f";palette.buttonText:"#fcf2f6";palette.placeholderText:"#d6c5d0";width:parent.width;height:90;wrapMode:TextEdit.Wrap;Accessible.name:root.custom.memories||"";onTextChanged:if(text.length>6030)remove(6030,text.length)}
                Text {text:root.custom.lines||"";color:"#fcf2f6";font.pixelSize:14}
                TextArea {color:"#fcf2f6";placeholderTextColor:"#d6c5d0";background:Rectangle {color:"#2a203b";border.color:parent.activeFocus?"#36ff73":"#7d3af5"} id:myLines;palette.base:"#2a203b";palette.text:"#fcf2f6";palette.button:"#20182f";palette.buttonText:"#fcf2f6";palette.placeholderText:"#d6c5d0";width:parent.width;height:90;wrapMode:TextEdit.Wrap;Accessible.name:root.custom.lines||"";onTextChanged:if(text.length>6030)remove(6030,text.length)}
                CapriButton {
                    text:root.custom.save;primary:true
                    onClicked: {
                        function list(text){return text.split("\n").map(s=>s.trim().slice(0,200)).filter(Boolean).slice(-30);}
                        brain.runtime.host.setConfig({userName:userName.text,persona:persona.text,memories:list(memories.text),myLines:list(myLines.text)});
                        controller.settingsOpen=false;
                    }
                }
                CapriButton {text:root.tray.forget||"";onClicked:controller.forget()}
            }
        }
    }
}
