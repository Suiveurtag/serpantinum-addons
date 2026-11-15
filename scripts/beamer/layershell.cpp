#include <LayerShellQt/Window>
#include <QWindow>
#include <QScreen>
extern "C" void serpantinum_layer(void *window, void *screen, const char *scope) {
    auto *w = static_cast<QWindow *>(window);
    auto *s = static_cast<QScreen *>(screen);
    w->setScreen(s);
    auto *layer = LayerShellQt::Window::get(w);
    layer->setScope(QString::fromUtf8(scope));
    layer->setScreen(s);
    layer->setLayer(LayerShellQt::Window::LayerOverlay);
    layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop) | LayerShellQt::Window::AnchorBottom |
                      LayerShellQt::Window::AnchorLeft | LayerShellQt::Window::AnchorRight);
    layer->setExclusiveZone(-1);
    layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
    layer->setActivateOnShow(false);
}
