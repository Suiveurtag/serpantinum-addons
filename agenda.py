"""Calendar addon: Google Calendar (read/write) and iCal subscriptions in the clock panel (Meta+S) and its agenda.

Registers the `gcal/` QML types, hooks the clock panel (today column, day dots, next-event pill, agenda morph),
binds Super+G and runs the sync / reminder daemon as a systemd user service. Every hook is a marked block that
`remove` takes out again, restoring the single upstream lines some of them replace.
"""
import json
import os
import re
import shlex
import subprocess
from pathlib import Path

MARK = 'serpantinum-gcal-v2'
CHORD = 'SUPER + G'
OPEN_CHORD = 'SUPER + I'   # second shortcut that opens the agenda directly
UNIT = 'serpantinum-gcal.service'
PAYLOAD = Path(__file__).resolve().parent/'payload/gcal'
# Every gcal/ type is registered in the shell's root qmldir (files loaded through it do not see their siblings).
TYPES = ['singleton GCal 1.0 gcal/GCal.qml'] + [f'{p.stem} 1.0 gcal/{p.name}' for p in sorted(PAYLOAD.glob('*.qml')) if p.stem != 'GCal']

# Blocks that replace an upstream line: removing the block puts that line back.
RESTORE = {
    'day': '                                enabled: false\n',
    'escape': '        onActivated: dashboardWindow.closeDashboard()\n',
}

DAY_ANCHOR = '                                enabled: false\n                                buttonText: dayNum\n'
DAY_BLOCK = f'''    // BEGIN {MARK} day
                                id: gcalDay
                                readonly property var gcalDate: {{ const m = new Date(window.currentTime.getFullYear(), window.currentTime.getMonth() + window.monthOffset, 1); return new Date(m.getFullYear(), m.getMonth(), 1 - ((m.getDay() + 6) % 7) + index); }}
                                readonly property bool gcalSelected: GCal.selectedDay !== null && GCal.sameDay(GCal.selectedDay, gcalDate)
                                enabled: GCal.available
                                onClicked: GCal.selectDay(gcalSelected ? null : gcalDate)
                                Rectangle {{
                                    anchors.fill: parent
                                    radius: Scaler.s(5)
                                    color: "transparent"
                                    border.width: Scaler.s(1.5)
                                    border.color: window.textAccent
                                    opacity: gcalDay.gcalSelected ? 1 : 0
                                    scale: gcalDay.gcalSelected ? 1 : 0.6
                                    Behavior on opacity {{ NumberAnimation {{ duration: 200 }} }}
                                    Behavior on scale {{ NumberAnimation {{ duration: 340; easing.type: Easing.OutBack; easing.overshoot: 2 }} }}
                                }}
                                GCalDayDots {{
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: Scaler.s(2)
                                    date: gcalDay.gcalDate
                                    onAccent: isToday && !ThemeBackend.liquidGlass
                                    dimmed: !isCurrentMonth
                                    delay: 320 + index * 9
                                }}
    // END {MARK} day
'''
NEXT_ANCHOR = '                    Item {\n                        id: hourStrip\n'
NEXT_BLOCK = f'''    // BEGIN {MARK} next
                    GCalNextChip {{ Layout.alignment: Qt.AlignHCenter; allowed: !window.vertical; accent: window.textAccent; intro: window.introClock }}
    // END {MARK} next
'''
WRAPPER_ANCHOR = '    onVisibleChanged: if (visible) resetAndPlayIntro()\n}'
WRAPPER_BLOCK = f'''    // BEGIN {MARK} layer
    GCalLayer {{ host: root }}
    // END {MARK} layer
'''
ESCAPE_ANCHOR = '        enabled: dashboardWindow.isOpen\n        onActivated: dashboardWindow.closeDashboard()\n'
ESCAPE_BLOCK = f'''    // BEGIN {MARK} escape
        onActivated: {{ if (GCal.handleEscape()) return; dashboardWindow.closeDashboard(); }}
    // END {MARK} escape
'''
SHELL_ANCHOR = '    function ensureScreenshotOverlay() {\n'


def remove_blocks(text):
    def restore(match):
        return RESTORE.get(match.group(1), '')
    text = re.sub(r'^[ ]*// BEGIN ' + MARK + r' ([^\n]+)\n.*?^[ ]*// END ' + MARK + r' \1\n', restore, text, flags=re.S | re.M)
    lua = re.compile(r'\n*^-- BEGIN ' + MARK + r' ([^\n]+)\n.*?^-- END ' + MARK + r' \1\n', re.S | re.M)
    while lua.search(text):
        text = lua.sub('\n', text, count=1)
    return text


def remove(text):
    return re.sub(r'^(?:singleton )?\w+ 1\.0 gcal/\w+\.qml\n', '', remove_blocks(text), flags=re.M)


def _insert(text, anchor, block, name, before=True):
    text = remove_blocks(text)
    if text.count(anchor) != 1:
        raise ValueError(f'Calendar {name} anchor changed')
    return text.replace(anchor, block + anchor if before else anchor + block, 1)


def patch_qmldir(text):
    text = remove(text)
    for declaration in TYPES:
        text = text.rstrip('\n') + '\n' + declaration + '\n'
    return text


def patch_shell(text):
    return _insert(text, SHELL_ANCHOR, f'    // BEGIN {MARK} host\n    AddonCalendar {{}}\n    // END {MARK} host\n', 'shell')


def patch_wrapper(text):
    return _insert(text, WRAPPER_ANCHOR, WRAPPER_BLOCK, 'clock wrapper')


# The clock panel extras (day dots, next-event pill, Esc handling) are optional: on a Serpantinum whose panel
# changed shape they are skipped, and the agenda still works through the wrapper layer.
def patch_native(text):
    text = remove_blocks(text)
    if text.count(DAY_ANCHOR) == 1:
        text = text.replace(DAY_ANCHOR, DAY_BLOCK + '                                buttonText: dayNum\n', 1)
    if text.count(NEXT_ANCHOR) == 1:
        text = text.replace(NEXT_ANCHOR, NEXT_BLOCK + NEXT_ANCHOR, 1)
    return text


def patch_dashboard(text):
    text = remove_blocks(text)
    if text.count(ESCAPE_ANCHOR) != 1:
        return text
    return text.replace(ESCAPE_ANCHOR, '        enabled: dashboardWindow.isOpen\n' + ESCAPE_BLOCK, 1)


def patch_keybind(text, shell_qml):
    # Preserve user edits inside the managed blocks on reinstall; the second bind is added to installs that predate it.
    base = 'quickshell -p ' + shlex.quote(str(shell_qml)) + ' ipc call addonCalendar '
    # An earlier version bound Super+I to a centered window that no longer exists.
    text = re.sub(r'\n*^-- BEGIN ' + MARK + r' keybind center\n.*?^-- END ' + MARK + r' keybind center\n', '\n', text, flags=re.S | re.M)
    text = text.rstrip() + '\n'
    for name, chord in (('keybind', CHORD), ('keybind open', OPEN_CHORD)):
        if f'-- BEGIN {MARK} {name}\n' in text:
            continue
        if f'"{chord}"' in text:
            raise ValueError(f'Calendar shortcut {chord} already in use')
        text += f'\n-- BEGIN {MARK} {name}\nhl.bind("{chord}", hl.dsp.exec_cmd(' + json.dumps(base + 'toggle') + f'))\n-- END {MARK} {name}\n'
    return text


def transformations(qs):
    return {qs/'qmldir': patch_qmldir, qs/'Shell.qml': patch_shell}


def resources(payload, qs):
    return [(qs/'gcal'/p.relative_to(payload), p.read_bytes()) for p in sorted(payload.rglob('*')) if p.is_file()]


def unit(script):
    return ('[Unit]\nDescription=Serpantinum calendar sync and reminders\nAfter=network-online.target\n\n'
            f'[Service]\nExecStart=/usr/bin/python3 {script} daemon\nRestart=on-failure\nRestartSec=15\nNice=10\nMemoryMax=200M\n\n'
            '[Install]\nWantedBy=default.target\n')


def service(deploy, home, remove=False):
    """Install (or remove) and start the sync daemon. Never fails the shell install."""
    if os.environ.get('SERPANTINUM_ADDONS_NO_SERVICES'):
        return 'calendar service skipped (SERPANTINUM_ADDONS_NO_SERVICES is set)'
    path = home/'.config/systemd/user'/UNIT
    run = lambda *args: subprocess.run(['systemctl', '--user', *args], capture_output=True, text=True, timeout=30)
    try:
        if remove:
            if path.exists():
                run('disable', '--now', UNIT)
                path.unlink(missing_ok=True)
                run('daemon-reload')
            return 'calendar service removed (account and cache kept in ~/.local/state/serpantinum/gcal)'
        text = unit(deploy/'scripts/gcal/gcal.py')
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists() or path.read_text() != text:
            path.write_text(text)
            run('daemon-reload')
        run('enable', UNIT)
        run('restart', UNIT)   # the daemon script was just refreshed
        return 'calendar service ' + run('is-active', UNIT).stdout.strip()
    except (OSError, subprocess.SubprocessError) as error:
        return f'calendar service not managed ({error}); run `python3 {deploy}/scripts/gcal/gcal.py daemon` yourself'
