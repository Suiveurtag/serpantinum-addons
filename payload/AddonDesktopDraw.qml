import QtQuick
import "reusables"
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root
    color: "transparent"
    visible: active || reveal > 0
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    focusable: active
    mask: Region { item: root.active ? drawingInput : null }
    WlrLayershell.namespace: "qs-addon-desktop-draw"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    property var targetScreen: null
    screen: targetScreen
    property bool active: false
    property real reveal: active ? 1 : 0
    property string tool: "pen"
    property real thickness: 4
    property int colorIndex: 0
    readonly property var colors: [ThemeBackend.mauve, ThemeBackend.red, ThemeBackend.green, ThemeBackend.peach, ThemeBackend.text]
    property var strokes: []
    property var current: null
    property var undoStack: []
    property var redoStack: []
    property bool eraseSaved: false
    Behavior on reveal { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    onRevealChanged: {
        if (reveal === 0 && !active) { strokes = []; undoStack = []; redoStack = []; }
    }
    onStrokesChanged: ink.requestPaint()
    onCurrentChanged: ink.requestPaint()
    function s(value) { return Scaler.s(value); }
    function open() {
        if (active) return;
        targetScreen = Quickshell.cursorScreen ?? Quickshell.screens.find(screen => Hyprland.focusedMonitor && screen.name === Hyprland.focusedMonitor.name) ?? Quickshell.screens[0];
        if (!targetScreen) return;
        // Prevent other modal pointer tools from consuming drawing gestures.
        Quickshell.execDetached(["quickshell", "-p", Caching.mainQml, "ipc", "call", "addonDesktopZoom", "deactivate"]);
        Quickshell.execDetached(["quickshell", "-p", Caching.mainQml, "ipc", "call", "addonMouseSpotlight", "deactivate"]);
        active = true;
    }
    function close() { current = null; active = false; }
    function checkpoint() { undoStack = undoStack.concat([strokes]); redoStack = []; }
    function undo() {
        current = null;
        if (!undoStack.length) return;
        redoStack = redoStack.concat([strokes]);
        strokes = undoStack[undoStack.length - 1]; undoStack = undoStack.slice(0, -1);
    }
    function redo() {
        current = null;
        if (!redoStack.length) return;
        undoStack = undoStack.concat([strokes]);
        strokes = redoStack[redoStack.length - 1]; redoStack = redoStack.slice(0, -1);
    }
    function clear() { current = null; if (strokes.length) { checkpoint(); strokes = []; } }
    function setTool(value) { current = null; tool = value; }
    function distanceToSegment(point, a, b) {
        let dx = b.x - a.x, dy = b.y - a.y;
        let t = dx * dx + dy * dy ? Math.max(0, Math.min(1, ((point.x-a.x)*dx + (point.y-a.y)*dy) / (dx*dx+dy*dy))) : 0;
        return Math.hypot(point.x-a.x-t*dx, point.y-a.y-t*dy);
    }
    function eraseAt(point) {
        let remaining = strokes.filter(stroke => {
            let pts = geometry(stroke), radius = s(12) + stroke.size / 2;
            if (pts.length === 1) return Math.hypot(point.x-pts[0].x, point.y-pts[0].y) > radius;
            for (let i = 1; i < pts.length; i++) if (distanceToSegment(point, pts[i-1], pts[i]) <= radius) return false;
            return true;
        });
        if (remaining.length === strokes.length) return;
        if (!eraseSaved) { checkpoint(); eraseSaved = true; }
        strokes = remaining;
    }
    function geometry(stroke) {
        if (stroke.tool === "pen") return stroke.points;
        let a = stroke.points[0], b = stroke.points[stroke.points.length-1];
        if (stroke.tool === "rectangle") return [a, {x:b.x,y:a.y}, b, {x:a.x,y:b.y}, a];
        let pts = [], cx = (a.x+b.x)/2, cy = (a.y+b.y)/2;
        for (let i = 0; i <= 96; i++) {
            let angle = i / 96 * Math.PI * 2;
            pts.push({x:cx + Math.abs(b.x-a.x)/2*Math.cos(angle), y:cy + Math.abs(b.y-a.y)/2*Math.sin(angle)});
        }
        return pts;
    }
    function begin(mouse) {
        eraseSaved = false;
        if (tool === "eraser" || mouse.button === Qt.RightButton) { eraseAt(mouse); return; }
        current = {tool:tool, color:String(colors[colorIndex]), size:s(thickness), points:[{x:mouse.x, y:mouse.y}]};
    }
    function move(mouse) {
        if (tool === "eraser" || drawingInput.pressedButtons & Qt.RightButton) { eraseAt(mouse); return; }
        if (!current) return;
        let point = {x:mouse.x,y:mouse.y};
        let last = current.points[current.points.length-1];
        if (Math.hypot(point.x-last.x, point.y-last.y) < 0.8) return;
        current = Object.assign({}, current, {points: current.tool === "pen" ? current.points.concat([point]) : [current.points[0], point]});
    }
    function finish() {
        if (!current) return;
        checkpoint(); strokes = strokes.concat([current]); current = null;
    }
    IpcHandler {
        target: "addonDesktopDraw"
        function toggle(): void { root.active ? root.close() : root.open(); }
        function activate(): void { root.open(); }
        function deactivate(): void { root.close(); }
        function status(): string { return JSON.stringify({active:root.active, strokes:root.strokes.length, tool:root.tool, thickness:root.thickness}); }
    }
    Shortcut { sequence: "Escape"; enabled: root.active; onActivated: root.close() }
    Shortcut { sequence: "Ctrl+Z"; enabled: root.active; onActivated: root.undo() }
    Shortcut { sequence: "Ctrl+Shift+Z"; enabled: root.active; onActivated: root.redo() }
    Shortcut { sequence: "Delete"; enabled: root.active; onActivated: root.clear() }
    Shortcut { sequence: "P"; enabled: root.active; onActivated: root.setTool("pen") }
    Shortcut { sequence: "C"; enabled: root.active; onActivated: root.setTool("circle") }
    Shortcut { sequence: "R"; enabled: root.active; onActivated: root.setTool("rectangle") }
    Shortcut { sequence: "E"; enabled: root.active; onActivated: root.setTool("eraser") }
    Canvas {
        id: ink
        anchors.fill: parent
        opacity: root.reveal
        onPaint: {
            let ctx = getContext("2d"); ctx.clearRect(0,0,width,height);
            let all = root.current ? root.strokes.concat([root.current]) : root.strokes;
            for (let stroke of all) {
                let pts = root.geometry(stroke);
                ctx.strokeStyle = stroke.color; ctx.fillStyle = stroke.color;
                ctx.lineWidth = stroke.size; ctx.lineCap = "round"; ctx.lineJoin = "round";
                if (pts.length === 1) { ctx.beginPath(); ctx.arc(pts[0].x,pts[0].y,stroke.size/2,0,Math.PI*2); ctx.fill(); continue; }
                ctx.beginPath(); ctx.moveTo(pts[0].x,pts[0].y);
                if (stroke.tool === "pen") {
                    for (let i=1;i<pts.length-1;i++) ctx.quadraticCurveTo(pts[i].x,pts[i].y,(pts[i].x+pts[i+1].x)/2,(pts[i].y+pts[i+1].y)/2);
                } else for (let i=1;i<pts.length-1;i++) ctx.lineTo(pts[i].x,pts[i].y);
                ctx.lineTo(pts[pts.length-1].x,pts[pts.length-1].y); ctx.stroke();
            }
        }
    }
    MouseArea {
        id: drawingInput
        anchors.fill: parent
        enabled: root.active
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.tool === "eraser" ? Qt.PointingHandCursor : Qt.CrossCursor
        onPressed: mouse => root.begin(mouse)
        onPositionChanged: mouse => { if (pressed) root.move(mouse); }
        onReleased: root.finish()
        onCanceled: root.current = null
        onWheel: wheel => {
            root.thickness = Math.max(2,Math.min(24,root.thickness + (wheel.angleDelta.y !== 0 ? wheel.angleDelta.y/120 : wheel.pixelDelta.y/40)));
            wheel.accepted = true;
        }
    }
    AddonGlassSurface {
        id: toolbar
        width: tools.implicitWidth + root.s(24); height: root.s(66)
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height - height - root.s(24) + root.s(16)*(1-root.reveal)
        opacity: root.reveal
        scale: 0.96 + root.reveal*0.04
        radius: root.s(18)
        surfaceColor: ThemeBackend.base
        glassSource: toolbarBackdrop
        WallpaperBlur {
            id: toolbarBackdrop
            surfaceEnabled: ThemeBackend.glassActive
            anchors.fill: parent
            radius: parent.radius
            visible: active && !ThemeBackend.liquidGlass
            z: -1
        }
        border.width: root.s(1); border.color: Qt.alpha(ThemeBackend.mauve,0.4)
        // Consume clicks in toolbar gaps so they cannot create stray marks.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => { wheel.accepted = true; } }
        Row {
            id: tools
            anchors.centerIn: parent
            spacing: root.s(5)
            Repeater {
                model: [
                    {tool:"pen",label:"󰏫",hint:"Pen · P"}, {tool:"circle",label:"○",hint:"Circle · C"},
                    {tool:"rectangle",label:"□",hint:"Box · R"}, {tool:"eraser",label:"󰇾",hint:"Eraser · E"}
                ]
                delegate: AddonGlassSurface {
                    required property var modelData
                    width: root.s(40); height: root.s(42); radius: root.s(10)
                    surfaceColor: root.tool === modelData.tool ? Qt.alpha(ThemeBackend.mauve,0.2) : toolMouse.containsMouse ? ThemeBackend.surface0 : "transparent"
                    Behavior on surfaceColor { ColorAnimation { duration: 160 } }
                    scale: toolMouse.pressed ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Text { anchors.centerIn: parent; text: modelData.label; color: root.tool === modelData.tool ? ThemeBackend.mauve : ThemeBackend.text; font.family:"Iosevka Nerd Font"; font.pixelSize:root.s(23) }
                    MouseArea { id: toolMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; enabled:root.active; onClicked:root.setTool(modelData.tool) }
                }
            }
            Rectangle { width:root.s(1);height:root.s(28); y:root.s(7);color:ThemeBackend.surface1 }
            Repeater {
                model: root.colors
                delegate: Rectangle {
                    required property int index
                    required property var modelData
                    width:root.s(30);height:root.s(42);color:"transparent"
                    Rectangle {
                        anchors.centerIn:parent;width:root.s(root.colorIndex === index ? 22 : 17);height:width;radius:width/2;color:modelData
                        border.width:root.colorIndex === index ? root.s(2):0;border.color:ThemeBackend.text
                        Behavior on width { NumberAnimation { duration:160;easing.type:Easing.OutCubic } }
                    }
                    MouseArea { anchors.fill:parent;cursorShape:Qt.PointingHandCursor;enabled:root.active;onClicked:root.colorIndex=index }
                }
            }
            Text { width:root.s(38);height:root.s(42);verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignHCenter;text:Math.round(root.thickness)+"px";color:ThemeBackend.subtext0;font.family:ThemeBackend.fontFamily;font.pixelSize:root.s(11) }
            Repeater {
                model: [{label:"↶",action:"undo"},{label:"󰆴",action:"clear"},{label:"×",action:"close"}]
                delegate: AddonGlassSurface {
                    required property var modelData
                    width:root.s(36);height:root.s(42);radius:root.s(10)
                    surfaceColor:actionMouse.containsMouse ? ThemeBackend.surface0 : "transparent"
                    Behavior on surfaceColor { ColorAnimation { duration:160 } }
                    Text { anchors.centerIn:parent;text:modelData.label;color:ThemeBackend.text;font.family:"Iosevka Nerd Font";font.pixelSize:root.s(21) }
                    MouseArea { id:actionMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;enabled:root.active;onClicked:{ if(modelData.action==="undo")root.undo();else if(modelData.action==="clear")root.clear();else root.close(); } }
                }
            }
        }
    }
}
