"""Trackpad controls through Niri's effective configuration and addon extension."""
import hashlib
import json
import math
from control import CONFIG, write
from niri_ipc import addon
import niri_config


def revision():
    return niri_config.revision()


def status():
    snapshot = addon('snapshot')
    devices = sorted(d['name'] for d in snapshot['devices'])
    return dict(settings=snapshot['input']['touchpad'], devices=devices,
                revision=revision(), available=bool(devices))


def save(payload):
    current = status()
    if not current['available']:
        raise ValueError('No touchpad detected.')
    if payload['revision'] != current['revision'] or payload['devices'] != current['devices']:
        raise ValueError('Trackpad configuration or connected devices changed. Reopen Addons before saving.')
    settings = payload['settings']
    speed = settings['speed']
    if isinstance(speed, bool) or not isinstance(speed, (int, float)) or not math.isfinite(speed) or not -1 <= speed <= 1:
        raise ValueError('Trackpad speed must be between -1 and 1.')
    for key in ('disableWhileTyping', 'disableClicksWhileTyping'):
        if not isinstance(settings[key], bool):
            raise ValueError('Invalid trackpad switch value.')
    content = niri_config.input_fragment('touchpad', {
        'accel-speed': str(speed),
        'dwt': '' if settings['disableWhileTyping'] else None,
        'serpantinum-disable-clicks-while-typing': '' if settings['disableClicksWhileTyping'] else None,
    })
    niri_config.update('trackpad', content, verify=lambda: addon('snapshot')['input']['touchpad'] == settings,
                       extra={CONFIG / 'hypr/config/serpantinum_trackpad.json': json.dumps(settings, indent=2) + '\n'})
    return dict(settings=settings, devices=current['devices'], revision=revision(), available=True)
