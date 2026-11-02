import QtQuick
import "../"
import "js/chat.mjs" as Logic
import "js/guide.mjs" as GuideJs
import "js/setup.mjs" as SetupJs
import "js/custom.mjs" as CustomJs
import "js/look.mjs" as LookJs
import "js/util.mjs" as Util

Item {
    id: root
    required property var brain
    property var chat: null
    property var guide: null
    property var setup: null
    property var custom: null
    property var look: null
    property var progress: null
    // no answer within this long: the helper is gone (0: a model download, as long as it takes)
    readonly property var timeouts: ({send:95000, lookSay:130000, startOllama:40000, pullModel:0})
    property var pending: ({})
    property int serial: 0
    property var delta: null
    property bool settingsOpen: false
    property bool configuring: false
    property var configuration: ({providers: [], models: []})
    property string feedback: ""
    property bool hiddenForShot: false
    signal send(var message)
    function rpc(method, args) {
        return new Promise(resolve => {
            const id = "c" + (++serial);
            const ms = timeouts[method] !== undefined ? timeouts[method] : 20000;
            const timeout = ms ? Util.setTimeout(() => {
                if (!pending[id]) return;
                delete pending[id];
                resolve({ok:false,error:"The Capri helper did not answer. Try again."});
            }, ms) : null;
            pending[id] = {resolve, timeout};
            send({t:"chat.request", id, method, args:args || {}});
        });
    }
    function ingest(m) {
        if (m.t === "chat.delta" && delta) delta(m);
        if (m.t === "setup.progress" && progress) progress(m);
        if (m.t !== "chat.result" || !pending[m.id]) return;
        const p = pending[m.id]; delete pending[m.id]; if (p.timeout) Util.clearTimeout(p.timeout); p.resolve(m.data);
    }
    function start() {
        if (chat || !brain.runtime) return;
        const r = brain.runtime;
        const host = {
            onChatDelta: fn => root.delta = m => fn({id:m.id,text:m.text}),
            chatStatus: () => root.rpc("status"),
            chatMemory: () => root.rpc("memory").then(data => Array.isArray(data) ? data : []),
            chatRemember: history => root.rpc("remember",{history}),
            chatSend: args => root.rpc("send",args),
            chatStop: id => root.rpc("stop",{id}),
            chatIntent: (text,apps,waitingWhen) => root.rpc("intent",{text,apps,waitingWhen}),
            focusOverlay: value => { brain.revision++; if(value) Qt.callLater(() => brain.bubble.focusChat()); },
            setConfig: patch => r.host.setConfig(patch),
            clock: (at,lang) => brain.clock(at,lang),
            now: () => new Date().toLocaleString(Qt.locale("en"),"dddd d MMMM yyyy HH:mm"),
            hideForShot: value => root.hiddenForShot = value,
            openOllama: () => root.rpc("openOllama"),
            // her guide, her setup, looking at your screen (guide/setup/look.mjs)
            hooksStatus: () => root.rpc("hooksStatus",{assistant:r.brain.assistant}).then(s => s || {}),
            installHooks: () => root.rpc("installHooks",{assistant:r.brain.assistant}),
            claudeFound: () => root.rpc("claudeFound",{assistant:r.brain.assistant}).then(found => found === true),
            openClaudeHelp: () => root.rpc("openHelp",{assistant:r.brain.assistant}),
            openClaudeFolder: () => root.rpc("openClaudeFolder",{assistant:r.brain.assistant}),
            trayPlace: () => {
                const c = r.capri.chipAt();
                return Promise.resolve({icon:null, corner:{x:c.x - 50, y:c.y - 60, w:100, h:120}});
            },
            getConfig: () => root.rpc("config"),
            onSetupProgress: fn => root.progress = fn,
            ollamaState: () => root.rpc("ollamaState"),
            installOllama: () => root.rpc("installOllama"),
            startOllama: () => root.rpc("startOllama"),
            setupInfo: () => root.rpc("setupInfo"),
            pullModel: name => root.rpc("pullModel",{name}),
            cancelSetup: () => root.rpc("cancelSetup"),
            useProvider: args => root.rpc("useProvider",args),
            keyPage: provider => root.rpc("keyPage",{provider}),
            launchThroughOllama: integration => root.rpc("launchFree",{integration}),
            lookWhere: () => root.rpc("lookWhere"),
            lookSnap: () => root.rpc("lookSnap",{output:Capri.screenName}),
            lookSay: request => root.rpc("lookSay",request)
        };
        for (const method of ["openApps","findApp","closeApp","findLaunch","launch","openSite","media","music","youtube","roblox","webSearch","searchFiles","openFile","screenshot"]) {
            host[method] = function() {
                const values = Array.prototype.slice.call(arguments);
                if (method === "screenshot") values.push(Capri.screenName);
                return root.rpc(method,{values}).then(data => {
                    if(data && data.ok === false) throw new Error(data.error);
                    return data;
                });
            };
        }
        r.panel.chatInput = {focus: () => brain.bubble.focusChat()};
        chat = new Logic.Chat({capri:r.capri,panel:r.panel,voice:r.voice,host,brain:r.brain});
        // app.js: her guide, her setup with buttons, making her yours, looking at your screen
        guide = new GuideJs.Guide({capri:r.capri,panel:r.panel,voice:r.voice,host,brain:r.brain});
        setup = new SetupJs.Setup({guide,panel:r.panel,host,brain:r.brain,capri:r.capri,voice:r.voice});
        custom = new CustomJs.Custom({guide,host,brain:r.brain,capri:r.capri,voice:r.voice});
        look = new LookJs.Look({capri:r.capri,panel:r.panel,brain:r.brain,chat,guide,host,fx:brain.engine.fx,voice:r.voice,active:() => Util.performance.now() - r.lastMove});
        guide.setup = setup; guide.custom = custom; guide.onTalk = () => root.open();
        setup.onReady = () => root.open();
        chat.look = look; r.guide = guide; r.look = look; r.jealousy.guide = guide;
        configureLook();
        chat.reminders = r.reminders; chat.bond = r.bond; chat.jealousy = r.jealousy;
        chat.onMessage = () => r.bond.add("chat",2);
        chat.onSetup = status => run(setup.chat(status));
        chat.onBetterModel = () => run(setup.better());
        r.chat = chat; r.jealousy.chat = chat; r.brain.onTalk = () => root.open();
        run(boot());
    }
    function run(promise) { if (promise && promise.catch) promise.catch(error => console.warn("Capri guide:", error)); return "ok"; }
    function configureLook() { if (look) look.configure({watchScreen:brain.get("WatchScreen",false), lookAsked:brain.get("LookAsked",false)}); }
    // the IPC/menu commands of app.js's onCommand
    function command(name, arg) {
        start();
        if (!guide) return "not ready";
        brain.menuOpen = false;
        switch (name) {
        case "help": return run(guide.menu());
        case "welcome": return run(guide.welcome());
        case "guide": return ["connect","icon","claude","folder"].indexOf(arg) >= 0 ? run(guide.scene(() => guide[arg]())) : "unknown";
        case "look": return run(look.once());
        case "lookAuto": return run(look.setAuto(arg !== "off" && arg !== "false"));
        case "setup": return run(setup.chat());
        case "key": return run(setup.key());
        case "free": return run(setup.free());
        case "customize": return run(custom.open());
        case "answer": if (guide.waiting) guide.answer(arg); else brain.runtime.panel.action(arg); return "ok";
        }
        return "unknown";
    }
    // After her entrance (app.js boot): the animations question the first time, then her welcome or
    // her online line.
    function boot() {
        const r = brain.runtime, c = r.capri;
        return Util.co((function* () {
            const until = Util.performance.now() + 25000;
            while ((c.busy || c.hidden || c.act) && Util.performance.now() < until) yield Util.sleep(250);
            if (brain.dnd || c.stowed) return;
            if (brain.get("Motion","auto") === "auto" && !Capri.animationEnabled && !brain.get("MotionAsked",false)) {
                const m = r.brain.t.motion;
                yield new Promise(done => {
                    const asked = r.panel.say({kind:"info", face:"aside", guide:true, line:m.line, quote:m.quote, hold:null,
                        actions:[{id:"full",label:m.full,primary:true},{id:"reduced",label:m.still}],
                        onAction: id => { r.host.setConfig({motion:id, motionAsked:true}); r.panel.hide(); if (id === "full") c.perform("hop"); },
                        onLeave: done});
                    if (!asked) done();
                });
            }
            const hooks = yield host().hooksStatus();
            if (!brain.get("Welcomed",false) || (r.brain.watching && !hooks.installed)) yield guide.welcome();
            else r.panel.say({kind:"info", line:r.brain.onlineLine(), hold:4000});
        })());
    }
    function host() { return chat.host; }
    function open() {
        start(); brain.menuOpen = false;
        if(chat) chat.start().catch(error => root.fail(error));
    }
    function submit(text) {
        if(!chat || !text.trim() || text.length > 2000) return;
        chat.send(text.trim()).catch(error => root.fail(error));
    }
    function fail(error) {
        hiddenForShot = false;
        if(chat) {
            chat.turn = 0;
            if(chat.history.length && chat.history[chat.history.length-1].role === "user") chat.history.pop();
        }
        if(brain.runtime) {
            brain.runtime.panel.setChatBusy(false);
            brain.runtime.panel.stream(brain.labels.chat.failed + " " + String(error.message || error),{done:true});
        }
    }
    function showSettings() {
        if(chat) chat.close();
        if(brain.runtime) brain.runtime.panel.hide();
        brain.menuOpen = false; settingsOpen = true;
        rpc("config").then(data => {if(data.providers)configuration = data;});
    }
    function configure(patch) {
        if(configuring)return;
        configuring = true; feedback = "…";
        rpc("configure",patch).then(data => {
            configuring = false;
            if(data.ok) {configuration=data.config;feedback="";settingsOpen=false;root.open();}
            else feedback=data.error || "offline";
        });
    }
    function forget() {
        if(chat) {chat.close();chat.history=[];}
        if(brain.runtime)brain.runtime.panel.hide();
        rpc("forget");
    }
    Component.onDestruction: {if(chat)chat.close();}
}
