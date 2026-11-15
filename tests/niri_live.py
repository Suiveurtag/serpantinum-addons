#!/usr/bin/env python3
"""Opt-in native smoke test: isolated Niri, a real window, addon IPC and restoration."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from niri_ipc import request, addon
from niri_actions import surge
from niri_world import normalize


def wait_for(test, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = test()
        if value:
            return value
        time.sleep(.05)
    raise AssertionError('Timed out waiting for native state')


def main():
    binary = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix='serp-niri-', dir=os.environ['XDG_RUNTIME_DIR']) as directory:
        base = Path(directory)
        runtime = base / 'run'; runtime.mkdir(mode=0o700)
        for name in ('pipewire-0', 'pulse'):
            service = Path(os.environ['XDG_RUNTIME_DIR']) / name
            if service.exists(): (runtime/name).symlink_to(service)
        config_root = base / 'config'; (config_root / 'niri').mkdir(parents=True)
        config = config_root / 'niri/config.kdl'; config.write_text('xwayland-satellite { path "/home/suiveurtag/.local/opt/niri-serpantinum/satellite/usr/bin/xwayland-satellite"; }\ninput { keyboard { xkb { layout "fr"; options "lv3:ralt_switch"; }; }; mouse { natural-scroll; accel-profile "flat"; }; touchpad { natural-scroll; tap; }; }\nhotkey-overlay { skip-at-startup; }\n')
        parent_display = os.environ['WAYLAND_DISPLAY']
        if not parent_display.startswith('/'):
            parent_display = str(Path(os.environ['XDG_RUNTIME_DIR']) / parent_display)
        env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), WAYLAND_DISPLAY=parent_display, XDG_CONFIG_HOME=str(config_root), XDG_CURRENT_DESKTOP="niri", XDG_SESSION_DESKTOP="niri")
        env.pop('NIRI_SOCKET', None); env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
        processes = []
        log = (base / 'niri.log').open('w+')
        compositor = subprocess.Popen([str(binary), '-c', str(config)], env=env, stdout=log, stderr=log)
        processes.append(compositor)
        saved_env = dict(os.environ)
        try:
            socket = wait_for(lambda: next(runtime.glob('niri.*.sock'), None))
            display = wait_for(lambda: next((p for p in runtime.glob('wayland-*') if p.is_socket()), None))
            os.environ['NIRI_SOCKET'] = str(socket)
            env.update(NIRI_SOCKET=str(socket), WAYLAND_DISPLAY=str(display))
            assert addon('capabilities')['version'] == 1
            app = base / 'window.qml'
            app.write_text('''import QtQuick
import QtQuick.Window
Window { visible: true; width: 600; height: 400; title: "Serpantinum Niri test"
    Rectangle { anchors.fill: parent; color: "#162338"
        Repeater { model: 6; Rectangle { required property int index; x: index * 100; y: 0; width: 50; height: parent.height; color: index % 2 ? "#e6b450" : "#62d9cb" } }
    }
}
''')
            app_log = (base / 'app.log').open('w+')
            window = subprocess.Popen(['qml6', str(app)], env=env, stdout=app_log, stderr=app_log)
            processes.append(window)
            snapshot = wait_for(lambda: (s if any(w.get('serpantinum_geometry') for w in s['windows']) else None) if (s := addon('snapshot')) else None)
            normalized = normalize(request('Outputs'), request('Workspaces'), snapshot['windows'], snapshot)
            assert any(not c['hidden'] and c['size'][0] > 0 for c in normalized['clients']), snapshot
            from unittest.mock import patch
            import niri_config, niri_controls, mouse_acceleration, niri_trackpad, startup, window_outline
            from contextlib import ExitStack
            with ExitStack() as scope:
                for module in (niri_config, niri_controls, mouse_acceleration, niri_trackpad, startup, window_outline):
                    if hasattr(module, 'CONFIG'): scope.enter_context(patch.object(module, 'CONFIG', config_root))
                for module in (mouse_acceleration, startup):
                    scope.enter_context(patch.object(module, 'SETTINGS', config_root / ('shared-' + module.__name__ + '.json')))
                scope.enter_context(patch.object(niri_config, 'executable', return_value=str(binary)))
                mouse = mouse_acceleration.status()
                mouse['enabled'] = True
                assert mouse_acceleration.save(mouse)['profile'] == 'adaptive'
                mouse_text = (config_root/'niri/serpantinum-mouse.kdl').read_text()
                assert 'natural-scroll' in mouse_text
                keyboard = niri_controls.keyboard_layouts()
                keyboard['layouts'] = ['fr', 'us']
                niri_controls.save_keyboard_layout(keyboard)
                wait_for(lambda: len(request('KeyboardLayouts')['names']) == 2)
                assert 'lv3:ralt_switch' in (config_root/'niri/serpantinum-keyboard.kdl').read_text()
                trackpad = dict(settings=dict(speed=.25, disableWhileTyping=True, disableClicksWhileTyping=True), devices=['fixture-touchpad'], revision=niri_trackpad.revision(), available=True)
                scope.enter_context(patch.object(niri_trackpad, 'status', return_value=trackpad))
                niri_trackpad.save(trackpad)
                assert addon('snapshot')['input']['touchpad']['disableClicksWhileTyping']
                assert 'natural-scroll' in (config_root/'niri/serpantinum-trackpad.kdl').read_text()
                window_outline.apply(True, '#112233', '#445566', '#778899')
                data = startup.status(); data['commands'] = ['printf test']
                startup.save(data)
                assert 'spawn-sh-at-startup' in (config_root/'niri/serpantinum-startup.kdl').read_text()
                print('NIRI_SETTINGS_PASS: applied mouse, keyboard, trackpad configuration, border and startup with existing options preserved')
            point = dict(x=100., y=120.)
            addon('warp', **point)
            assert addon('snapshot')['pointer'] == point
            for factor in [0., 7., -1.]:
                try:
                    addon('zoom', factor=factor)
                except RuntimeError:
                    pass
                else:
                    raise AssertionError('Invalid magnification accepted')
            if os.environ.get('SERPANTINUM_TEST_PIXELS'):
                window_id = snapshot['windows'][0]['id']
                request({'Action': {'FullscreenWindow': {'id': window_id}}})
                time.sleep(.4)
                clients = json.loads(subprocess.check_output(['hyprctl', '-j', 'clients'], text=True))
                host = next(c for c in clients if c['pid'] == compositor.pid)
                x, y = host['at']; width, height = host['size']
                before = base / 'before.png'; after = base / 'after.png'
                region = f'{x},{y} {width}x{height}'
                subprocess.run(['grim', '-g', region, str(before)], check=True, capture_output=True)
                from PIL import Image, ImageChops
                first = Image.open(before).convert('RGB')
                yellow = lambda p: abs(p[0]-230)<5 and abs(p[1]-180)<5 and abs(p[2]-80)<5
                def rendered_zoom():
                    # Keep the centre fixed: physical pointer motion in the parent must not move this test's camera.
                    addon('zoom', factor=2., scroll=True, x=100., y=120.)
                    time.sleep(.04)
                    subprocess.run(['grim', '-g', region, str(after)], check=True, capture_output=True)
                    return yellow(Image.open(after).convert('RGB').getpixel((175,120)))
                wait_for(rendered_zoom, timeout=3)
                second = Image.open(after).convert('RGB')
                import shutil
                artifacts = Path(os.environ.get('SERPANTINUM_TEST_ARTIFACTS', str(base/'artifacts')))
                artifacts.mkdir(parents=True, exist_ok=True)
                for artifact in (before, after):
                    shutil.copy2(artifact, artifacts / artifact.name)
                assert ImageChops.difference(first, second).getbbox(), 'Native zoom did not change the rendered pixels'
                assert not yellow(first.getpixel((175,120)))
                print('NIRI_ZOOM_PIXELS_PASS: actual output scales around the selected pointer position')
            addon('zoom', factor=2., scroll=True)
            assert addon('snapshot')['zoomFactor'] == 2.
            wait_for(lambda: addon('snapshot')['zoomFactor'] == 1., timeout=4)
            worker = subprocess.Popen([sys.executable, str(ROOT / 'scripts/desktop_zoom.py')], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            processes.append(worker)
            ready = json.loads(worker.stdout.readline()); assert ready['ready']
            worker.stdin.write('{"factor":2}\n'); worker.stdin.flush()
            wait_for(lambda: addon('snapshot')['zoomFactor'] > 1.95)
            worker.kill(); worker.wait()
            wait_for(lambda: addon('snapshot')['zoomFactor'] == 1., timeout=4)
            print('NIRI_ZOOM_WORKER_PASS: animation and recovery after SIGKILL')
            surge_zoom = subprocess.Popen([sys.executable, str(ROOT / 'scripts/clawd/surge_zoom.py')], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            processes.append(surge_zoom)
            assert json.loads(surge_zoom.stdout.readline())['ready']
            surge_zoom.stdin.write('{"f":2.5,"x":100,"y":120}\n'); surge_zoom.stdin.flush()
            wait_for(lambda: addon('snapshot')['zoomFactor'] == 2.5)
            surge_zoom.stdin.write('{"close":true}\n'); surge_zoom.stdin.flush()
            surge_zoom.wait(timeout=3)
            assert surge_zoom.returncode == 0 and addon('snapshot')['zoomFactor'] == 1.
            print('NIRI_SURGE_ZOOM_PASS: fixed-centre zoom and restoration')
            focused = next(s for s in request('Workspaces') if s['is_focused'])
            output = focused['output']
            from io import StringIO
            surge(output, StringIO('{"close":true}\n'))
            assert next(s for s in request('Workspaces') if s['is_focused'])['id'] == focused['id']
            print('NIRI_LIVE_PASS: real window geometry, pointer warp, bounded zoom, lease recovery, workspace restoration')
            if os.environ.get('SERPANTINUM_TEST_SHELL'):
                shell_path=Path.home()/'.local/share/serpantinum/src/quickshell/Shell.qml'
                settings=json.loads((Path.home()/'.config/serpantinum/settings.json').read_text())
                settings.update(addonsV2Clawd=True, addonsV2ClawdWorld=True, addonsV2Capri=True)
                settings_path=base/'settings.json'; settings_path.write_text(json.dumps(settings))
                import socket as sockets
                with sockets.socket() as reserve:
                    reserve.bind(('127.0.0.1',0)); capri_port=reserve.getsockname()[1]
                shell_env=dict(env, QS_SETTINGS=str(settings_path), QS_STATE_DIR=str(base/'state'), QS_CACHE_DIR=str(base/'cache'), QS_RUN_DIR=str(runtime/'serpantinum'),
                    SERPANTINUM_DIR=str(shell_path.parents[1]), QS_DIR=str(shell_path.parent), XDG_STATE_HOME=str(base/'state'), CAPRI_PORT=str(capri_port))
                widgets=base/'state/widgets/winit'; widgets.mkdir(parents=True)
                (widgets/'layout.json').write_text(json.dumps([dict(wType='time',wVariant='analog',wX=300,wY=300,wWidth=200,wHeight=200,wOpacity=1,wRotation=0,wId='niri-test')]))
                shell_log=(base/'shell.log').open('w+')
                shell=subprocess.Popen(['quickshell','-p',str(shell_path)],env=shell_env,stdout=shell_log,stderr=shell_log)
                processes.append(shell)
                def ipc(target,method,*args):
                    result=subprocess.run(['quickshell','-p',str(shell_path),'ipc','call',target,method,*args],env=shell_env,capture_output=True,text=True,timeout=15)
                    if result.returncode: return None
                    try: return json.loads(result.stdout)
                    except ValueError: return None
                clawd=wait_for(lambda: (v if v and v.get('world') and v['world']['wins']>0 and v['world']['pointer'] else None) if (v:=ipc('clawd','state')) else None,timeout=20)
                capri=wait_for(lambda: (v if v and v.get('world') and v['world']['clients']>0 and v['world']['pointer'] else None) if (v:=ipc('capri','status')) else None,timeout=20)
                assert clawd['world']['layers']>0
                assert clawd['world']['widgets']>0, clawd['world']
                def namespaces():
                    return {l['namespace'] for ls in addon('snapshot')['layers'].values() for level in ls.values() for l in level}
                ipc('addonMouseSpotlight','activate')
                wait_for(lambda: 'qs-addon-mouse-spotlight' in namespaces())
                ipc('addonMouseSpotlight','deactivate')
                wait_for(lambda: 'qs-addon-mouse-spotlight' not in namespaces())
                ipc('addonDesktopDraw','activate')
                wait_for(lambda: (s and s['active']) if (s:=ipc('addonDesktopDraw','status')) else False)
                addon('warp', x=200., y=200.)
                subprocess.run([os.environ.get('SERPANTINUM_TEST_INPUT','/tmp/serpantinum-niri-fulltest/input'),'stroke','0'],env=dict(env,SERPANTINUM_NIRI_TEST='1'),check=True)
                wait_for(lambda: (s and s['strokes']>0) if (s:=ipc('addonDesktopDraw','status')) else False)
                ipc('addonDesktopDraw','deactivate')
                ipc('addonColorPicker','activate')
                wait_for(lambda: 'qs-addon-color-picker' in namespaces())
                ipc('addonColorPicker','deactivate')
                wait_for(lambda: 'qs-addon-color-picker' not in namespaces())
                ipc('addonDesktopZoom','activate')
                wait_for(lambda: addon('snapshot')['zoomFactor']>1.2)
                ipc('addonDesktopZoom','deactivate')
                wait_for(lambda: addon('snapshot')['zoomFactor']==1.)
                print('NIRI_TOOLS_PASS: spotlight, real drawing stroke, colour picker and shell-driven zoom')
                request({'Action':{'CloseWindow':{'id':snapshot['windows'][0]['id']}}})
                wait_for(lambda: (v and v.get('world') and v['world']['wins']==0) if (v:=ipc('clawd','state')) else False)
                shell_log.flush(); shell_log.seek(0); log_text=shell_log.read()
                if 'ERROR' in log_text:
                    Path('/tmp/serpantinum-niri-fulltest/shell.log').write_text(log_text)
                    raise AssertionError('\n'.join(line for line in log_text.splitlines() if 'ERROR' in line))
                print('NIRI_SHELL_PASS: real Clawd/Capri windows, pointer, layer geometry and window-close lifecycle')
                shell.terminate(); shell.wait(timeout=4)
            if os.environ.get('SERPANTINUM_TEST_CAPTURE'):
                native_input = os.environ.get('SERPANTINUM_TEST_INPUT', '/tmp/serpantinum-niri-fulltest/input')
                broker_log = (base/'capture.log').open('w+')
                broker = subprocess.Popen([sys.executable, str(ROOT/'scripts/beamer/niri_capture_bridge.py')], env=env, stdout=broker_log, stderr=broker_log)
                processes.append(broker)
                wait_for(lambda: (runtime/'beamer-addon/capture.sock').exists())
                source = Path(subprocess.check_output(['flatpak','info','--user','--show-location','uk.co.kalkman.beamer'],text=True).strip())/'files/share/beamer'
                sys.path[:0] = [str(ROOT/'scripts/beamer'), str(source/'win_app'), str(source)]
                import niri_capture, capture_portal
                niri_capture.install()
                old_runtime = os.environ['XDG_RUNTIME_DIR']
                os.environ['XDG_RUNTIME_DIR'] = str(runtime)
                transport = capture_portal._Session(None,None,None,None)
                try:
                    transport.check(); transport.open(); transport.events()
                    output_geo = request('FocusedOutput')['logical']
                    right=output_geo['x']+output_geo['width']
                    barrier=[right,output_geo['y'],right,output_geo['y']+output_geo['height']-1]
                    transport.set_barriers([barrier])
                    addon('warp', x=right-1, y=100.)
                    input_env=dict(env,SERPANTINUM_NIRI_TEST='1')
                    subprocess.run([native_input,'motion','10','0'],env=input_env,check=True)
                    assert transport.pending()
                    assert any(s[2]=='Activated' for s in transport.signals())
                    assert any(e[0]=='motion' for e in transport.events())
                    subprocess.run([native_input,'key','30'],env=input_env,check=True)
                    transport.pending()
                    keys=[e for e in transport.events() if e[0]=='key']
                    assert [e[3] for e in keys]==[True,False], keys
                    transport.release(1,(right-20,100))
                    transport.pending(); transport.signals(); transport.events()
                    transport.set_barriers([barrier])
                    addon('warp',x=right-1,y=100.)
                    subprocess.run([native_input,'motion','10','0'],env=input_env,check=True)
                    time.sleep(1.2)
                    transport.pending()
                    assert any(s[2]=='Disabled' for s in transport.signals()), 'capture lease failed to release'
                    subprocess.run([native_input,'motion','-20','0'],env=input_env,check=True)
                    assert addon('snapshot')['pointer']['x'] < right-1
                    print('BEAMER_CAPTURE_PASS: real virtual-device motion and keys, host broker, lease release and pointer recovery')
                finally:
                    transport.close(); os.environ['XDG_RUNTIME_DIR']=old_runtime
            if os.environ.get('SERPANTINUM_TEST_EFFECTS'):
                env.update(QT_QPA_PLATFORM='wayland')
                effect_log = (base / 'effects.log').open('w+')
                effects = subprocess.Popen([sys.executable, str(ROOT / 'scripts/beamer/niri_effects.py')], env=env, stdout=effect_log, stderr=effect_log)
                processes.append(effects)
                effect_socket = runtime / 'beamer-addon/effects.sock'
                wait_for(lambda: effect_socket.exists() or effects.poll() is not None)
                if effects.poll() is not None:
                    effect_log.seek(0); raise AssertionError(effect_log.read())
                import socket as sockets
                with sockets.socket(sockets.AF_UNIX) as client:
                    client.connect(str(effect_socket))
                    for command in [dict(op='effect_configure', style='aperture', colour='signal', length='normal', size='medium'),
                                    dict(op='push', edge='left', pressure=.8, crossed=False, x=100, y=120, desk=[0,0,750,1019]),
                                    dict(op='glow_configure', style='glow', colour='signal', length='normal', size='medium'),
                                    dict(op='glow_pressure', edge='left', pressure=.8, crossed=False)]:
                        client.sendall((json.dumps(command)+'\n').encode())
                    wait_for(lambda: {'qs-addon-beamer-effects', 'qs-addon-beamer-glow'} <= {l['namespace'] for ls in addon('snapshot')['layers'].values() for level in ls.values() for l in level})
                    assert effects.poll() is None
                    print('BEAMER_NATIVE_PASS: original engine mapped as native layer surfaces')
            if os.environ.get('SERPANTINUM_TEST_X11'):
                x11_app=base/'x11.qml'
                x11_app.write_text('import QtQuick\nimport QtQuick.Window\nWindow { visible:true; width:400; height:300; title:"Serpantinum Niri X11 test"; Rectangle { anchors.fill:parent; color:"#116644"; } }\n')
                request({'Action':{'Spawn':{'command':['env','QT_QPA_PLATFORM=xcb','qml6',str(x11_app)]}}})
                x11=wait_for(lambda: next((w for w in addon('snapshot')['windows'] if w.get('title')=='Serpantinum Niri X11 test'),None),timeout=15)
                assert x11.get('serpantinum_geometry')
                request({'Action':{'CloseWindow':{'id':x11['id']}}})
                print('NIRI_XWAYLAND_PASS: real X11 client mapped through local xwayland-satellite')
        finally:
            for process in reversed(processes):
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill(); process.wait()
            os.environ.clear(); os.environ.update(saved_env)
            if compositor.returncode not in (0, -signal.SIGTERM):
                log.seek(0); print(log.read(), file=sys.stderr)

if __name__ == '__main__':
    main()
