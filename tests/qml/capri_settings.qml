import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import QtTest

ShellRoot {
    id: test
    property int previewWidth: 900
    property int step: 0
    property int tries: 0
    property bool capturing: false
    property string lastAction: ""
    property var searchItems: ({})
    TestCase { id: input; when: false }
    IpcHandler {
        target: "capri"
        function act(name: string, arg: string): string { test.lastAction = name + ":" + arg; return "ok"; }
    }
    function expect(condition, reason) { if (!condition) { console.error("CAPRI_FAIL", step, reason); Qt.exit(1); } }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = find(child, name); if (found) return found; }
        return null;
    }
    function capture(name, after) {
        const path = Quickshell.env("CAPRI_CAPTURE_DIR");
        if (!path) {if(after)after();return;}
        capturing = true;
        guide.grabToImage(result => {expect(result.saveToFile(path + "/" + name + ".png"), "capture");capturing = false;if(after)after();});
    }
    FloatingWindow {
        id: window
        visible: true; implicitWidth: 900; implicitHeight: 740; color: ThemeBackend.base
        Item {
            id: guide
            width: Math.min(window.width,test.previewWidth);height:window.height
            property int currentTab: 0
            property int currentSubTab: 0
            property bool isGuidePopup: true
            function s(v) { return v; }
            function registerSearchItem(info) { test.searchItems[info.id] = info; }
            function unregisterSearchItem(key) {}
            Flickable {
                id: viewport
                anchors.fill: parent; anchors.margins: 24; clip: true
                contentWidth: width; contentHeight: column.implicitHeight
                ColumnLayout {
                    id: column
                    property int tabIndex: 0
                    property int subTabIndex: 0
                    width: viewport.width
                    CapriSettings { id: settings; rootObj: guide; viewport: viewport }
                }
            }
        }
    }
    Component.onCompleted: Config.setSetting("addonsV2Capri", true)
    Timer {
        interval: 400; running: true; repeat: true
        onTriggered: {
            if (test.capturing) return;
            const master = test.find(settings,"capriMaster");
            switch (test.step++) {
            case 0: test.expect(settings.card.previewActive,"enabled preview");test.capture("card-on");break;
            case 1: input.mouseClick(master,master.width/2,master.height/2);break;
            case 2: test.expect(!Capri.enabled && !settings.card.previewActive,"off still and master");test.capture("card-off",()=>{master.forceActiveFocus();input.keyClick(Qt.Key_Space);});break;
            case 3: Config.setSetting("general.performance",true);break;
            case 4: test.expect(!settings.card.previewActive,"performance unload");Config.setSetting("general.performance",false);settings.set("Motion","reduced");break;
            case 5: test.expect(!settings.card.previewActive,"reduced unload");settings.set("Motion","full");Config.setSetting("general.performance",true);break;
            case 6: test.expect(!settings.card.previewActive,"card performance overrides full");Config.setSetting("general.performance",false);settings.set("Motion","auto");settings.visible=false;break;
            case 7: test.expect(!settings.card.previewActive,"tab hidden unload");settings.visible=true;break;
            case 8: test.expect(settings.card.previewActive,"return preview");viewport.contentY=500;break;
            case 9: test.expect(!settings.card.previewActive,"scrolled away unload");viewport.contentY=0;window.visible=false;break;
            case 10: test.expect(!settings.card.previewActive,"window hidden unload");window.visible=true;settings.expanded=true;break;
            case 11:
                if (settings.busy || !settings.hooks.codex) {test.step--;if(++test.tries>15)test.expect(false,"hooks status");return;}
                test.expect(!settings.hooks.codex.data.installed,"no auto install");
                test.find(settings,"capriHook_codex").clicked();break;
            case 12:
                if (settings.busy) {test.step--;return;}
                test.expect(settings.hooks.codex.data.installed,"button install in isolated home");
                test.find(settings,"capriHook_codex").clicked();break;
            case 13:
                if (settings.busy) {test.step--;return;}
                test.expect(!settings.hooks.codex.data.installed,"button uninstall");
                settings.set("Language","fr");test.previewWidth=430;break;
            case 14:
                test.expect(settings.t.options === "Options de Capri","local french");test.capture("options-fr-compact",()=>{
                test.find(settings,"capriScale").currentIndex=2;test.find(settings,"capriScale").selected(2,"Large");
                test.expect(settings.get("Scale",0)===0.8,"size selection");
                settings.watch("none");test.expect(!settings.get("Watching",true),"watch none");
                settings.watch("claude");test.expect(settings.get("Watching",false) && settings.get("Assistant","")==="claude","watch selection");
                test.find(settings,"capriAI").clicked();});break;
            case 15:
                test.expect(test.lastAction === "ai:","settings to shell IPC");test.expect(settings.feedback === settings.t.opened,"action feedback");
                settings.set("Scale",0.45);test.expect(test.find(settings,"capriScale").currentIndex===0,"external size change after selection");
                I18n.currentLang="ar";settings.set("Language","auto");I18n.rtl=true;test.previewWidth=700;viewport.contentY=0;break;
            case 16: test.expect(settings.t.options === "Capri options","unsupported language fallback");test.capture("card-rtl",()=>viewport.contentY=viewport.contentHeight-viewport.height);break;
            case 17: test.capture("options-footer",()=>settings.expanded=false);break;
            case 18:
                test.expect(!!test.searchItems.addons_capri_ai,"search registration");
                test.searchItems.addons_capri_ai.target.acquireRevealHolds();break;
            case 19:
                test.expect(test.searchItems.addons_capri_ai.target.isSettingAvailable(),"search reveals collapsed options");
                test.searchItems.addons_capri_ai.target.releaseRevealHolds();viewport.contentY=0;settings.expanded=true;settings.viewport=({width:0,height:700,contentY:0});break;
            case 20: test.expect(!settings.card.previewActive,"zero width unload");console.log("CAPRI_PASS");Qt.quit();break;
            }
        }
    }
}
