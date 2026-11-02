import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: shell
    AddonCapri { id: addon }
    property int step: 0
    property var r: addon.world && addon.world.engine ? addon.world.engine.brain.runtime : null
    property int tries: 0
    property string tool: ""
    function expect(ok, text) { if(!ok){console.error("CAPRI_FAIL",text,Capri.act("brain",""));Qt.exit(1);} }
    function send(name, fields) { Capri.accept(Object.assign({hook_event_name:name,session_id:"codex:test",cwd:"/project/capri"}, fields || {})); }
    Component.onCompleted: {
        Config.setSetting("general.performance",true);
        Config.setSetting("addonsV2CapriLinked",true);
        Config.setSetting("addonsV2Capri",true);
    }
    Process {
        id: hook
        command: ["node", Capri.scripts + "/hooks/capri-codex-hook.js"]
        stdinEnabled: true
        onRunningChanged: if(running){write(JSON.stringify({hook_event_name:"PreToolUse",session_id:"test",tool_name:"exec_command",tool_input:{cmd:"npm test"}}));stdinEnabled=false;}
    }
    Timer {
        interval: 350; repeat:true; running:true
        onTriggered: {
            if(!shell.r || !addon.world.engine.capri.free){if(++shell.tries>60){shell.expect(false,"runtime startup or action timeout");stop();}return;}
            shell.tries=0;
            const c=addon.world.engine.capri,p=shell.r.panel,b=shell.r.brain;
            switch(shell.step++) {
            case 0:
                shell.expect(!Capri.accept({hook_event_name:"PreToolUse",tool_name:{}}),"reject malformed tool at ingress");
                shell.expect(!Capri.accept({hook_event_name:"PreToolUse",tool_input:[]}),"reject malformed input at ingress");
                shell.expect(b.describe({tool_name:"Bash",tool_input:{command:"a".repeat(150)}}).target.length===64,"long tool input is clipped in QV4");
                shell.expect(b.lang==="en" && b.assistant==="codex","default shell language and assistant");
                Config.setSetting("addonsV2CapriLanguage","fr");
                shell.send("UserPromptSubmit",{prompt:"Teste le Brain"});
                hook.running=true;break;
            case 1:
                if(!b.sessions.get("codex:test") || b.sessions.get("codex:test").count!==1){shell.step--;break;}
                shell.expect(b.describe({tool_name:"Bash",tool_input:{command:"a".repeat(150)}}).target.length===64,"long tool input is clipped in QV4");
                shell.expect(b.lang==="fr" && c.mode==="work","hook through node/HTTP/stdout/Brain");
                shell.expect(p.tickerAction.target==="npm test","adapted Codex ticker");
                p.hide();shell.send("Notification",{notification_type:"permission_prompt",message:"Permission test"});break;
            case 2:
                shell.expect(b.sessions.get("codex:test").waiting && c.mode==="alert","sticky approval");
                shell.expect(addon.world.engine.brain.message.kind==="alert","QML attention bubble");
                shell.send("PostToolUse");shell.expect(!b.sessions.get("codex:test").waiting,"answer clears waiting");
                shell.send("Stop",{last_assistant_message:"**Terminé**"});break;
            case 3:
                shell.expect(shell.r.mission.day.missions===1 && shell.r.mission.day.actions===1,"mission stats");
                shell.expect(p.current.kind==="done","victory onSpeak panel");
                p.hide();Capri.act("report","");shell.expect(p.current.report.hero.value===1,"report render data");
                shell.expect(Capri.act("menu","")==="ok" && addon.world.engine.brain.menuOpen,"menu opens");
                Capri.act("dismiss","");
                Config.setSetting("notifications.dnd",true);shell.send("SessionStart");
                shell.expect(!p.visible,"DND suppresses bubble");
                shell.send("UserPromptSubmit");shell.send("PreToolUse",{tool_name:"Edit",tool_input:{file_path:"a.qml"}});shell.send("Stop");break;
            case 4:
                shell.expect(shell.r.mission.day.missions===2,"DND keeps mission bookkeeping");
                Config.setSetting("notifications.dnd",false);p.hide();
                Capri.act("remind","rappelle-moi dans 5 secondes de boire");break;
            case 5:
                if(!shell.r.reminders.list.length){shell.step--;break;}
                shell.expect(shell.r.reminders.list[0].text==="boire","French parser via sidecar");
                shell.r.reminders.list[0].at=Date.now()-100;
                p.hide();shell.r.reminders.check();break;
            case 6:
                if(!p.current || p.current.kind!=="remind"){shell.step--;break;}
                shell.expect(p.current.actions.length===2,"reminder buttons");
                p.action("snooze");shell.expect(shell.r.reminders.list[0].at>Date.now()+590000,"10 minute snooze");
                shell.r.reminders.list[0].at=Date.now()-100;p.hide();shell.r.reminders.check();break;
            case 7:
                if(!p.current || p.current.kind!=="remind"){shell.step--;break;}
                p.action("done");shell.expect(shell.r.reminders.list.length===0,"done removes reminder");
                shell.expect(shell.r.bond.data.caps.remind===2,"done earns affection");
                Config.setSetting("addonsV2CapriWatching",false);shell.expect(b.sessions.size===0 && p.tickerAction===null,"watch OFF resets brain");
                Config.setSetting("addonsV2Capri",false);break;
            case 8:
                console.log("CAPRI_PASS");Qt.quit();break;
            }
            if(shell.step===8){console.log("CAPRI_PASS");Qt.quit();}
        }
    }
}
