import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id:shell
    AddonCapri {id:addon}
    property int step:0
    property int tries:0
    property string address:""
    property bool configured:false
    property bool capturing:false
    property var e:null
    property var r:null
    function scrollBottom(item) {
        if(item.contentY !== undefined && item.contentHeight > item.height) item.contentY=item.contentHeight-item.height;
        for(const child of item.children || [])scrollBottom(child);
    }
    function expect(ok,text){if(!ok){console.error("CAPRI_FAIL",text,Capri.act("brain",""));Qt.exit(1);}}
    function capture(name,item,after){const dir=Quickshell.env("CAPRI_CAPTURE_DIR");if(!dir){if(after)after();return;}shell.capturing=true;item.parent.grabToImage(result=>{expect(result.saveToFile(dir+"/"+name+".png"),"capture");shell.capturing=false;if(after)after();});}
    Component.onCompleted:{Config.setSetting("general.performance",true);Config.setSetting("notifications.dnd",true);Config.setSetting("addonsV2CapriLanguage","fr");Config.setSetting("addonsV2CapriLinked",true);Config.setSetting("addonsV2Capri",true);}
    Process {
        id:server;running:true;stdinEnabled:true;command:["node",Quickshell.env("CAPRI_TEST_SERVER")]
        stdout:SplitParser{onRead:line=>shell.address="http://127.0.0.1:"+line+"/v1"}
    }
    Timer {
        interval:350;repeat:true;running:true
        onTriggered:{
            if(shell.capturing)return;
            if(shell.step===15){shell.expect(Capri.instances===0,"OFF destroys chat surfaces");console.log("CAPRI_PASS");Qt.quit();return;}
            shell.e=addon.world?addon.world.engine:null;
            shell.r=shell.e?shell.e.brain.runtime:null;
            if(!shell.r||!shell.address||!shell.e.capri.free){if(++shell.tries>80){shell.expect(false,"startup");stop();}return;}
            const ctl=shell.e.brain.chatController,c=ctl.chat,p=shell.r.panel;
            switch(shell.step){
            case 0:ctl.rpc("configure",{provider:"custom",customUrl:shell.address}).then(data=>{shell.expect(data.ok,"configure custom");shell.configured=true;});shell.step++;break;
            case 1:if(!shell.configured)return;ctl.open();shell.step++;break;
            case 2:
                if(!c.open){if(++shell.tries>15)shell.expect(false,"chat opens in DND");return;}shell.expect(shell.e.brain.bubble.visible,"explicit chat renders in DND");shell.expect(shell.e.brain.wantsFocus,"chat focus");shell.expect(p.current.chat.note===shell.r.brain.t.chat.note,"local disclosure");
                ctl.submit("appelle-moi Éléonore");shell.step++;break;
            case 3:
                if(c.turn)return;shell.expect(Config.getSetting("addonsV2CapriUserName","")==="Éléonore","name via Unicode intent");
                shell.expect(c.history.length===2,"complete turn history");shell.expect(p.current.line.indexOf("Salut")>=0,"streamed native answer");shell.expect(shell.r.bond.data.caps.chat===2,"chat affection");
                Config.setSetting("notifications.dnd",false);Config.setSetting("notifications.dnd",true);
                shell.expect(c.open&&shell.e.brain.bubble.visible,"enabling DND keeps the requested chat open");Config.setSetting("notifications.dnd",false);
                shell.capture("chat",shell.e.brain.bubble,()=>ctl.submit("souviens-toi que mon chat aime le soleil"));shell.step++;break;
            case 4:if(c.turn)return;shell.expect(c.persona().indexOf("mon chat aime le soleil")>=0,"memo enters persona");ctl.submit("rappelle-moi de boire");shell.step++;break;
            case 5:if(c.turn)return;shell.expect(c.waitingWhen&&c.waitingWhen.text==="boire","reminder pending");ctl.submit("dans 10 minutes");shell.step++;break;
            case 6:if(c.turn)return;shell.expect(shell.r.reminders.list.length===1,"chat follow-up scheduled");shell.expect(p.current.actions[0].id==="cancel","cancel reminder action");p.action("cancel");shell.expect(!shell.r.reminders.list.length,"cancel saved reminder");ctl.submit("ouvre ce site example.com");shell.step++;break;
            case 7:if(c.turn)return;if(!p.current.actions.length)return;shell.expect(p.current.actions[0].id==="site","model site waits for a button");shell.capture("site-confirm",shell.e.brain.bubble,()=>{p.action("no");ctl.submit("unsolicited suggestion");});shell.step++;break;
            case 8:if(c.turn)return;shell.expect(!p.current.actions.length,"unrequested model tag ignored");
                shell.r.reminders.add(Date.now()-100,"boire");shell.r.reminders.check();shell.step++;break;
            case 9:if(!p.current.actions.length)return;shell.expect(c.open&&p.current.chat,"reminder interjects without closing chat");p.action("done");shell.expect(shell.r.bond.data.caps.remind===2,"chat reminder affection");ctl.submit("CANCEL_TEST");shell.step++;break;
            case 10:if(!c.turn)return;p.hide();shell.expect(!c.open&&!c.turn&&!shell.e.brain.wantsFocus,"close aborts and releases keyboard");shell.expect(Capri.act("ai","")==="ok","AI editor command");shell.expect(!shell.e.brain.chatSettings.personal,"provider page");shell.step++;break;
            case 11:shell.capture("provider-settings",shell.e.brain.chatSettings,()=>Capri.act("personal",""));shell.step++;break;
            case 12:shell.capture("personal-settings",shell.e.brain.chatSettings,()=>shell.scrollBottom(shell.e.brain.chatSettings));shell.step++;break;
            case 13:shell.capture("personal-footer",shell.e.brain.chatSettings,()=>{ctl.settingsOpen=false;ctl.forget();});shell.step++;break;
            case 14:shell.expect(c.history.length===0,"forget local history");Config.setSetting("addonsV2Capri",false);shell.step++;break;
            case 15:console.log("CAPRI_PASS");Qt.quit();break;
            }
        }
    }
}
