"""Keep upstream animations in step with the render loop."""


def _pulse(text, *, name, indent, running, replacement):
    pad = ' ' * indent
    old = (f'{pad}Timer {{\n'
           f'{pad}    interval: 45\n'
           f'{pad}    running: {running}\n'
           f'{pad}    repeat: true\n'
           f'{pad}    onTriggered: {{')
    if old not in text:
        return text
    if text.count(old) != 1:
        raise ValueError(f'Ambiguous {name} pulse animation')
    marker = f'\n{pad}property real pulseOp: 0.0'
    if text.count(marker) != 1 or f'id: {name}' in text:
        raise ValueError(f'{name} pulse anchor changed')
    text = text.replace(marker, f'\n{pad}id: {name}\n{marker}', 1)
    new = (f'{pad}FrameAnimation {{\n'
           f'{pad}    running: {replacement}\n'
           f'{pad}    onTriggered: {{')
    text = text.replace(old, new, 1)
    start = text.index(new)
    end = text.index(f'\n{pad}    }}\n{pad}}}', start)
    block = text[start:end].replace('parent.pulseOp', f'{name}.pulseOp').replace('parent.pulseSc', f'{name}.pulseSc')
    return text[:start] + block + text[end:]


def network(text):
    return _pulse(text, name='networkPulse', indent=20,
                  running='window.visible && parent.opacity > 0.01',
                  replacement='window.visible && coreContainer.visible && (window.currentConn || coreContainer.showPassword) && window.showInfoView && window.currentPower && !coreContainer.isMyDisconnecting')


def volume(text):
    return _pulse(text, name='volumePulse', indent=28,
                  running='window.visible && (parent.opacity > 0.01 || !window.activeMute)',
                  replacement='window.visible && !window.activeMute')


def visualizer(text):
    old = '''    Timer {
        interval: 33
        running: root.previewDemo && root.active && root.visible
        repeat: true
        onTriggered: root.demoTick++
    }'''
    new = '''    FrameAnimation {
        running: root.previewDemo && root.active && root.visible
        onTriggered: root.demoTick++
    }'''
    if text.count(old) > 1:
        raise ValueError('Ambiguous visualizer preview animation')
    text = text.replace(old, new, 1)
    old_clock = '''        property real pendingTime: 0.0
        running: root.settling && root.visible
        onTriggered: {
            levelAnimation.pendingTime += frameTime;
            if (levelAnimation.pendingTime + frameTime / 2 < 1 / 60) return;
            let elapsed = levelAnimation.pendingTime;
            levelAnimation.pendingTime = 0.0;'''
    new_clock = '''        property real pendingTime: 0.0
        property real elapsedTime: 0.0
        running: root.settling && root.visible
        onRunningChanged: if (!running) { pendingTime = 0; elapsedTime = 0; }
        onTriggered: {
            const frameBudget = 1 / 60;
            levelAnimation.pendingTime += frameTime;
            levelAnimation.elapsedTime += frameTime;
            if (frameTime >= frameBudget * 0.7) levelAnimation.pendingTime = Math.max(levelAnimation.pendingTime, frameBudget);
            if (levelAnimation.pendingTime + 0.0005 < frameBudget) return;
            let elapsed = levelAnimation.elapsedTime;
            levelAnimation.elapsedTime = 0.0;
            levelAnimation.pendingTime -= frameBudget;
            if (levelAnimation.pendingTime >= frameBudget) levelAnimation.pendingTime %= frameBudget;'''
    carry_clock = new_clock.replace(
        '            if (frameTime >= frameBudget * 0.7) levelAnimation.pendingTime = Math.max(levelAnimation.pendingTime, frameBudget);\n', '')
    previous_clock = carry_clock.replace(
        '            levelAnimation.pendingTime -= frameBudget;\n'
        '            if (levelAnimation.pendingTime >= frameBudget) levelAnimation.pendingTime %= frameBudget;',
        '            levelAnimation.pendingTime = levelAnimation.pendingTime < frameBudget ? 0 : levelAnimation.pendingTime % frameBudget;')
    if text.count(old_clock) > 1:
        raise ValueError('Ambiguous visualizer frame clock')
    return text.replace(old_clock, new_clock, 1).replace(previous_clock, new_clock, 1).replace(carry_clock, new_clock, 1)


def lumen_clock(text):
    old = '''    Timer {
        interval: root.showSeconds ? 40 : 1000
        running: root.visible
        repeat: true
        onTriggered: root.tick()
    }'''
    new = '''    FrameAnimation {
        property real pendingTime: 0.0
        running: root.visible && root.showSeconds
        onRunningChanged: if (!running) pendingTime = 0.0
        onTriggered: {
            const frameBudget = 1 / 60;
            pendingTime += frameTime;
            if (frameTime >= frameBudget * 0.7) pendingTime = Math.max(pendingTime, frameBudget);
            if (pendingTime + 0.0005 < frameBudget) return;
            pendingTime -= frameBudget;
            if (pendingTime >= frameBudget) pendingTime %= frameBudget;
            root.tick();
        }
    }

    Timer {
        interval: 1000
        running: root.visible && !root.showSeconds
        repeat: true
        onTriggered: root.tick()
    }'''
    if text.count(old) > 1:
        raise ValueError('Ambiguous Lumen clock')
    return text.replace(old, new, 1)


def stopwatch(text):
    old = '''    Timer {
        id: fastTicker
        interval: 32
        repeat: true
        triggeredOnStart: true
        running: root.visible && root.widgetVisible && FocusTimer.isStopwatchRunning
        onTriggered: root.liveMs = FocusTimer.swAccumulatedMs + (Date.now() - FocusTimer.swStartEpoch)
    }'''
    new = '''    FrameAnimation {
        id: fastTicker
        running: root.visible && root.widgetVisible && FocusTimer.isStopwatchRunning

        function updateTime() {
            root.liveMs = FocusTimer.swAccumulatedMs + (Date.now() - FocusTimer.swStartEpoch);
        }

        onRunningChanged: if (running) updateTime()
        onTriggered: updateTime()
    }'''
    if text.count(old) > 1:
        raise ValueError('Ambiguous stopwatch display clock')
    return text.replace(old, new, 1)


def lock_editor(text):
    old = '''                        onVisibleChanged: if (visible) chrome.place()

                        Timer {
                            interval: 33
                            repeat: true
                            running: chrome.visible
                            onTriggered: chrome.place()
                        }'''
    new = '''                        function schedulePlacement() {
                            if (visible) Qt.callLater(chrome.place);
                        }

                        onVisibleChanged: schedulePlacement()
                        onImplicitWidthChanged: schedulePlacement()
                        onImplicitHeightChanged: schedulePlacement()

                        Connections {
                            target: win
                            function onChromeTargetChanged() { chrome.schedulePlacement(); }
                        }

                        Connections {
                            target: win.chromeTarget
                            function onXChanged() { chrome.schedulePlacement(); }
                            function onYChanged() { chrome.schedulePlacement(); }
                            function onWidthChanged() { chrome.schedulePlacement(); }
                            function onHeightChanged() { chrome.schedulePlacement(); }
                            function onRotationChanged() { chrome.schedulePlacement(); }
                            function onScaleChanged() { chrome.schedulePlacement(); }
                        }

                        Connections {
                            target: win.page === 0 ? clockFrame : panelFrame
                            function onXChanged() { chrome.schedulePlacement(); }
                            function onYChanged() { chrome.schedulePlacement(); }
                            function onKChanged() { chrome.schedulePlacement(); }
                            function onScaleChanged() { chrome.schedulePlacement(); }
                        }

                        Connections {
                            target: panelStage
                            function onPanelLeftChanged() { chrome.schedulePlacement(); }
                            function onPanelTopChanged() { chrome.schedulePlacement(); }
                        }

                        Connections {
                            target: toolbar
                            function onYChanged() { chrome.schedulePlacement(); }
                        }'''
    if text.count(old) > 1:
        raise ValueError('Ambiguous lock editor placement')
    return text.replace(old, new, 1)


def launcher(text):
    old_rank = '''                    if (this.text && this.text.trim().length > 0) {
                        launcherWindow.usageRanks = JSON.parse(this.text);
                        if (!launcherWindow.isVisible || appModel.count === 0) {
                            launcherWindow.loadApps();
                            launcherWindow.appsLoaded = true;
                            if (launcherWindow.currentTabIndex === 0) {
                                launcherWindow.executeFilter(searchInput.text);
                            }
                        }
                    }'''
    new_rank = '''                    const snapshot = this.text.trim();
                    if (!snapshot || snapshot === launcherWindow.rankSnapshot) return;
                    launcherWindow.usageRanks = JSON.parse(snapshot);
                    launcherWindow.rankSnapshot = snapshot;
                    launcherWindow.appsLoaded = false;
                    if ((!launcherReveal.active && !launcherWindow.isVisible) || appModel.count === 0) {
                        launcherWindow.loadApps();
                        if (launcherWindow.currentTabIndex === 0)
                            launcherWindow.executeFilter(searchInput.text);
                    }'''
    edits = {
        old_rank: new_rank,
        '    property var usageRanks: ({ "focus": {}, "launch": {}, "context": {} })':
            '    property string rankSnapshot: ""\n    property var usageRanks: ({ "focus": {}, "launch": {}, "context": {} })',
        '        loadApps();\n        appsLoaded = true;': '        loadApps();',
        '''            if (!launcherWindow.appsLoaded) {
                launcherWindow.loadApps();
                launcherWindow.appsLoaded = true;
            }''': '            if (!launcherWindow.appsLoaded) launcherWindow.loadApps();',
        '            introItems = 0.0;\n            launcherWindow.appsLoaded = false;\n            appList.resetScroll();':
            '            introItems = 0.0;\n            appList.resetScroll();',
        '''            if (launcherWindow.smartRanking) {
                loadApps();
                executeFilter("");
            }
        }
    }

    function normalizeDecimalCommas''': '''        }
    }

    function normalizeDecimalCommas''',
        '        launcherWindow.allApps = finalArr;':
            '        launcherWindow.allApps = finalArr;\n        launcherWindow.appsLoaded = true;',
        '            closeDuration: launcherWindow.isCentered ? 200 : 150': '''            closeDuration: launcherWindow.isCentered ? 200 : 150
            onActiveChanged: {
                if (!active && launcherWindow.smartRanking && !launcherWindow.appsLoaded) {
                    launcherWindow.loadApps();
                    if (launcherWindow.currentTabIndex === 0) launcherWindow.executeFilter("");
                }
            }''',
    }
    if old_rank not in text:
        return text
    if any(text.count(anchor) != 1 for anchor in edits):
        raise ValueError('Launcher app cache anchors changed')
    for anchor, replacement in edits.items():
        text = text.replace(anchor, replacement, 1)
    return text


def widget_loading(text):
    old = '''    function ensureWidgetItem(name, t) {
        let cached = widgetCache[name];
        if (cached) return cached;

        let comp = componentCache[name];
        if (!comp) {
            comp = typeof t.comp === "string" ? Qt.createComponent(t.comp) : t.comp;
            if (comp) componentCache[name] = comp;
        }
        if (!comp) return null;

        if (comp.status === Component.Loading) return null;
        if (comp.status === Component.Error) {
            console.warn("Widget component failed to load:", name, comp.errorString());
            return null;
        }

        let item = comp.createObject(preloaderContainer);
        if (item) {
            item.visible = false;
            widgetCache[name] = item;
        }
        return item;
    }'''
    new = '''    property var widgetJobs: ({})
    property var pendingWidget: null

    function finishWidgetLoad(name, item) {
        delete widgetJobs[name];
        if (item) widgetCache[name] = item;
        const pending = pendingWidget;
        if (!pending || pending.name !== name) return;
        if (item) {
            Qt.callLater(function() {
                if (pendingWidget !== pending) return;
                pendingWidget = null;
                executeSwitch(name, pending.arg, pending.generation);
            });
        } else {
            pendingWidget = null;
            targetActive = currentActive;
        }
    }

    function ensureWidgetItem(name, t) {
        if (widgetCache[name] || widgetJobs[name]) return;
        const comp = componentCache[name] || (typeof t.comp === "string"
            ? Qt.createComponent(t.comp, Component.Asynchronous) : t.comp);
        if (!comp) {
            finishWidgetLoad(name, null);
            return;
        }
        componentCache[name] = comp;
        const job = {};
        widgetJobs[name] = job;

        function instantiate() {
            if (comp.status !== Component.Ready) {
                console.warn("Widget component failed to load:", name, comp.errorString());
                delete componentCache[name];
                finishWidgetLoad(name, null);
                return;
            }
            const incubator = comp.incubateObject(preloaderContainer, { visible: false }, Qt.Asynchronous);
            job.incubator = incubator;
            function complete(status) {
                if (status === Component.Loading) return;
                if (status !== Component.Ready) console.warn("Widget failed to initialize:", name);
                finishWidgetLoad(name, status === Component.Ready ? incubator.object : null);
            }
            if (!incubator) {
                finishWidgetLoad(name, null);
            } else if (incubator.status === Component.Loading) {
                incubator.onStatusChanged = complete;
            } else {
                complete(incubator.status);
            }
        }

        if (comp.status === Component.Loading) {
            const loaded = function() {
                if (comp.status === Component.Loading) return;
                comp.statusChanged.disconnect(loaded);
                instantiate();
            };
            comp.statusChanged.connect(loaded);
        } else {
            instantiate();
        }
    }'''
    edits = {
        old: new,
        '        masterWindow.switchGeneration++;': '        pendingWidget = null;\n        masterWindow.switchGeneration++;',
        '''        let cachedItem = ensureWidgetItem(newWidget, t);
        if (!cachedItem) {
            Qt.callLater(function() {
                if (gen === masterWindow.switchGeneration) {
                    executeSwitch(newWidget, arg, gen);
                }
            });
            return;
        }''': '''        const cachedItem = widgetCache[newWidget];
        if (!cachedItem) {
            pendingWidget = { name: newWidget, arg: arg, generation: gen };
            ensureWidgetItem(newWidget, t);
            return;
        }''',
        '''                if (targetWidget === effectivelyActive) {
                    let currentItem''': '''                if (targetWidget === effectivelyActive) {
                    if (pendingWidget && pendingWidget.name === targetWidget && arg !== "") {
                        pendingWidget.arg = arg;
                        return;
                    }
                    let currentItem''',
        '''        let item = widgetCache["guide"] || widgetStack.currentItem;''': '''        if (pendingWidget && pendingWidget.name === "guide" && tab !== "") {
            pendingWidget.arg = tab;
            return;
        }
        let item = widgetCache["guide"] || widgetStack.currentItem;''',
        '''                if (cmd === effectivelyActive) {
                    let currentItem''': '''                if (cmd === effectivelyActive) {
                    if (pendingWidget && pendingWidget.name === cmd && legacyArg !== "") {
                        pendingWidget.arg = legacyArg;
                        return;
                    }
                    let currentItem''',
    }
    if old not in text:
        return text
    if any(text.count(anchor) != 1 for anchor in edits):
        raise ValueError('Widget loading anchors changed')
    for anchor, replacement in edits.items():
        text = text.replace(anchor, replacement, 1)
    return text


def floating_actions(text):
    warm_up = '''            property bool modulesWarm: false

            onIsPeekVisibleChanged: {
                if (isPeekVisible) modulesWarm = true;
            }

'''
    active = '                                active: isEager || floatingWidget.modulesWarm || (isCurrentTarget && floatingWidget.isExpanded)'
    loaded = '                                onLoaded: updateSizes()'
    if 'property bool hasLoaded: false' in text or warm_up not in text:
        return text
    changes = {
        warm_up: '',
        '                    modulesWarm = true;\n': '',
        active: '''                                property bool hasLoaded: false
                                active: isEager || hasLoaded || (isCurrentTarget && floatingWidget.isExpanded)''',
        loaded: '''                                onLoaded: {
                                    hasLoaded = true;
                                    updateSizes();
                                }''',
    }
    if any(text.count(anchor) != 1 for anchor in changes):
        raise ValueError('Quick actions loading anchors changed')
    for anchor, replacement in changes.items():
        text = text.replace(anchor, replacement, 1)
    return text


def surface_field(text):
    old = '''        root.shapes = next;
        root.revision++;
    }'''
    if 'signal shapeChanged(' in text or old not in text:
        return text
    anchors = [
        '    property int revision: 0',
        '        next[screenName][id] = shape;\n' + old,
        '        delete next[screenName][id];\n' + old,
    ]
    if any(text.count(anchor) != 1 for anchor in anchors):
        raise ValueError('SurfaceField publication anchors changed')
    text = text.replace(anchors[0], anchors[0] +
                        '\n    signal shapeChanged(string screenName, string id, var previous, var current)', 1)
    text = text.replace(anchors[1], anchors[1].replace('        root.revision++;',
                        '        root.revision++;\n        root.shapeChanged(screenName, id, cur === undefined ? null : cur, shape);'), 1)
    return text.replace(anchors[2], anchors[2].replace('        delete next',
                        '        const previous = next[screenName][id];\n        delete next').replace('        root.revision++;',
                        '        root.revision++;\n        root.shapeChanged(screenName, id, previous, null);'), 1)


def attached_surface(text):
    old = '''    Connections {
        target: SurfaceField
        function onRevisionChanged() { if (!root.inRebuild) root.schedule(); }
    }'''
    new = '''    function belongsToField(shape) {
        return shape && (attachTo.includes(shape.kind) || (shape.attachTo && shape.attachTo.includes(kind)));
    }

    Connections {
        target: SurfaceField
        function onShapeChanged(screenName, id, previous, current) {
            if (!root.live || root.inRebuild || screenName !== root.screenName || id === root.surfaceId) return;
            if (root.belongsToField(previous) || root.belongsToField(current)) root.schedule();
        }
    }'''
    if old not in text:
        return text
    if text.count(old) != 1:
        raise ValueError('Ambiguous attached surface subscription')
    return text.replace(old, new, 1)


def transformations(qs):
    return {
        qs/'network/NetworkCoreLayer.qml': network,
        qs/'volume/VolumePopup.qml': volume,
        qs/'reusables/media/Visualizer.qml': visualizer,
        qs/'widgets/faces/clock/ClockFaceMaterialLumen.qml': lumen_clock,
        qs/'reusables/display/focustimer/FocusStopwatchPanel.qml': stopwatch,
        qs/'lock/redactor/LockRedactor.qml': lock_editor,
        qs/'launcher/Launcher.qml': launcher,
        qs/'quickactions/Floating.qml': floating_actions,
        qs/'Main.qml': widget_loading,
        qs/'singletons/system/SurfaceField.qml': surface_field,
        qs/'reusables/display/AttachedSurface.qml': attached_surface,
    }
