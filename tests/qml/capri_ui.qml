import QtQuick
import Quickshell

// Render real QML components in the offscreen fixture, with explicit synthetic UI data.
ShellRoot {
    id: shell
    AddonCapri { id: addon }
    property int step: 0
    property int tries: 0
    property bool capturing: false
    function capture(name, item) {
        if(item.width < 100 || item.height < 25 || !item.visible) { console.error("CAPRI_FAIL",name,"empty surface");Qt.exit(1);return; }
        const path = Quickshell.env("CAPRI_CAPTURE_DIR");
        if(path){shell.capturing=true;item.parent.grabToImage(result=>{if(!result.saveToFile(path+"/"+name+".png")){console.error("CAPRI_FAIL","capture");Qt.exit(1);}shell.capturing=false;});}
    }
    Component.onCompleted: {Config.setSetting("general.performance",true);Config.setSetting("addonsV2Capri",true);}
    Timer {
        interval:1200;running:true;repeat:true
        onTriggered: {
            if(shell.capturing)return;
            const e=addon.world?addon.world.engine:null,r=e?e.brain.runtime:null;
            if(!r || !e.capri.free){if(++shell.tries>15)Qt.exit(1);return;}
            switch(shell.step++) {
            case 0:
                r.panel.say({kind:"alert",line:"Waiting on your green light.",quote:"Capri needs permission to continue this task.",hold:null});break;
            case 1: shell.capture("permission",e.brain.bubble); break;
            case 2:
                r.panel.hide();r.mission.data={date:Qt.formatDate(new Date(),"yyyy-MM-dd"),prompts:5,missions:4,actions:76,files:12,errors:1,approvals:2,longest:{ms:126000,project:"capri"},projects:["capri"],reported:false};r.brain.report();break;
            case 3: if(!e.brain.wantsFocus || !e.brain.bubble.activeFocus){console.error("CAPRI_FAIL","report focus",e.brain.wantsFocus,e.brain.bubble.activeFocus,JSON.stringify(e.brain.message && {kind:e.brain.message.kind,line:e.brain.message.line,guide:e.brain.message.guide}));Qt.exit(1);return;} shell.capture("report",e.brain.bubble);break;
            case 4: r.panel.hide();Config.setSetting("addonsV2CapriLanguage","ru");r.brain.status();break;
            case 5: shell.capture("russian",e.brain.bubble);break;
            case 6: r.panel.hide();e.brain.openMenu();break;
            case 7: shell.capture("menu",e.brain.menu);break;
            case 8: e.brain.menuOpen=false;e.brain.reminderOpen=true;break;
            case 9: shell.capture("reminder-entry",e.brain.menu);break;
            case 10:
                e.brain.reminderOpen=false;Config.setSetting("general.performance",false);e.brain.suspended=true;
                r.panel.say({kind:"info",line:"Transmission after teleport",hold:null});break;
            case 11: e.brain.suspended=false;break;
            case 12: if(e.brain.bubble.decoded!=="Transmission after teleport"){console.error("CAPRI_FAIL","decode resumes after teleport");Qt.exit(1);return;}shell.capture("decode",e.brain.bubble);break;
            case 13: console.log("CAPRI_PASS");Qt.quit();break;
            }
        }
    }
}
