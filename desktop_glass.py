"""Connect the optional desktop capture to the upstream Liquid Glass backdrop."""
MARK = 'serpantinum-addons-v2 desktop glass'
BLOCK = '''                    // BEGIN serpantinum-addons-v2 desktop glass
                    Loader {
                        id: desktopCapture
                        x: root.imageX + root.blurPad
                        y: root.imageY + root.blurPad
                        width: root.screenWidth
                        height: root.screenHeight
                        scale: root.imageScale
                        transformOrigin: Item.TopLeft
                        rotation: root.imageRotation
                        active: root.active && root.liquid && !root.useSnapshot && AddonDesktopGlass.enabled && AddonDesktopGlass.moduleUrl !== ""
                        source: active ? AddonDesktopGlass.moduleUrl : ""
                        onLoaded: {
                            item.screenName = Qt.binding(function() { return root.screenName; });
                            item.textureSize = Qt.binding(function() { return root.textureSize; });
                        }
                    }
                    Connections {
                        target: desktopCapture.item
                        ignoreUnknownSignals: true
                        function onFrameChanged() { root.refreshTexture(); }
                    }
                    // END serpantinum-addons-v2 desktop glass

'''


def patch(text):
    if f'// BEGIN {MARK}' in text:
        start = text.index('                    // BEGIN ' + MARK + '\n')
        end = text.index('                    // END ' + MARK + '\n', start) + len('                    // END ' + MARK + '\n')
        text = text[:start] + text[end:].lstrip('\n')
    anchor = '''                    Rectangle {
                        anchors.fill: parent
                        visible: root.tint > 0'''
    if text.count(anchor) != 1:
        raise ValueError('WallpaperBlur desktop glass anchor changed')
    return text.replace(anchor, BLOCK + anchor, 1)
