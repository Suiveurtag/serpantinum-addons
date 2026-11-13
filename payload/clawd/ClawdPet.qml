import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../"
import "js/world.mjs" as World
import "js/mind.mjs" as Mind
import "js/acts.mjs" as Acts
import "js/dreams.mjs" as Dreams
import "js/fidgets.mjs" as Fidgets

// Clawd himself, in global logical pixels: x/y is his top-left corner, every ClawdOverlay draws him from here.
// mode: spawn, idle, walk, turn, sit, sleep, drag, fall, land, play, work (an agent session is busy: Clawd.activity,
// playing Clawd.workAnim, the loop of the last tool used, or one of its "_2", "_3"... variants; "sweat" now and then when strained),
// perch (resting on a window top), hop (a parabolic jump), react (a one-shot that returns to his resting pose),
// teeter (at the end of a window top), peek (2/3 hidden behind a window: cover), explode (frozen inside a limit scene),
// corpse (his corpse falling back after it), dead (lying there, grey and smoking: nothing moves him), revive (ClawdRevive),
// climb (up a window side, then climb_top onto it), hang (under the bar or from a window's top corner; swing now and then),
// shimmy (hand over hand along the bar), drop (lets go, then falls), dance (music: dance / dance_2 at the beat's pace),
// sleep (classic or under a blanket: sleepKind), dream / nightmare (a dream scene plays over his sleep), sleepwalk (a few sleeping steps);
// `asleep` is true for all four.
// act (an idle special on the floor: book, bike, boat, camp... a sequence of strips, js/acts.mjs; some have their own canvas size).
// Idle fidgets (js/fidgets.mjs) are plain strips played in his resting modes: a one-shot in idle or perch (yawn, stretch, bubble, butterfly...),
// a seated loop in sit (sit_sway, sit_gaze); they end like a blink does, back in his resting pose.
// mood: '' | drowsy | exhausted | rain | snow, a lasting state from the shell (dim light, low battery, weather): slower, calmer, sits tired,
// under an umbrella or shivering.
// support = what he stands on: null (the floor of `here`) | {kind: "win", id, dx} (dx = contact x - window x;
// a widget's top, 5d: kind "widget") | {kind: "bar", dx, display} (hanging: dx = contact x - bar x) | {kind: "side", id, side, dy} (a window edge:
// climbing, or hanging from its top corner; dy = contact y - the side's top). He is placed through the animation's grip
// (clawd.json; default bottom centre).
Item {
    id: pet
    property var world: null       // ClawdWorld: displays, windows, ledges, cursor
    readonly property bool hypr: Hyprland.requestSocketPath !== ""
    readonly property var displays: world ? world.displays : World.monitors(Quickshell.screens.map(s => ({ name: s.name, x: s.x, y: s.y, width: s.width, height: s.height })),
        hypr ? Hyprland.monitors.values.map(m => ({ name: m.name, x: m.x, y: m.y, lastIpcObject: m.lastIpcObject })) : [])
    readonly property var here: display(Clawd.screenName)
    readonly property int summon: Config.getSetting("addonsV2ClawdSummon", 0)
    readonly property alias frame: clock.frame
    readonly property var pointer: world ? world.pointer : null   // global cursor
    property string mode: "spawn"
    property string animation: "spawn"
    property bool mirrored: false
    property bool reverse: false
    property bool menuOpen: false
    property bool journalOpen: false
    property bool chatOpen: false  // the chat panel is open (it sets this)
    property string chatPhase: ""  // "" | wait (thinking) | talk (answering), set by the chat panel
    property bool dbl: false       // a double-click is under way: its second release is not a single click
    property string mood: ""
    property bool grooved: false   // the swing under the bar is a dance (music), not a natural one
    property real beat: 1          // dance playback rate (bpm / 120)
    property string chain: ""     // the reaction that follows the current one-shot (a look_up, then read)
    property int sleepAfter: Clawd.sleepMinutes * 60000 / (mood === "drowsy" ? 2 : 1)
    property var target: null      // walk destination x
    property var intent: null      // why he walks there: {kind: edge | peek | out | cross | leave, ...}
    property var grab: null        // left press: {x, y, dx, dy, moved}
    property var support: null
    property var cover: null       // the window rect he peeks from behind: the overlays clip him there
    property string coverId: ""
    property var peeking: null     // {id, side, ex} while peeking
    property var hop: null         // the ledge a hop lands on
    property var agenda: null      // {kind: chime | dance, id, bpm, until}: what he does once he stands on that widget
    property var resume: null      // the pose a reaction returns to
    property var act: null         // {name, steps, i, to, v}: the special in progress (mode act)
    property real actAt: Date.now()  // ms when the last special ended (they are rare)
    property string lastAct: ""
    property var fidgets: ({})       // pose (stand | sit | perch) -> the last idle fidget played in it (never the same twice in a row)
    property real touchedAt: Date.now()  // ms of the last touch(): his nap is near once most of sleepAfter has passed
    property bool switching: false
    // Sleep life: sleepKind classic | blanket; sleepAt = ms when this sleep began; dream = {entry, seed} (a registry entry of js/dreams.mjs);
    // dreamPhase "" | bubble (the cloud waits for a click, 30 s) | view (the scene plays; dreamAt = when it began); mumble = a sleep-talk line;
    // journalTab sessions | dreams; sleepLast = ms of the last roll / dream / talk / walk (cooldowns).
    readonly property bool asleep: ["sleep", "dream", "nightmare", "sleepwalk"].indexOf(mode) >= 0
    property string sleepKind: "classic"
    property real sleepAt: 0
    property var dream: null
    property string dreamPhase: ""
    property real dreamAt: 0
    property string mumble: ""
    property string journalTab: "sessions"
    property var sleepLast: ({ roll: 0, dream: 0, talk: 0, walk: 0 })
    property string groggy: ""     // the clip that follows his wake-up one-shot
    // The singularity (ClawdSingularity): {screen, x, y, animation, frame, mirrored, scale, clock}; clock = ms when its
    // timeline was at 0, set once his screen is captured. blasting: frozen inside it, nothing else moves him.
    property var blast: null       // + kind: singularity | nuke | bsod | panic
    property var quotaQueue: []
    property bool blasting: false
    property bool blastHidden: false
    // Dead after a limit scene until revived (menu, a new agent session, or a shell start 3 h later). Kept in Config
    // (addonsV2ClawdDead = when he died, ms) so a reload finds his corpse; reviveAt = ms when the revival started.
    property bool dead: false
    property real weeklyAt: 0      // ms when the weekly reset scene started (mode weekly)
    property real surgeAt: 0       // ms when the superpowered weekly scene started (mode surge)
    property var surgeHome: null   // the workspace id his screen showed before he dashed to an empty one
    property real rechargeAt: 0    // ms when the 5 h reset scene started (mode recharge)
    property real deadAt: 0
    property real reviveAt: 0
    readonly property int reviveAfter: 3 * 3600000
    property var fallTarget: null
    property real fallAt: 0
    property bool lost: false      // his support vanished under him: oops on landing
    property bool dropStartled: false  // the drop in progress was a fright (startled while falling)
    property var mind: Mind.memory()
    property int awayChecks: 0
    property string awayScreen: ""
    property real vx: 0
    property real vy: 0
    property real last: 0
    property bool tired: false
    readonly property bool riding: !!support && support.kind === "win"
    // what `cover` hides of him, px from each side; the overlays clip it
    readonly property var cut: {
        const c = cover;
        if (!c || width <= 0) return { l: 0, r: 0 };
        const a = Math.max(x, c.x), b = Math.min(x + width, c.x + c.w);
        if (b <= a || Math.min(y + height, c.y + c.h) - Math.max(y, c.y) < height / 2) return { l: 0, r: 0 };
        if (c.x <= x && c.x + c.w >= x + width) return { l: width, r: 0 };
        return c.x <= x ? { l: b - x, r: 0 } : { l: 0, r: x + width - a };
    }
    // his box = the canvas of the current strip (the pet's own frame, or a special's bigger one)
    readonly property var box: { const m = Clawd.manifest, c = m && m.animations[animation]; return c && c.w && c.h ? c : m ? m.frame : null; }
    width: box ? Math.round(box.w * Clawd.unit(box)) : 0
    height: box ? Math.round(box.h * Clawd.unit(box)) : 0

    // Working loops that have a variant, and how fast his hands go (the lead session's effort).
    readonly property var families: ["work", "edit", "read", "bash", "search", "web", "task", "todo"]
    readonly property real speed: mode === "dance" ? beat : mode === "work" && families.indexOf(animation.replace(/_\d+$/, "")) >= 0 ? Clawd.effortSpeed : 1

    function display(name) { return displays.find(d => d.id === name) || null; }
    function displayAt(gx, gy) { return World.displayAt(displays, gx, gy); }
    function refresh() { if (hypr) Hyprland.refreshMonitors(); }
    function clampX(d, v) { return Math.max(d.x, Math.min(d.x + d.w - width, v)); }

    // An animation the manifest lacks (sprites not regenerated yet) falls back to a close one.
    function clipName(name) {
        const m = Clawd.manifest, alt = { perch: "sit", perch_look: "sit", hop: "land", stumble: "oops", teeter: "idle", peek: "look_right",
            climb: "walk", climb_top: "land", hang: "idle", shimmy: "walk", swing: "idle", drop: "fall",
            dance: "happy", dance_2: "dance", vibe: "dance", twirl: "dance", wiggle: "dance", breakdance: "dance", shush: "idle", drowsy: "sit", exhausted: "sit", umbrella: "sit", shiver: "idle", chime: "happy",
            sleep_blanket: "sleep", sleep_blanket_in: "sleep", sleep_roll: "sleep", sleep_blanket_roll: "sleep_blanket", sleep_blanket_out: "idle", sleep_jolt: "sleep", wake_groggy: "idle", sleep_walk: "walk" };
        return !m || m.animations[name] || !Object.prototype.hasOwnProperty.call(alt, name) ? name : alt[name];
    }
    function ownGrip(anim) {
        const clip = Clawd.manifest && Clawd.manifest.animations[anim];
        return !!clip && Array.isArray(clip.grip) && clip.grip.length === 2 && clip.grip.every(Number.isFinite);
    }
    // His contact point with the support inside the frame, scaled px from his top-left (mirrored: from the right).
    function grip(anim, flip) {
        const m = Clawd.manifest;
        if (!m) return { x: 0, y: 0 };
        const c = m.animations[anim], sized = c && c.w && c.h, W = sized ? c.w : m.frame.w, H = sized ? c.h : m.frame.h, g = ownGrip(anim) ? m.animations[anim].grip : [W / 2, H];
        const gx = Math.max(0, Math.min(W, g[0])), gy = Math.max(0, Math.min(H, g[1]));
        const u = Clawd.unit(sized ? c : null);
        return { x: Math.round((flip ? W - gx : gx) * u), y: Math.round(gy * u) };
    }
    function contact() { const g = grip(animation, mirrored); return { x: x + g.x, y: y + g.y }; }
    function placeAt(cx, cy) { const g = grip(animation, mirrored); x = cx - g.x; y = cy - g.y; }
    function ledgeOf(s) { return s && world ? world.ledge(s.id) : null; }
    function sideOf(s) { return s && world ? world.sideOf(s.id, s.side) : null; }
    function barOf(s) { return s && world && world.bars ? world.bars[s.display] || null : null; }
    function has(name) { return !!Clawd.manifest && !!Clawd.manifest.animations[name]; }
    function holding() { return ["climb", "hang", "shimmy", "drop"].indexOf(mode) >= 0; }

    function enter(m, anim, flip, back) {
        if (blasting || dead && ["corpse", "dead", "revive", "carried"].indexOf(m) < 0) return;
        if (["sleep", "dream", "nightmare", "sleepwalk"].indexOf(m) < 0) dreamAbort();
        groggy = "";
        const name = clipName(anim), was = grip(animation, mirrored);
        if (m !== "act") { if (act) actAt = Date.now(); act = null; }
        mode = m;
        mirrored = !!flip;
        reverse = !!back;
        switching = true;  // a strip of another size changes width/height: the contact shift below keeps him put, not placeOnSupport
        animation = name;
        switching = false;
        // the contact point stays put: grips differ (perch sits on the seat line, legs below the ledge)
        if (m !== "drag" && m !== "carried") { const g = grip(name, mirrored); x += was.x - g.x; y += was.y - g.y; }
        clock.restart();
        last = Date.now();
        const clip = Clawd.manifest && Clawd.manifest.animations[name];
        brain.stop();
        if (m === "idle" && name === "idle") brain.interval = pause();
        else if (m === "sit" || m === "perch" && clip && clip.loop) brain.interval = 5000 + Math.random() * 7000;
        else if (m === "teeter") brain.interval = 1200 + Math.random() * 800;
        else if (m === "peek") brain.interval = 3000 + Math.random() * 3000;
        else if ((m === "play" || m === "react") && clip && clip.loop) brain.interval = 3000;
        else if (m === "hang") brain.interval = 4000 + Math.random() * 11000;
        else if (m === "dance") brain.interval = 8000 + Math.random() * 6000;
        else if (m === "sleep" || m === "dream" || m === "nightmare") brain.interval = Dreams.tickMs(Clawd.lowMotion, Math.random);
        else return;
        brain.start();
    }
    function pause() {
        if (Clawd.lowMotion) return 20000 + Math.random() * 20000;
        const base = ({ calm: 5000, normal: 3000, active: 2000 })[Clawd.speed] * (mood ? 1.8 : 1);
        return base + Math.random() * base * 1.2;
    }
    function next() {
        if (dead) { if (mode === "dead" && animation !== "dead") enter("dead", "dead"); return; }
        if (mode === "turn" && target !== null) enter("walk", "walk", mirrored);
        else if (mode === "fall") { if (animation !== "fall") enter("fall", "fall"); }  // a startle mid-air is over
        else if (asleep) sleepNext();
        else if (mode === "idle" && groggy) { const g = groggy; groggy = ""; enter("idle", g, mirrored); }
        else if (mode === "teeter") edge();
        else if (mode === "peek") unpeek();
        else if (mode === "chat") { if (chatOpen) enter("chat", chatClip(), mirrored); else idle(); }
        else if (mode === "react" && chain) { const a = chain; chain = ""; enter("react", a); }
        else if (mode === "dance") enter("dance", danceClip());
        else if (mode === "act") actNext();
        else if (mode === "climb") { if (animation === "climb_top") idle(); }
        else if (mode === "hang") hangThink();
        else if (mode === "drop") fell();
        else if (mode === "shimmy") return;
        else if (mode === "react" && resume && grounded()) { const r = resume; resume = null; enter(r.mode, r.animation, r.mirrored); }
        else if (["sleep", "drag", "walk", "hop", "chat", "recharge", "weekly", "surge"].indexOf(mode) < 0) idle();
    }
    // Back to his resting pose on whatever holds him: perch on a window, idle on the floor; no valid support: fall.
    function idle() {
        if (dead) return;
        target = null;
        intent = null;
        resume = null;
        chain = "";
        peeking = null;
        cover = null;
        coverId = "";
        if (!grounded()) { support = null; vy = 0; enter("fall", "fall"); return; }
        if (!support && here) x = clampX(here, x);
        if (chatOpen) { enterChat(); return; }  // an agent hook does not pull him out of the chat
        if (Clawd.activity) { touch(); enter("work", Clawd.activity === "alert" ? "alert" : Clawd.variant(Clawd.workAnim)); }
        else if (tired) sleep();
        else if (due()) play();
        else if (support) enter("perch", "perch");
        else enter("idle", "idle");
    }
    function grounded() {
        if (support && (support.kind === "bar" || support.kind === "side")) return false;  // held by his hands, not standing
        if (support) { const l = ledgeOf(support); return !!l && !!World.span(world.wins, l, l.x + support.dx); }
        return !here || contact().y >= here.floor - 0.5;
    }
    function think() {
        refresh();
        const chance = (Clawd.lowMotion ? 0.1 : ({ calm: 0.25, normal: 0.4, active: 0.6 })[Clawd.speed]) * (mood ? 0.5 : 1);  // a mood walks calmly
        const r = Math.random(), rest = (r - chance) / (1 - chance);
        if (chatOpen) enterChat();
        else if (menuOpen) enter(support ? "perch" : "idle", support ? "perch" : "idle");
        else if (r < chance) { if (!(r < chance / 4 && explore())) walk(); }  // a quarter of his walks explore
        else if (!support && actReady() && Math.random() < ({ calm: 0.05, normal: 0.08, active: 0.12 })[Clawd.speed]) startAct("");
        else if (support) {
            if (rest < 0.3) enter("perch", "perch_look", Math.random() < 0.5);
            else if (rest < 0.45) { if (!hopDown(0)) enter("perch", "perch"); }
            else enter("perch", rest < 0.65 && fidget("perch") || "perch");
        }
        else if (rest < 0.3) enter("idle", "blink");
        else if (rest < 0.55 && !Clawd.lowMotion) enter("idle", look());
        else if (rest < 0.78 && fidget("stand")) enter("idle", fidgets.stand);
        else if (rest < 0.9) enter("sit", moodSit());
        else enter("idle", "idle");
    }
    // The next idle fidget for his pose (stand | sit | perch, js/fidgets.mjs), remembered in fidgets[pose]; "" when there is none (performance
    // mode, a mood that allows none, sprites not regenerated yet).
    function fidget(pose) {
        if (Clawd.lowMotion) return "";
        const sleepy = !mood && Date.now() - touchedAt > sleepAfter * 0.6;
        const name = Fidgets.pick(pose, { mood, sleepy, prev: fidgets[pose] || "" }, Math.random, has);
        if (name) fidgets = Object.assign({}, fidgets, { [pose]: name });
        return name;
    }
    // The idle specials: rare, on the floor, in a calm state; each is a sequence of strips (js/acts.mjs) of their own size.
    function actReady() {
        return !!here && !!world && !Clawd.lowMotion && !mood && !Clawd.activity && !tired && !menuOpen && !journalOpen && !chatOpen && !grab && !owned() && grounded()
            && Date.now() - actAt > 45000;
    }
    function startAct(name) {
        const has2 = n => Acts.plan(n, () => 0.5).every(s => has(s.clip));
        const pick = name || Acts.pick(lastAct, Math.random, has2);
        if (!pick || !has2(pick) || !here) return false;
        touch();
        target = null;
        intent = null;
        lastAct = pick;
        act = { name: pick, steps: Acts.plan(pick, Math.random), i: -1, dir: Math.random() < 0.5 ? -1 : 1 };
        actNext();
        return true;
    }
    function actNext() {
        if (!act || !here) return idle();
        const i = act.i + 1;
        if (i >= act.steps.length) { actAt = Date.now(); return idle(); }
        const s = act.steps[i], a = act;
        let dir = a.dir;
        if (s.go) {  // walk toward the side with more room, the strips face right: mirrored going left
            const left = x - here.x, right = here.x + here.w - (x + width);
            dir = Math.abs(left - right) < 80 ? a.dir : left > right ? -1 : 1;
            a.dir = dir;
        }
        enter("act", s.clip, dir < 0);
        if (act !== a) return;
        a.i = i;
        a.to = undefined;
        x = clampX(here, x);
        if (s.go) {
            const b = stand(), want = s.go.min + Math.random() * (s.go.max - s.go.min);
            const to = b ? Math.max(b.x0, Math.min(b.x1, x + dir * want)) : x;
            if (Math.abs(to - x) < 30) return actNext();
            a.to = to;
            a.v = s.go.v[({ calm: 0, normal: 1, active: 2 })[Clawd.speed] ?? 1];
        } else if (s.ms) { brain.interval = s.ms; brain.start(); }
    }
    // The sitting pose of his mood: tired when drowsy or exhausted, under an umbrella in the rain (now and then).
    function moodSit() {
        if ((mood === "drowsy" || mood === "exhausted") && has(mood)) return mood;
        const weather = mood === "rain" ? "umbrella" : mood === "snow" ? "shiver" : "";
        if (weather && !Clawd.lowMotion && has(weather) && Math.random() < 0.5) return weather;
        return !mood && Math.random() < 0.5 && fidget("sit") || "sit";  // a calm day: half his sits sway or gaze at the sky
    }
    function lookAt(gx, gy) {
        const dx = gx - (x + width / 2), dy = gy - (y + height / 2);
        return dy < 0 && -dy > Math.abs(dx) ? "look_up" : dx < 0 ? "look_left" : "look_right";
    }
    function look() {
        if (!pointer) return ["look_left", "look_right", "look_up"][Math.floor(Math.random() * 3)];
        return lookAt(pointer.x, pointer.y + height / 2);  // above his head counts as up
    }
    // Sprite x range he can walk on: the floor of his screen, or the uncovered part of his window top.
    function stand() {
        if (!support) return here ? { x0: here.x, x1: here.x + here.w - width } : null;
        const l = ledgeOf(support), s = l && World.span(world.wins, l, l.x + support.dx);
        return s ? { x0: s.x0, x1: s.x1 - width } : null;
    }
    function walk() {
        const s = stand();
        if (!s || s.x1 - s.x0 < 8) return idle();
        const distance = 80 + Math.random() * Math.min(400, s.x1 - s.x0);
        const fit = v => Math.max(s.x0, Math.min(s.x1, v));
        let to = x + (Math.random() < 0.5 ? -distance : distance);
        // the floor turns him back at the screen edge; a window top may take him to its end, where he teeters
        if (fit(to) !== to && (!support || Math.random() < 0.5)) to = 2 * x - to;
        to = fit(to);
        if (!walkTo(to, support && (to <= s.x0 + 0.5 || to >= s.x1 - 0.5) ? { kind: "edge" } : null)) idle();
    }
    function walkTo(to, why) {
        if (Math.abs(to - x) < 8) {
            if (!why || why.kind !== "peek" && why.kind !== "climb") return false;
            intent = why;
            arrive();
            return true;
        }
        target = to;
        intent = why || null;
        enter("turn", "turn", to < x);
        return true;
    }
    function step() {
        const now = Date.now(), dt = Math.min(0.05, (now - last) / 1000);
        last = now;
        if (mode === "walk") {
            const hurry = intent && (intent.kind === "cross" || intent.kind === "leave") ? 3 : 1;
            const v = ({ calm: 30, normal: 60, active: 100 })[Clawd.speed] * hurry * dt, left = target - x;
            if (Math.abs(left) > v) { x += left > 0 ? v : -v; walked(); return; }
            x = target;
            target = null;
            walked();
            arrive();
        } else if (mode === "sleepwalk" && target !== null) {
            const v = 24 * dt, left = target - x;
            if (Math.abs(left) > v) x += left > 0 ? v : -v;
            else { x = target; target = null; sleep(sleepKind, true); }
        } else if (mode === "act" && act && act.to !== undefined) {
            const v = act.v * dt, left = act.to - x;
            if (Math.abs(left) > v) x += left > 0 ? v : -v;
            else { x = act.to; act.to = undefined; actNext(); }
        } else if (mode === "fall") {
            vy = Math.min(2400, vy + 2600 * dt);
            const c = contact(), ny = c.y + vy * dt;
            if (!fallTarget || now - fallAt >= 250) { fallTarget = landingAt(c.x, c.y); fallAt = now; }
            if (fallTarget && ny >= fallTarget.y) {
                fallTarget = landingAt(c.x, c.y);  // touchdown: is it still there?
                fallAt = now;
                if (fallTarget && ny >= fallTarget.y) return settle(fallTarget, c.x);
            }
            placeAt(c.x, ny);
        } else if (mode === "corpse") {
            // his corpse drops straight onto the floor of his screen, whatever is in between
            vy = Math.min(2400, vy + 2600 * dt);
            const c = contact(), ny = c.y + vy * dt;
            if (here && ny >= here.floor) { vy = 0; placeAt(c.x, here.floor); enter("dead", "dead_land"); }
            else placeAt(c.x, ny);
        } else if (mode === "climb" && animation === "climb" && support && support.kind === "side") {
            const s = sideOf(support);
            if (!s) return slip(true);
            const ny = contact().y - ({ calm: 40, normal: 70, active: 110 })[Clawd.speed] * dt;
            if (ny <= s.y0 + 2) return topOut(s);
            placeAt(s.x, ny);
            support.dy = ny - s.y0;
        } else if (mode === "shimmy" && support && support.kind === "bar") {
            const b = barOf(support);
            if (!b || target === null) return b ? hangAgain() : slip(true);
            const to = Math.max(b.x, Math.min(b.x + b.w - width, target)), v = ({ calm: 25, normal: 40, active: 60 })[Clawd.speed] * dt;
            if (Math.abs(to - x) > v) x += to > x ? v : -v;
            else { x = to; hangAgain(); }
            if (support) support.dx = contact().x - b.x;
        } else if (mode === "hop" && hop) {
            vy = Math.min(2400, vy + 2600 * dt);
            const c = contact(), nx = c.x + vx * dt, ny = c.y + vy * dt;
            const b = hop.kind === "bar" ? barOf(hop) : null, l = hop.kind === "floor" ? hop : b ? Object.assign(hop, { y: b.y }) : hop.kind === "bar" ? null : ledgeOf(hop);
            if (!l) { hop = null; vx = 0; enter("fall", "fall"); return; }  // its window went away mid-air
            if (vy > 0 && ny >= l.y) return settle(l, nx);
            placeAt(nx, ny);
        }
    }
    function walked() {
        if (support) { const l = ledgeOf(support); if (l) support.dx = contact().x - l.x; }
        if (intent && intent.kind === "cross") track();
    }
    function arrive() {
        const i = intent;
        intent = null;
        if (i && i.kind === "edge" && support) return enter("teeter", "teeter", mirrored);
        if (i && i.kind === "climb") return startClimb(i);
        if (i && i.kind === "notif") return lookRead();
        if (i && i.kind === "visit") { const l = world ? world.ledge(i.id) : null, tx = l ? reach(l) : null; return tx !== null && !owned() ? void hopTo(tx, l) : idle(); }
        if (i && i.kind === "peek") {
            // the window on his right (came to its left edge): peek out leftwards, mirrored
            const flip = i.side < 0;
            peeking = i;
            enter("peek", "peek", flip);
            x = ownGrip(animation) ? i.ex - grip(animation, flip).x : flip ? i.ex - width / 3 : i.ex - width * 2 / 3;
            return;
        }
        if (i && i.kind === "out") { cover = null; coverId = ""; }
        if (i && i.kind === "leave") return reenter(i.to);
        enter("turn", "turn", mirrored, true);
    }
    // At the end of a window top: hop down (40 %), (5b: hang from the edge, 30 %), else turn back.
    function edge() {
        if (!support) return idle();
        if (Math.random() < 0.4 && hopDown(mirrored ? -1 : 1)) return;
        const s = stand();
        if (!s || !walkTo(Math.max(s.x0, Math.min(s.x1, x + (mirrored ? 1 : -1) * (60 + Math.random() * 140))))) idle();
    }
    // Off his window top, on that side (0: the nearest one with room), down to whatever is below.
    function hopDown(side) {
        const l = ledgeOf(support);
        if (!l) return false;
        const c = contact(), d = display(l.display) || here;
        const off = s => { const tx = s < 0 ? l.x - width * 0.6 : l.x + l.w + width * 0.6; return d && tx - width / 2 >= d.x && tx + width / 2 <= d.x + d.w ? tx : null; };
        const near = c.x - l.x < l.x + l.w - c.x ? -1 : 1;
        const tx = side ? off(side) : off(near) !== null ? off(near) : off(-near);
        return tx !== null && hopTo(tx, landingAt(tx, c.y + 1));
    }
    // A parabolic jump: his contact point flies to (tx, ledge top).
    function hopTo(tx, l) {
        if (!l) return false;
        const c = contact(), g = 2600, top = Math.min(c.y, l.y) - Math.max(height * 0.6, Math.abs(tx - c.x) * 0.2);
        const up = Math.sqrt(2 * g * (c.y - top)), t = up / g + Math.sqrt(2 * (l.y - top) / g);
        vy = -up;
        vx = (tx - c.x) / t;
        hop = l;
        support = null; target = null; intent = null; cover = null; coverId = ""; peeking = null;
        touch();
        enter("hop", "hop", tx < c.x);
        return true;
    }
    // Touchdown on ledge l, his contact at cx.
    function settle(l, cx) {
        if (l.kind === "bar") { hop = null; vx = 0; const b = barOf(l); if (b) hangOn(b, cx); else { lost = true; enter("fall", "fall"); } return; }  // grabbed the bar
        const win = l.kind !== "floor";
        if (win) {  // clamp onto the ledge, then off any front window; none left: fall again
            const s = World.standAt(world ? world.wins : [], l, cx, width / 2);
            if (s === null) { support = null; vy = 0; fallTarget = null; hop = null; lost = true; enter("fall", "fall"); return; }
            cx = s;
        }
        support = win ? { kind: l.kind, id: l.id, dx: cx - l.x } : null;
        vy = 0; vx = 0; fallTarget = null;
        const hopping = mode === "hop" && !clock.done && animation === clipName("hop");
        hop = null;
        if (hopping) mode = "land";  // the hop strip ends with its own landing squash
        else enter("land", lost ? "oops" : "land");
        lost = false;
        placeAt(cx, l.y);
        const d = display(l.display);
        if (!win && d) x = clampX(d, x);
        if (d && d.id !== Clawd.screenName) Clawd.screenName = d.id;
    }
    function landingAt(cx, feetY) {
        const t = world ? World.landing(world.ledges, world.wins, cx, feetY, displays) : null;
        if (t) return t;
        const d = displayAt(cx, feetY);
        return d ? { id: "floor:" + d.id, kind: "floor", x: d.x, y: d.floor, w: d.w, display: d.id } : null;
    }
    // Modes the world must never disturb: input, physics in flight, and the scenes of other work.
    function owned() { return blasting || dead || ["drag", "fall", "hop", "corpse", "dead", "revive", "carried", "explode", "recharge", "weekly", "surge"].indexOf(mode) >= 0; }
    function placeOnSupport() {
        if (!here || owned()) return;  // special modes keep their support and revalidate after
        if (support) return revalidate();
        placeAt(contact().x, here.floor);
        if (!intent || ["cross", "leave"].indexOf(intent.kind) < 0) x = clampX(here, x);
    }
    // After every world snapshot: follow his window, or lose it (gone, covered, maximized, another workspace).
    function revalidate() {
        if (coverId) {
            const w = world ? world.win(coverId) : null;
            if (!w || !cover || w.x !== cover.x || w.y !== cover.y || w.w !== cover.w || w.h !== cover.h) {
                cover = null;
                coverId = "";
                if (mode === "peek") unpeek();
                else if (intent && intent.kind === "peek") idle();
            }
        }
        if (!support || owned()) return;
        if (support.kind === "bar" || support.kind === "side") return holdOn();
        const l = ledgeOf(support), c = contact(), cx = l ? l.x + support.dx : 0;
        if (!l || !World.span(world.wins, l, cx)) return lose(false);
        if (Math.abs(cx - c.x) + Math.abs(l.y - c.y) > 200) return lose(true);  // yanked away: startled mid-air
        if (Math.abs(cx - c.x) + Math.abs(l.y - c.y) < 0.01) return;
        if (target !== null) target += cx - c.x;
        placeAt(cx, l.y);
        track();
    }
    function lose(startle) {
        if (owned()) return;  // keeps its support: revalidate() finds it again afterwards
        support = null; hop = null; target = null; intent = null; fallTarget = null;
        vy = 0;
        lost = true;
        touch();
        enter("fall", startle ? "startled" : "fall");
    }
    // Hanging or climbing: follow the bar or the window edge, or let go when it is gone.
    function holdOn() {
        const s = support, c = contact();
        let cx, cy;
        if (s.kind === "bar") {
            const b = barOf(s);
            if (!b) return slip(true);
            cx = Math.max(b.x + width / 2, Math.min(b.x + b.w - width / 2, b.x + s.dx));
            cy = b.y;
        } else {
            const t = sideOf(s);
            if (!t) return slip(true);
            cx = t.x;
            cy = mode === "climb" ? Math.max(t.y0, Math.min(t.y1, t.y0 + s.dy)) : t.y0;
        }
        const off = Math.abs(cx - c.x) + Math.abs(cy - c.y);
        if (off > 200) return slip(true);
        if (off > 0.01) placeAt(cx, cy);
    }
    // His hold vanished: falls from where he is (the sprite box stays, hands and feet differ), startled or not.
    function slip(startle) {
        if (owned()) return;
        const bx = x, by = y;
        support = null; hop = null; target = null; intent = null; fallTarget = null;
        vy = 0;
        lost = true;
        touch();
        enter("fall", startle ? "startled" : "fall");
        x = bx; y = by;
    }
    // His centre went over to another screen.
    function track() {
        const d = displayAt(x + width / 2, y + height / 2);
        if (d && d.id !== Clawd.screenName) Qt.callLater(moveTo, d.id);
    }
    function moveTo(name) { if (display(name) && Clawd.screenName !== name) Clawd.screenName = name; }

    // Windows, peeking and the cursor's screen; false when there is nothing to explore.
    function explore() {
        if (!world || !Clawd.world || Clawd.lowMotion || chatOpen || !here) return false;
        const c = contact(), ops = [];
        let hopOn = null;
        for (const l of world.ledges) {
            if (l.kind === "floor" || l.display !== here.id || support && l.id === support.id) continue;
            const up = c.y - l.y, tx = Math.max(l.x + width * 0.6, Math.min(l.x + l.w - width * 0.6, c.x));
            if (up < 8 || up > height * 1.5 || Math.abs(tx - c.x) > width * 4 || !World.span(world.wins, l, tx)) continue;
            if (!hopOn || Math.abs(tx - c.x) < Math.abs(hopOn.tx - c.x)) hopOn = { tx, l };
        }
        if (hopOn) ops.push(() => hopTo(hopOn.tx, hopOn.l));
        const spot = support ? null : peekSpot();
        if (spot) ops.push(() => peek(spot));
        const edge = support || !has("climb") ? null : climbSpot();
        if (edge) ops.push(() => climb(edge));
        const cur = World.cursor(displays, here, pointer);
        if (cur && cur.display && !cur.inside && Clawd.world && Clawd.follow) ops.push(() => cross(cur.display));
        else if (cur && cur.inside) ops.push(() => { const s = stand(); return !!s && walkTo(Math.max(s.x0, Math.min(s.x1, cur.x - width / 2))); });
        return ops.length > 0 && !!ops[Math.floor(Math.random() * ops.length)]();
    }
    // The nearest window edge on his screen he can hide behind from the floor (the window covers his height).
    function peekSpot() {
        const c = contact(), d = here;
        let best = null;
        for (const w of world.wins) {
            if (w.display !== d.id || w.max || w.y > y + height * 0.3 || w.y + w.h < y + height * 0.7) continue;
            for (const side of [-1, 1]) {  // -1: its left edge, he comes from the left
                const ex = side < 0 ? w.x : w.x + w.w, px = side < 0 ? ex - width / 3 : ex - width * 2 / 3;
                if ((side < 0 ? c.x > ex : c.x < ex) || px < d.x || px + width > d.x + d.w) continue;
                if (World.covered(world.wins, w.id, ex - 1, ex + 1, y + height / 2)) continue;
                const far = Math.abs(px - x);
                if (far <= 500 && (!best || far < best.far)) best = { id: w.id, rect: { x: w.x, y: w.y, w: w.w, h: w.h }, side, ex, x: px, far };
            }
        }
        return best;
    }
    function peek(spot) {
        coverId = spot.id;
        cover = spot.rect;
        if (walkTo(spot.x, { kind: "peek", id: spot.id, side: spot.side, ex: spot.ex })) return true;
        cover = null;
        coverId = "";
        return false;
    }
    // The nearest climbable window side on his screen, from the floor: {id, side, x (his x at the foot of it), far}.
    function climbSpot() {
        if (!world || !here || !world.sides) return null;
        let best = null;
        for (const s of world.sides[here.id] || []) {
            const tx = s.x - grip("climb", s.side > 0).x, far = Math.abs(tx - x);
            if (tx < here.x || tx + width > here.x + here.w || far > 700 || best && far >= best.far) continue;
            best = { id: s.id, side: s.side, x: tx, far };
        }
        return best;
    }
    function climb(spot) { return walkTo(spot.x, { kind: "climb", id: spot.id, side: spot.side }); }
    // At the foot of the side: up he goes (the wall column of the sprite on the window edge).
    function startClimb(i) {
        const s = world ? world.sideOf(i.id, i.side) : null;
        if (!s || owned() || Clawd.lowMotion || !has("climb")) return idle();
        const top = y;
        touch();
        support = { kind: "side", id: s.id, side: s.side, dy: 0 };
        enter("climb", "climb", s.side > 0);
        placeAt(s.x, top + grip(animation, mirrored).y);
        support.dy = contact().y - s.y0;
    }
    // Reached the top of the side: mantle onto the window if there is room, else hop to the bar (window top right under it),
    // else hang from the window's top corner.
    function topOut(s) {
        const l = world.ledge(s.id), d = display(s.display) || here, b = d && world.bars ? world.bars[d.id] : null;
        const cx = l && l.display === s.display ? World.standAt(world.wins, l, s.x + (s.side < 0 ? 1 : -1) * width / 2, width / 2) : null;
        if (cx !== null) {
            support = { kind: "win", id: l.id, dx: cx - l.x };
            if (!has("climb_top")) return settle(l, cx);
            enter("climb", "climb_top", s.side > 0);
            placeAt(cx, l.y);
        } else if (b && s.y0 - b.y < height * 1.2) { if (!hopBar(s.x)) slip(false); }
        else if (has("hang") && !owned()) {
            support = { kind: "side", id: s.id, side: s.side, dy: 0 };
            enter("hang", "hang", s.side > 0);
            placeAt(s.x, s.y0);
        } else slip(false);
    }
    // A jump from where he is up to the bar: his hands fly to its underside at cx, then hangBar.
    function hopBar(cx) {
        const b = here && world && world.bars ? world.bars[here.id] : null;
        if (!b || !has("hang") || owned() || Clawd.lowMotion) return false;
        return hopTo(Math.max(b.x + width / 2, Math.min(b.x + b.w - width / 2, cx)), { kind: "bar", y: b.y, display: here.id });
    }
    // Hanging under the bar of his screen with his centre at cx.
    function hangBar(cx) {
        const b = here && world && world.bars ? world.bars[here.id] : null;
        if (!b || !has("hang") || owned() || Clawd.lowMotion) return false;
        hangOn(b, cx);
        return true;
    }
    function hangOn(b, cx) {
        cx = Math.max(b.x + width / 2, Math.min(b.x + b.w - width / 2, cx));
        touch();
        target = null; intent = null; resume = null; hop = null; fallTarget = null; cover = null; coverId = ""; peeking = null;
        vy = 0;
        support = { kind: "bar", dx: cx - b.x, display: here.id };
        enter("hang", "hang", mirrored);
        placeAt(cx, b.y);
    }
    // Brain tick while hanging (4-15 s): shimmy along the bar, swing, or let go.
    function hangThink() {
        if (!support || owned()) return;
        const b = support.kind === "bar" ? barOf(support) : null, r = Math.random();
        if (Clawd.lowMotion || Clawd.activity || r < 0.2) return void letGo(false);
        if (animation === clipName("swing") && has("swing")) return hangAgain();
        if (b && has("shimmy") && r < 0.6 && b.w > width * 2) {
            const d = (Math.random() < 0.5 ? -1 : 1) * (80 + Math.random() * 240), fit = v => Math.max(b.x, Math.min(b.x + b.w - width, v));
            let to = fit(x + d);
            if (Math.abs(to - x) < 8) to = fit(x - d);
            if (Math.abs(to - x) >= 8) { target = to; enter("shimmy", "shimmy", to < x); return; }
        }
        if (has("swing") && r < 0.85) enter("hang", "swing", mirrored);
        else hangAgain();
    }
    function hangAgain() { target = null; enter("hang", "hang", mirrored); }
    // Lets go (startled: a fright); a drop animation first when he hangs, straight down when he climbs.
    function letGo(startled) {
        if (owned() || !holding() || mode === "drop") return false;
        target = null; intent = null;
        dropStartled = !!startled;
        if (mode === "climb" || !has("drop")) fell();
        else enter("drop", "drop", mirrored);
        return true;
    }
    function fell() {
        const bx = x, by = y;
        support = null; hop = null; fallTarget = null;
        vy = 0;
        lost = false;
        touch();
        enter("fall", dropStartled ? "startled" : "fall");
        x = bx; y = by;
        dropStartled = false;
    }
    // 5d widgets. The nearest widget of a kind (clock | music) on his display; none while the widget editor is on.
    function widgetOn(kind) {
        if (!world || !here || world.redact) return null;
        let best = null;
        for (const w of world.widgets) if (w.display === here.id && World.widgetKind(w.type) === kind && (!best || Math.abs(w.x + w.w / 2 - x - width / 2) < Math.abs(best.x + best.w / 2 - x - width / 2))) best = w;
        return best;
    }
    // Where on ledge l (its middle) he could jump from where he is: null when it is too high, below him or covered.
    function reach(l) {
        const c = contact(), tx = l.x + l.w / 2, up = c.y - l.y;
        return up >= 8 && up <= height * 4 && World.span(world.wins, l, tx) ? tx : null;
    }
    // Toward ledge l: a hop from here when it is near, else a walk along the floor to its foot first. False: out of reach or not now.
    function visit(l) {
        if (!l || !world || !here || owned() || holding() || Clawd.lowMotion || l.display !== here.id) return false;
        const tx = reach(l), cx = contact().x;
        if (tx === null) return false;
        if (Math.abs(tx - cx) <= width * 3) return hopTo(tx, l);
        const s = support ? null : stand();
        return !!s && walkTo(Math.max(s.x0, Math.min(s.x1, tx - width / 2 - (tx > cx ? 2 : -2) * width)), { kind: "visit", id: l.id });
    }
    function due() { return !!agenda && Date.now() < agenda.until && !!support && support.id === agenda.id; }
    // On the widget he came for: the chime, or the dance.
    function play() {
        const a = agenda;
        agenda = null;
        enter(support ? "perch" : "idle", support ? "perch" : "idle");
        if (a.kind === "chime") react("chime");
        else groove(a.bpm);
    }
    // The hour struck (ClawdEvents, on the hour): with a clock widget on his display he goes to it and chimes. False when he does not.
    function hourChime() {
        if (!world || !Clawd.world || Clawd.lowMotion || Clawd.activity || menuOpen || journalOpen || chatOpen || grab || owned() || holding() || ["idle", "sit", "perch", "walk", "turn"].indexOf(mode) < 0) return false;
        const w = widgetOn("clock"), now = Date.now();
        if (!w || verdict("clock_hour", now).act !== "react") return false;
        mind = Mind.commit(mind, "clock_hour", now);
        const l = world.ledge(w.id);
        if (!(support && support.id === w.id) && l && visit(l)) agenda = { kind: "chime", id: w.id, until: now + 20000 };
        else react("chime");
        return true;
    }

    // A shell layer opened (Mind kind `layer`): under the bar he lets go, startled; otherwise he looks up at the bar.
    function shellLayer(ns, monitor) {
        const k = World.layerKind(ns);
        if (["master", "launcher", "clipboard", "desktopmenu", "traymenu", "sidemusic"].indexOf(k) < 0 || monitor && monitor !== Clawd.screenName || !Clawd.world || owned()) return;
        if (mode === "hang" || mode === "shimmy") { if (support && support.kind === "bar") letGo(true); }
        else feel("layer", x + width / 2, y - 200);
    }

    // Out from behind the window, the way he came.
    function unpeek() {
        const p = peeking;
        peeking = null;
        if (!p || !here) return idle();
        const out = clampX(here, p.side < 0 ? p.ex - width - 20 - Math.random() * 60 : p.ex + 20 + Math.random() * 60);
        if (!walkTo(out, { kind: "out" })) idle();
    }

    // Every 2 s: the cursor on another screen twice in a row and he is free -> he goes there.
    function follow() {
        const c = World.cursor(displays, here, pointer);
        const elsewhere = Clawd.world && Clawd.follow && !Clawd.lowMotion && !!c && !c.inside && !!c.display;
        awayChecks = elsewhere ? (awayScreen === c.display ? awayChecks + 1 : 1) : 0;
        awayScreen = elsewhere ? c.display : "";
        if (awayChecks < 2 || ["idle", "sit", "perch"].indexOf(mode) < 0 || Clawd.activity || menuOpen || journalOpen || chatOpen || grab) return;
        awayChecks = 0;
        cross(c.display);
    }
    // Next screen with a floor at about the same height: walk over. Otherwise walk off his edge and drop in from its top.
    function cross(name) {
        const d = display(name), h = here;
        if (!d || !h || d.id === h.id) return false;
        const side = d.x + d.w / 2 >= h.x + h.w / 2 ? 1 : -1;
        if (support) return hopDown(side) || hopDown(0);  // down first; the next check walks on
        touch();
        const n = World.beyond(displays, h, side, h.floor - height / 2);
        if (n && Math.abs(n.floor - h.floor) <= height)
            return walkTo(side > 0 ? n.x + 40 + Math.random() * 160 : n.x + n.w - width - 40 - Math.random() * 160, { kind: "cross", to: n.id });
        return walkTo(side > 0 ? h.x + h.w + 2 : h.x - width - 2, { kind: "leave", to: d.id });
    }
    function reenter(name) {
        const d = display(name);
        if (!d) return idle();
        support = null; vy = 0; fallTarget = null; lost = false;
        enter("fall", "fall");
        Clawd.screenName = d.id;
        const near = pointer && pointer.x >= d.x && pointer.x < d.x + d.w ? pointer.x - width / 2 : d.x + width + Math.random() * Math.max(0, d.w - 3 * width);
        x = Math.round(clampX(d, near));
        y = d.y - height;
    }

    // Mind's verdict on an event now, with the real context (the shell's settings included).
    function verdict(kind, now, info) {
        return Mind.decide(Object.assign({}, mind, { drag: !!grab, dead: dead || blasting, scene: owned(), menu: menuOpen || chatOpen, petpet: animation.startsWith("petpet"), hook: Clawd.activity,
            asleep: asleep, reactions: Clawd.reactions, dnd: Clawd.dnd, lowMotion: Clawd.lowMotion, mode }), kind, now, info);
    }
    readonly property var free: ["idle", "sit", "perch", "walk", "turn", "react", "sleep", "dream", "nightmare", "sleepwalk", "work"]
    // A world event through Mind; a look toward (gx, gy) or the event's own one-shot.
    function feel(kind, gx, gy) {
        if (!Clawd.world || free.indexOf(mode) < 0) return false;
        const now = Date.now(), d = verdict(kind, now);
        if (d.act !== "react" && d.act !== "glance") return false;
        let anim = d.anim, flip = false;
        if (anim === "look" && mode === "perch") { anim = "perch_look"; flip = gx < x + width / 2; }
        else if (anim === "look") anim = lookAt(gx, gy);
        react(anim, flip);
        mind = Mind.commit(mind, kind, now);
        return true;
    }
    // A shell event (5c) through Mind: returns the verdict's act ('none' | 'bubble' | 'mood' | 'react' | 'glance'). Bubbles and moods need no free pose;
    // a motion he cannot do right now degrades to a bubble. info.chain = a second one-shot after the first; info.look = [gx, gy].
    function shell(kind, info) {
        const now = Date.now(), d = verdict(kind, now, info || {});
        if (d.act === "none") return "none";
        const look = info && info.look ? info.look : [x + width / 2, y - 200];
        let act = d.act;
        if (act === "mood") setMood(info && info.mood || (kind === "rain" ? "rain" : d.anim));
        else if (act === "react" || act === "glance") {
            if (free.indexOf(mode) < 0 || owned() || holding() || mode === "dance" || act === "glance" && ["idle", "sit", "perch"].indexOf(mode) < 0) act = "bubble";
            else {
                let anim = d.anim;
                if (anim === "look") anim = mode === "perch" ? "perch_look" : lookAt(look[0], look[1]);
                react(anim, anim === "perch_look" && look[0] < x + width / 2);
                chain = info && info.chain || "";
            }
        }
        mind = Mind.commit(mind, kind, now);
        return act;
    }
    function setMood(m) { if (m !== mood) mood = m; touch(); }
    function clearMood(m) { if (mood === m) mood = ""; }
    // One of his dances at random; a slow beat (< 100 BPM) favours the headphones.
    function danceClip() {
        const all = ["dance", "dance_2", "vibe", "twirl", "wiggle", "breakdance"].filter(has);
        if (beat < 0.83 && has("vibe") && Clawd.roll() < 0.6) return "vibe";
        return all.length ? Clawd.pick(all) : "dance";
    }
    // Music: dance in a resting pose, swing under the bar; bpm (0 = unknown) retunes the pace. False when he cannot right now.
    function dance(bpm) {
        beat = bpm > 0 ? Math.max(0.6, Math.min(1.6, bpm / 120)) : 1;
        if (mode === "dance" || mode === "hang" && animation === clipName("swing")) return true;
        if (owned() || Clawd.lowMotion || Clawd.activity || menuOpen || journalOpen || chatOpen || grab) return false;
        if (mode === "hang") { if (!has("swing") || !support || support.kind !== "bar") return false; enter("hang", "swing", mirrored); grooved = true; return true; }
        if (["idle", "sit", "perch"].indexOf(mode) < 0 || !grounded() || !has("dance")) return false;
        touch();
        target = null;
        intent = null;
        resume = null;
        enter("dance", danceClip());
        return true;
    }
    // Mind approves a new dance; a dance already going only retunes (bpm 0 = unknown: normal pace).
    function groove(bpm) {
        if (mode === "dance" || mode === "hang" && animation === clipName("swing") && has("swing")) { beat = bpm > 0 ? Math.max(0.6, Math.min(1.6, bpm / 120)) : 1; return true; }
        const now = Date.now();
        if (verdict("music", now).act !== "react") return false;
        if (agenda && agenda.kind === "dance" && now < agenda.until) return false;  // on his way to the music widget
        const w = widgetOn("music"), l = w && !Clawd.lowMotion && ["idle", "sit", "perch"].indexOf(mode) >= 0 ? world.ledge(w.id) : null;
        if (l && !(support && support.id === l.id) && visit(l)) { agenda = { kind: "dance", id: l.id, bpm, until: now + 20000 }; return false; }
        if (!dance(bpm)) return false;
        mind = Mind.commit(mind, "music", now);
        return true;
    }
    function stopDance() {
        const was = grooved;
        beat = 1;
        grooved = false;
        if (mode === "dance") idle();
        else if (was && mode === "hang" && animation === clipName("swing") && has("swing")) hangAgain();
    }
    function react(anim, flip) {
        touch();
        chain = "";
        if (mode !== "react") resume = ["idle", "sit", "perch"].indexOf(mode) >= 0 ? { mode, animation, mirrored } : null;
        target = null;
        intent = null;
        enter("react", anim, flip);
    }
    function closed(id, rect) {
        if (support && support.id === id) return;  // his own window: he falls, oops on landing
        const cx = x + width / 2, cy = y + height / 2;
        const dx = Math.max(rect.x - cx, 0, cx - rect.x - rect.w), dy = Math.max(rect.y - cy, 0, cy - rect.y - rect.h);
        if (Math.hypot(dx, dy) <= 300) feel("window_close_near", cx, cy);
    }

    function spawn() {
        refresh();
        const f = hypr && Hyprland.focusedMonitor ? display(Hyprland.focusedMonitor.name) : null;
        const d = f || displays[0];
        if (!d) return;
        grab = null;
        menuOpen = false;
        support = null; hop = null; cover = null; coverId = ""; peeking = null; resume = null; lost = false;
        target = null;
        intent = null;
        Qt.callLater(() => { Clawd.screenName = d.id; });  // not inside `here`'s own evaluation (binding loop at shell start)
        if (dead) {  // his corpse, where it lies; no greeting
            if (mode !== "revive") enter("dead", "dead");
            x = Math.round(d.x + (d.w - width) / 2);
            y = d.floor - height;
            return;
        }
        enter("spawn", "spawn");
        x = Math.round(d.x + (d.w - width) / 2);
        y = d.floor - height;
        touch();
    }
    function touch() {
        tired = false;
        touchedAt = Date.now();
        drowsy.restart();
    }
    function sleepLoop() { return sleepKind === "blanket" && has("sleep_blanket") ? "sleep_blanket" : "sleep"; }
    // kind: "classic" | "blanket" | anything else (a coin flip); keepClock: the same night goes on (after a sleepwalk).
    function sleep(kind, keepClock) {
        target = null;
        tired = false;
        drowsy.stop();
        if (!grounded()) return idle();
        const fresh = !keepClock || !asleep;
        sleepKind = (kind === "classic" || kind === "blanket" ? kind === "blanket" : Clawd.roll() < 0.5) && has("sleep_blanket") ? "blanket" : "classic";
        if (fresh || !sleepAt) sleepAt = Date.now();
        if (fresh) { dreamAbort(); mumble = ""; }
        const intro = sleepKind === "blanket" && fresh && has("sleep_blanket_in");
        enter("sleep", intro ? "sleep_blanket_in" : sleepLoop(), keepClock && mode === "sleepwalk" ? mirrored : false);
    }
    // After an intro or a roll clip: back to the loop (a roll leaves him turned the other way).
    function sleepNext() {
        const loop = sleepLoop();
        if (mode === "nightmare" && animation === "sleep_jolt") { if (dreamPhase !== "view") wakeSweat(); return; }  // he stays up, eyes wide, until the scene ends
        if (mode === "sleepwalk" || animation === loop) return;
        enter(mode, loop, ["sleep_roll", "sleep_blanket_roll"].indexOf(animation) >= 0 ? !mirrored : mirrored);
    }
    function wake() {
        touch();
        if (!asleep) return;
        const long = Date.now() - sleepAt >= 15 * 60000, blanket = sleepKind === "blanket" && has("sleep_blanket_out"), groggyNow = long && has("wake_groggy");
        dreamAbort();
        if (blanket) { enter("idle", "sleep_blanket_out", mirrored); if (groggyNow) groggy = "wake_groggy"; }
        else if (groggyNow) enter("idle", "wake_groggy", mirrored);
        else enter("idle", "blink");
    }
    function wakeSweat() {
        touch();
        if (has("sweat")) react("sweat"); else enter("idle", "blink");
    }
    function sleepTick() {
        const rnd = () => Clawd.roll();
        if (mode === "sleep") {
            const now = Date.now(), ev = Dreams.nextSleepEvent(rnd, { sleptMs: now - sleepAt, now, kind: sleepKind, bubble: dreamPhase === "bubble", last: sleepLast,
                lowMotion: Clawd.lowMotion, canWalk: canWalk(), hasRoll: has(sleepKind === "blanket" ? "sleep_blanket_roll" : "sleep_roll") });
            if (ev === "roll") roll();
            else if (ev === "dream") startDream("");
            else if (ev === "talk") mumbleNow();
            else if (ev === "walk") sleepwalk();
        }
        if (asleep && mode !== "sleepwalk") { brain.interval = Dreams.tickMs(Clawd.lowMotion, Math.random); brain.start(); }
    }
    function markSleep(key) { sleepLast = Object.assign({}, sleepLast, { [key]: Date.now() }); }
    // Turn over: the roll clip, then the loop mirrored the other way (no clip: just turned).
    function roll() {
        if (mode !== "sleep") return;
        markSleep("roll");
        const clip = sleepKind === "blanket" ? "sleep_blanket_roll" : "sleep_roll";
        if (has(clip)) enter("sleep", clip, mirrored); else enter("sleep", sleepLoop(), !mirrored);
    }
    // entry: a registry entry, its id, or empty (picks one at random, unseen ones favoured). The cloud waits 30 s for a click.
    function startDream(entry) {
        if (mode !== "sleep") return false;
        const e = entry && typeof entry === "object" ? entry : Dreams.byId(typeof entry === "string" && entry ? entry : Dreams.pick(null, () => Clawd.roll(), Clawd.dreams ? Clawd.dreams.seen : {}));
        if (!e) return false;
        mumble = "";
        dream = { entry: e, seed: Math.floor(Clawd.roll() * 1000000000) };
        dreamPhase = "bubble";
        dreamAt = Date.now();
        markSleep("dream");
        bubbleTimer.restart();
        return true;
    }
    // The click on the cloud: the scene plays over his sleep (the overlay times it and calls jolt() / dreamed()).
    function openDream() {
        if (mode !== "sleep" || dreamPhase !== "bubble" || !dream) return;
        bubbleTimer.stop();
        Clawd.recordDream(dream.entry.id, dream.entry.kind);
        dreamPhase = "view";
        dreamAt = Date.now();
        mode = dream.entry.kind === "nightmare" ? "nightmare" : "dream";
    }
    // The nightmare's jumpscare: he starts awake in his sleep.
    function jolt() {
        if (mode !== "nightmare" || !has("sleep_jolt")) return;
        enter("nightmare", "sleep_jolt", mirrored);
    }
    // The scene is over: a dream returns to the sleep loop, a nightmare wakes him up sweating.
    function dreamed() {
        if (mode !== "dream" && mode !== "nightmare" || dreamPhase !== "view") return;
        const nightmare = mode === "nightmare";
        dream = null;
        dreamPhase = "";
        if (!nightmare) { mode = "sleep"; return; }
        wakeSweat();
    }
    // Whatever interrupts (drag, work, quota, chat, a wake): no dream goes on.
    function dreamAbort() {
        bubbleTimer.stop();
        mumbleTimer.stop();
        dream = null;
        dreamPhase = "";
        mumble = "";
        if (mode === "dream" || mode === "nightmare") mode = "sleep";
    }
    function mumbleNow() {
        if (mode !== "sleep" || dreamPhase) return;
        mumble = sleepKind === "blanket" && Clawd.roll() < 0.5 ? Clawd.pick(Dreams.BLANKET_MUMBLES) : Clawd.pick(Dreams.MUMBLES);
        markSleep("talk");
        mumbleTimer.restart();
    }
    function canWalk() {
        const s = stand();
        return mode === "sleep" && !!here && !!world && !support && !grab && !Clawd.lowMotion && grounded() && !!s && s.x1 - s.x0 >= 60;
    }
    // A few sleeping steps toward the side with more room, then back to sleep there.
    function sleepwalk() {
        if (!canWalk()) return false;
        const s = stand(), left = x - s.x0, right = s.x1 - x;
        const dir = Math.abs(left - right) < 80 ? (Clawd.roll() < 0.5 ? -1 : 1) : left > right ? -1 : 1;
        const to = Math.max(s.x0, Math.min(s.x1, x + dir * (60 + Clawd.roll() * 80)));
        if (Math.abs(to - x) < 30) return false;
        dreamAbort();
        markSleep("walk");
        target = to;
        enter("sleepwalk", "sleep_walk", to < x);
        return true;
    }
    // IPC / menu names of js/dreams.mjs: dream, nightmare, blanket, sleepwalk, dream_<id>, nightmare_<id>. Puts him to sleep first if needed.
    function playDream(name) {
        if (Dreams.NAMES.indexOf(name) < 0 || owned() || grab || !here || !grounded() || dead) return;
        const blanket = name === "blanket";
        if (mode !== "sleep" && !asleep || blanket && mode === "sleep") sleep(blanket ? "blanket" : "classic", blanket && mode === "sleep");
        if (blanket || mode !== "sleep") return;
        if (name === "sleepwalk") { sleepwalk(); return; }
        if (dreamPhase) dreamAbort();
        const cut = name.indexOf("_"), kind = cut < 0 ? name : name.slice(0, cut), id = cut < 0 ? Dreams.pick(kind, () => Clawd.roll(), Clawd.dreams ? Clawd.dreams.seen : {}) : name.slice(cut + 1);
        startDream(id);
    }
    function enqueueQuota(name) {
        quotaQueue = quotaQueue.concat([name]);
        runQuota();
    }
    function runQuota() {
        if (!quotaQueue.length || blast || mode === "revive" || mode === "recharge" || mode === "weekly" || mode === "surge") return;
        if (dead) { revive(); return; }
        if (holding()) { letGo(false); return; }
        if (!here || !grounded() || grab && grab.moved || ["fall", "hop", "drag"].indexOf(mode) >= 0) return;
        const name = quotaQueue[0];
        quotaQueue = quotaQueue.slice(1);
        perform(name);
    }
    Timer { interval: 1000; repeat: true; running: pet.quotaQueue.length > 0; onTriggered: pet.runQuota() }

    function perform(name) {
        if (holding()) { letGo(false); return; }  // let go first; the request is dropped
        if (Dreams.NAMES.indexOf(name) >= 0) return playDream(name);
        if (Acts.NAMES.indexOf(name) >= 0) { if (!owned() && mode !== "act" && !grab && here && grounded() && !support) startAct(name); return; }  // a special by name (IPC play)
        if (name === "limit") return explode(Math.random() < 0.5 ? "singularity" : "nuke");  // the quota ran out: either end
        if (name === "explode") return explode("singularity");
        if (name === "nuke") return explode("nuke");
        if (name === "bsod" || name === "panic") return explode(name);
        if (name === "crash") return explode(Math.random() < 0.5 ? "bsod" : "panic");
        if (name === "limit5") return Clawd.roll() < 0.5 ? explode("nuke") : explode(Math.random() < 0.5 ? "bsod" : "panic");  // the 5 h quota ran out: the nuke, or a crash, 50/50
        if (name === "revive") return revive();
        if (name === "recharge") return recharge();
        if (name === "weekly") return weekly();
        if (name === "surge") return surge();
        if (name === "limit7") return Clawd.roll() < 0.5 ? explode("singularity") : surge();  // the weekly quota ran out
        if (mode === "recharge" || mode === "weekly" || mode === "surge") return;
        if (owned() || !Clawd.manifest || !Clawd.manifest.animations[name] || grab && grab.moved) return;  // never mid-air (a let-go from the wall is falling)
        touch();
        target = null;
        intent = null;
        enter("play", name);
    }

    // His quota ran out: he freezes mid-pose (the clock stops) and the limit windows take over (kind: singularity | nuke | bsod | panic);
    // they hide him, then reappear(gx) drops his corpse at global x gx and blastDone() ends it.
    function explode(kind) {
        if (blast || !here || dead) return;
        grab = null; menuOpen = false; journalOpen = false; chatOpen = false; target = null; intent = null; resume = null; hop = null;
        dreamAbort();
        brain.stop();
        blast = { kind: ["nuke", "bsod", "panic"].indexOf(kind) >= 0 ? kind : "singularity", screen: Clawd.screenName, x, y, animation, frame: clock.frame, mirrored, scale: Clawd.scale, clock: 0 };
        mode = "explode";
        blasting = true;
    }
    function blastClock(ms) { if (blast) blast = Object.assign({}, blast, { clock: ms }); }
    function reappear(gx) {
        if (!blasting) return;
        blasting = false;
        blastHidden = false;
        die(gx);
    }
    function blastDone() { reappear(); blast = null; }
    // Dead: his corpse falls from the top of the screen at global x gx (default: the middle of his screen) and lies there.
    function die(gx) {
        const d = (gx !== undefined ? displayAt(gx, here ? here.y + here.h / 2 : 0) : null) || here || displays[0];
        if (!d) return;
        grab = null; menuOpen = false; journalOpen = false; chatOpen = false; target = null; intent = null; resume = null; hop = null;
        support = null; cover = null; coverId = ""; peeking = null; lost = false; fallTarget = null;
        dreamAbort();
        dead = true;
        deadAt = Date.now();
        Config.setSetting("addonsV2ClawdDead", deadAt);
        Clawd.screenName = d.id;
        vy = 0;
        enter("corpse", "dead");
        x = Math.round(clampX(d, (gx !== undefined ? gx : d.x + d.w / 2) - width / 2));
        y = d.y - height;
    }
    // Back to life: ClawdRevive plays on his screen's overlay, which calls revived() at its end.
    function revive() {
        if (!dead || mode === "revive" || blast) return;
        if (mode === "corpse" && here) placeAt(contact().x, here.floor);  // still falling: down at once
        grab = null;
        menuOpen = false;
        reviveAt = Date.now();
        enter("revive", "dead");
    }
    function revived() {
        if (mode !== "revive") return;
        dead = false;
        deadAt = 0;
        Config.setSetting("addonsV2ClawdDead", 0);
        touch();
        idle();
    }
    // The 5 h limit is back: ClawdRecharge plays on his screen's overlay (he stays where he stands), whose end calls
    // recharged(). A dead Clawd simply comes back to life instead.
    function recharge() {
        if (dead) return revive();
        if (blast || !here || !grounded() || grab && grab.moved || ["recharge", "weekly", "surge", "revive", "corpse", "carried", "explode", "fall", "hop", "drag"].indexOf(mode) >= 0) return;
        grab = null; menuOpen = false; journalOpen = false; chatOpen = false; target = null; intent = null; resume = null; hop = null;
        rechargeAt = Date.now();
        enter("recharge", "idle");
    }
    // The weekly limit is back: the symphony (ClawdSymphony on his screen's overlay; the curtains hide his move to the
    // stage), whose end calls weeklied(). Dead: he comes back to life instead.
    function weekly() {
        if (dead) return revive();
        if (blast || !here || !grounded() || grab && grab.moved || ["recharge", "weekly", "surge", "revive", "corpse", "carried", "explode", "fall", "hop", "drag"].indexOf(mode) >= 0) return;
        grab = null; menuOpen = false; journalOpen = false; chatOpen = false; target = null; intent = null; resume = null; hop = null;
        weeklyAt = Date.now();
        enter("weekly", "idle");
    }
    function weeklied() {
        if (mode !== "weekly") return;
        touch();
        idle();
        busy();
    }
    // The weekly limit ran out, the superpowered way: ClawdSurge on his screen's overlay (an orb hits him, he absorbs it,
    // dashes to an empty workspace, summons six helpers and recharges the week); he ends in the middle of his screen,
    // back on the workspace he left: surged(gx). Dead: he comes back to life instead.
    function surge() {
        if (dead) return revive();
        if (blast || !here || !grounded() || grab && grab.moved || ["recharge", "weekly", "surge", "revive", "corpse", "carried", "explode", "fall", "hop", "drag"].indexOf(mode) >= 0) return;
        grab = null; menuOpen = false; journalOpen = false; chatOpen = false; target = null; intent = null; resume = null; hop = null;
        surgeAt = Date.now();
        surgeHome = null;
        enter("surge", "idle");
    }
    // During his dash: an empty workspace on his screen (away), then the one he left (back).
    function surgeWorkspace(away) {
        if (!hypr || mode !== "surge") return;
        const name = Clawd.screenName, m = Hyprland.monitors.values.find(v => v.name === name);
        if (away) surgeHome = m && m.activeWorkspace ? m.activeWorkspace.id : null;
        else if (surgeHome === null) return;
        // Lua dispatchers (the shell's Hyprland takes hl.dsp.*, like the bar's workspace buttons)
        if (!Hyprland.focusedMonitor || Hyprland.focusedMonitor.name !== name) Hyprland.dispatch("hl.dsp.focus({ monitor = \"" + name + "\" })");
        Hyprland.dispatch(away ? "hl.dsp.focus({ workspace = \"emptynm\" })" : "hl.dsp.focus({ workspace = " + surgeHome + " })");
        if (!away) surgeHome = null;
    }
    function surged(gx) {
        if (mode !== "surge") return;
        if (surgeHome !== null) surgeWorkspace(false);
        support = null; cover = null; coverId = ""; peeking = null;
        if (here && gx !== undefined) { x = Math.round(clampX(here, gx - width / 2)); placeAt(contact().x, here.floor); }
        touch();
        idle();
        busy();
    }
    function recharged() {
        if (mode !== "recharge") return;
        touch();
        idle();
        busy();
    }
    function clockRunning() { return clock.running; }  // test hook

    // Middle click pets him; petting him again while he is being petted gets hearts.
    // At work he only startles, then goes back to it.
    function petpet() {
        if (Clawd.activity === "work") perform("startled");
        else perform(animation.startsWith("petpet") ? "petpetheart" : "petpet");
    }

    // Input from the overlay where the press started, already in global coordinates.
    function press(button, gx, gy) {
        touch();
        if (button === Qt.RightButton) { openMenu(); return; }
        if (mode === "recharge" || mode === "weekly" || mode === "surge") return;
        if (dead) {  // he does not react any more, but his corpse can be carried (only where it lies)
            if (button === Qt.LeftButton && ["dead", "carried"].indexOf(mode) >= 0) grab = { x: gx, y: gy, dx: gx - x, dy: gy - y, moved: false };
            return;
        }
        if (button === Qt.MiddleButton) { petpet(); return; }
        grab = { x: gx, y: gy, dx: gx - x, dy: gy - y, moved: false };
    }
    function move(gx, gy) {
        if (!grab) return;
        if (!grab.moved && Math.abs(gx - grab.x) + Math.abs(gy - grab.y) < 4) return;
        if (!grab.moved) {
            grab.moved = true;
            agenda = null;
            menuOpen = false;
            if (dead) {
                if (mode !== "dead") { grab = null; return; }
                enter("carried", "dead");
            } else {
                target = null;
                intent = null; support = null; hop = null; cover = null; coverId = ""; peeking = null; resume = null;
                enter("drag", "drag");
            }
        }
        x = gx - grab.dx;
        y = gy - grab.dy;
    }
    // Dropped: he falls onto whatever is below, a window top included.
    function release(gx, gy) {
        const g = grab, swallow = dbl;
        grab = null;
        dbl = false;
        if (!g) return;
        touch();
        if (dead) {  // dropped corpse: it falls to the floor of the screen it was dropped on
            if (!g.moved || mode !== "carried") return;
            refresh();
            const d = displayAt(gx === undefined ? x + width / 2 : gx, gy === undefined ? y + height / 2 : gy);
            if (d) { Clawd.screenName = d.id; x = clampX(d, x); y = Math.max(y, d.y); }
            vy = 0;
            enter("corpse", "dead");
            return;
        }
        if (!g.moved) {
            if (swallow) return;
            clickTimer.restart();  // a double-click turns this into the chat
            return;
        }
        refresh();
        const d = displayAt(gx === undefined ? x + width / 2 : gx, gy === undefined ? y + height / 2 : gy);
        if (!d) return;
        Clawd.screenName = d.id;
        x = clampX(d, x);
        y = Math.max(y, d.y);
        vy = 0;
        support = null;
        lost = false;
        fallTarget = null;
        enter("fall", "fall");
    }
    // A session got busy, needs the user or went quiet: stop wandering (and wake) or go back to normal life.
    function busy() {
        if (mode === "chat") return;  // bubbles still show, he stays in the chat
        if ((Clawd.activity || mode === "work") && holding()) { letGo(false); return; }  // drop -> land -> work
        if ((Clawd.activity || mode === "work") && ["idle", "sit", "sleep", "dream", "nightmare", "sleepwalk", "walk", "turn", "work", "perch", "teeter", "peek", "dance", "act"].indexOf(mode) >= 0) idle();
    }
    // Every 8-12 s at work: the other variant of the loop, or a sweat break when the lead session is strained.
    function shuffle() {
        if (mode !== "work" || Clawd.activity !== "work" || !Clawd.manifest) return;
        const fam = Clawd.workAnim, all = Clawd.variants(fam);
        if (Clawd.strained && animation !== "sweat" && Clawd.roll() < 1 / 3 && Clawd.manifest.animations.sweat) enter("work", "sweat");
        else if (all.length > 1) {  // never the one already playing
            const others = all.filter(a => a !== animation);
            enter("work", Clawd.pick(others));
        } else if (animation !== fam) enter("work", fam);
    }
    // The single click, 250 ms late (a double-click cancels it): the journal.
    function singleClick() {
        if (dead || chatOpen) return;
        if (!journalOpen) journalTab = "sessions";
        journalOpen = !journalOpen;
        if (asleep) wake();
        else if (["work", "fall", "hop", "climb", "hang", "shimmy", "drop", "chat"].indexOf(mode) < 0) enter("land", Math.random() < 0.5 ? "land" : "blink");
    }
    // Double-click on him (the overlay calls it): the chat.
    function doubleClick() {
        clickTimer.stop();
        dbl = false;
        if (dead || blasting || owned() || ["recharge", "weekly", "surge"].indexOf(mode) >= 0) return;
        dbl = true;
        if (typeof Clawd.chat === "undefined" || Clawd.chat) chatOpen = true;
    }
    function chatClip() {
        if (chatPhase === "wait") return "think";
        if (chatPhase === "talk") return has("talk") ? "talk" : "idle";
        return Math.random() < 0.25 ? "blink" : "idle";
    }
    // He stays put, facing the screen centre (the panel).
    function enterChat() {
        const mid = here ? here.x + here.w / 2 : x + width / 2;
        enter("chat", chatClip(), mid < x + width / 2);
    }
    // A notification popup (qs-popups) on his screen: he walks under it, looks up, reads. False when he does not.
    function notifWalk() {
        if (!world || !Clawd.world || Clawd.lowMotion || !here || support || chatOpen || menuOpen || journalOpen || grab || owned() || holding() || Clawd.activity
            || ["idle", "sit"].indexOf(mode) < 0 || !grounded()) return false;
        const r = (world.layerRects || []).find(r => r.ns === "qs-popups" && r.display === here.id);
        if (!r || verdict("notif", Date.now()).act !== "react") return false;
        mind = Mind.commit(mind, "notif", Date.now());
        const to = clampX(here, r.x + r.w / 2 - width / 2);
        touch();
        if (!walkTo(to, { kind: "notif" })) lookRead();
        return true;
    }
    function lookRead() { react("look_up"); chain = "read"; }
    function openMenu() {
        if (["revive", "corpse", "carried", "recharge", "weekly", "surge"].indexOf(mode) >= 0) return;
        if (mode === "walk" || mode === "turn" || mode === "act") idle();
        journalOpen = false;
        chatOpen = false;  // the menu takes over from the chat
        menuOpen = true;
    }

    onHeightChanged: if (!switching) placeOnSupport()
    onHereChanged: if (here) placeOnSupport(); else if (displays.length) Qt.callLater(spawn)  // spawn() rewrites screenName, which here depends on
    onSummonChanged: spawn()
    onChatOpenChanged: {
        if (chatOpen && (dead || blasting || owned() || ["recharge", "weekly", "surge"].indexOf(mode) >= 0)) { chatOpen = false; return; }
        if (chatOpen) { menuOpen = false; journalOpen = false; target = null; intent = null; resume = null; chain = ""; if (asleep) wake(); enterChat(); }
        else if (mode === "chat") idle();
    }
    onChatPhaseChanged: if (mode === "chat" && chatOpen) enterChat()
    Component.onCompleted: {
        deadAt = Number(Config.getSetting("addonsV2ClawdDead", 0)) || 0;
        dead = deadAt > 0;
        spawn();
        if (dead && Date.now() - deadAt >= reviveAfter) rising.start();  // 3 h later, the shell starting again revives him
    }

    Connections {
        target: Clawd
        function onCommand(name, arg) { if (name === "quota") pet.enqueueQuota(arg); else if (name === "play" || name === "react") pet.perform(arg); }
        function onActivityChanged() { pet.busy(); }
        function onSessionStarted() { pet.revive(); }  // a new Claude Code / Codex session brings him back
        function onWorkAnimChanged() { if (pet.mode === "work" && Clawd.activity === "work") pet.enter("work", Clawd.variant(Clawd.workAnim)); }
    }
    // Window reactions (Mind arbitrates); physics (his own window going away) is revalidate's.
    Connections {
        target: pet.world
        function onUpdated() { Qt.callLater(pet.revalidate); }
        function onWindowOpened(id, rect) { if (rect.display === Clawd.screenName) pet.feel("window_open", rect.x + rect.w / 2, rect.y + rect.h / 2); }
        function onWindowClosed(id, rect) { pet.closed(id, rect); }
        function onLayerOpened(ns, monitor) { pet.shellLayer(ns, monitor); }
        function onFocusMoved(id) { const w = pet.world.win(id); if (w && w.display === Clawd.screenName) pet.feel("focus", w.x + w.w / 2, w.y + w.h / 2); }
        function onWorkspaceSwitched(monitor) { if (monitor === Clawd.screenName && !pet.support) pet.feel("workspace", 0, 0); }  // on a window he just falls
    }

    // The single clock for his frames; every overlay sprite shows clock.frame.
    ClawdSprite {
        id: clock
        running: !pet.blasting
        animation: pet.animation
        reverse: pet.reverse
        speed: pet.speed
        onFinished: pet.next()
    }
    Timer {
        id: shuffler
        interval: 10000; repeat: true
        running: pet.mode === "work" && Clawd.activity === "work"
        onTriggered: { interval = 8000 + Math.random() * 4000; pet.shuffle(); }
    }
    Timer { id: clickTimer; interval: 250; onTriggered: pet.singleClick() }
    Timer { id: rising; interval: 1500; onTriggered: pet.revive() }
    Timer { id: brain; onTriggered: pet.asleep ? pet.sleepTick() : pet.mode === "idle" || pet.mode === "perch" ? pet.think() : pet.next() }
    Timer { id: bubbleTimer; interval: 30000; onTriggered: if (pet.dreamPhase === "bubble") { pet.dreamPhase = ""; pet.dream = null; } }
    Timer { id: mumbleTimer; interval: 3500; onTriggered: pet.mumble = "" }
    Timer { id: drowsy; interval: pet.sleepAfter; onTriggered: { pet.tired = true; if (["sit", "perch"].indexOf(pet.mode) >= 0 || pet.mode === "idle" && pet.animation === "idle") pet.sleep(); } }
    Timer { interval: 16; repeat: true; running: ["walk", "fall", "hop", "corpse", "climb", "shimmy", "act", "sleepwalk"].indexOf(pet.mode) >= 0; onTriggered: pet.step() }
    Timer { interval: 2000; repeat: true; running: Clawd.world && Clawd.follow && !Clawd.lowMotion && !!pet.world; onTriggered: pet.follow() }
}
