#include <QGuiApplication>
#include <QQmlExtensionPlugin>
#include <QtQml/qqml.h>
#include <QQuickPaintedItem>
#include <QPainter>
#include <QSocketNotifier>
#include <QTimer>
#include <QMutex>
#include <QMutexLocker>
#include <QHash>
#include <QSet>
#include <QDebug>
#include <wayland-client.h>
#include <sys/mman.h>
#include <unistd.h>
#include <climits>
#include "source.h"
#include "workspace.h"
#include "workspace-capture.h"
#include "copy.h"

class Capture : public QObject {
    Q_OBJECT
public:
    static Capture *acquire(const QString &name) {
        Capture *c = instances.value(name);
        if (!c) { c = new Capture(name); instances.insert(name, c); }
        ++c->users;
        return c;
    }
    void release() { if (--users == 0) { instances.remove(name); delete this; } }
    QImage frameImage() { QMutexLocker lock(&mutex); return image; }
    bool hasFrame() const { return !image.isNull(); }
    ~Capture() override {
        timer.stop();
        if (notifier) notifier->setEnabled(false);
        if (frame) ext_image_copy_capture_frame_v1_destroy(frame);
        if (session) ext_image_copy_capture_session_v1_destroy(session);
        if (buffer) wl_buffer_destroy(buffer);
        if (pixels) munmap(pixels, size);
        if (display) wl_display_disconnect(display);
    }
signals:
    void changed();
private:
    static QHash<QString, Capture *> instances;
    QString name;
    int users = 0;
    wl_display *display = nullptr;
    wl_shm *shm = nullptr;
    ext_workspace_manager_v1 *wm = nullptr;
    hyprland_workspace_image_capture_source_manager_v1 *cm = nullptr;
    ext_image_copy_capture_manager_v1 *im = nullptr;
    ext_workspace_handle_v1 *target = nullptr;
    struct Group { QSet<wl_output *> outputs; QSet<ext_workspace_handle_v1 *> workspaces; };
    QHash<wl_output *, QString> outputs;
    QHash<uint32_t, wl_output *> outputIds;
    QHash<ext_workspace_group_handle_v1 *, Group> groups;
    QHash<ext_workspace_handle_v1 *, bool> activeWorkspaces;
    ext_image_copy_capture_session_v1 *session = nullptr;
    ext_image_copy_capture_frame_v1 *frame = nullptr;
    wl_buffer *buffer = nullptr;
    void *pixels = nullptr;
    size_t size = 0;
    int width = 0, height = 0, bufferWidth = 0, bufferHeight = 0;
    bool constraints = false, argb = false, failed = false;
    QSocketNotifier *notifier = nullptr;
    QTimer timer;
    QImage image;
    QMutex mutex;

    explicit Capture(QString n): name(std::move(n)) {
        timer.setSingleShot(true);
        connect(&timer, &QTimer::timeout, this, &Capture::capture);
        display = wl_display_connect(nullptr);
        if (!display) return;
        auto *registry = wl_display_get_registry(display);
        static const wl_registry_listener reg = {global, globalRemove};
        wl_registry_add_listener(registry, &reg, this);
        if (wl_display_roundtrip(display) < 0 || wl_display_roundtrip(display) < 0 || !wm || !shm || !cm || !im) {
            qWarning() << "desktop capture: Wayland protocol unavailable" << name;
            return;
        }
        selectWorkspace();
        notifier = new QSocketNotifier(wl_display_get_fd(display), QSocketNotifier::Read, this);
        connect(notifier, &QSocketNotifier::activated, this, [this] {
            if (wl_display_dispatch(display) < 0) { notifier->setEnabled(false); failed = true; }
        });
        wl_display_flush(display);
    }
    static void global(void *data, wl_registry *r, uint32_t id, const char *interface, uint32_t version) {
        auto *c = static_cast<Capture *>(data);
        if (!strcmp(interface, wl_output_interface.name) && version >= 4) {
            auto *output = static_cast<wl_output *>(wl_registry_bind(r, id, &wl_output_interface, 4));
            c->outputs.insert(output, QString());
            c->outputIds.insert(id, output);
            static const wl_output_listener l = {outputGeometry, outputMode, outputDone, outputScale, outputName, outputDescription};
            wl_output_add_listener(output, &l, c);
        } else if (!strcmp(interface, wl_shm_interface.name)) c->shm = static_cast<wl_shm *>(wl_registry_bind(r, id, &wl_shm_interface, 1));
        else if (!strcmp(interface, ext_workspace_manager_v1_interface.name)) {
            c->wm = static_cast<ext_workspace_manager_v1 *>(wl_registry_bind(r, id, &ext_workspace_manager_v1_interface, 1));
            static const ext_workspace_manager_v1_listener l = {group, workspace, managerDone, managerFinished};
            ext_workspace_manager_v1_add_listener(c->wm, &l, c);
        } else if (!strcmp(interface, hyprland_workspace_image_capture_source_manager_v1_interface.name)) c->cm = static_cast<hyprland_workspace_image_capture_source_manager_v1 *>(wl_registry_bind(r, id, &hyprland_workspace_image_capture_source_manager_v1_interface, 1));
        else if (!strcmp(interface, ext_image_copy_capture_manager_v1_interface.name)) c->im = static_cast<ext_image_copy_capture_manager_v1 *>(wl_registry_bind(r, id, &ext_image_copy_capture_manager_v1_interface, 1));
    }
    static void globalRemove(void *data, wl_registry *, uint32_t id) {
        auto *c = static_cast<Capture *>(data);
        auto *output = c->outputIds.take(id);
        if (!output) return;
        c->outputs.remove(output);
        for (auto &group : c->groups) group.outputs.remove(output);
        wl_output_destroy(output);
        c->selectWorkspace();
    }
    static void outputGeometry(void *, wl_output *, int32_t, int32_t, int32_t, int32_t, int32_t, const char *, const char *, int32_t) {}
    static void outputMode(void *, wl_output *, uint32_t, int32_t, int32_t, int32_t) {}
    static void outputDone(void *data, wl_output *) { static_cast<Capture *>(data)->selectWorkspace(); }
    static void outputScale(void *, wl_output *, int32_t) {}
    static void outputName(void *data, wl_output *o, const char *n) { static_cast<Capture *>(data)->outputs[o] = QString::fromUtf8(n); }
    static void outputDescription(void *, wl_output *, const char *) {}
    static void group(void *data, ext_workspace_manager_v1 *, ext_workspace_group_handle_v1 *g) {
        auto *c = static_cast<Capture *>(data); c->groups.insert(g, Group{});
        static const ext_workspace_group_handle_v1_listener l = {groupCapabilities, outputEnter, outputLeave, workspaceEnter, workspaceLeave, groupRemoved};
        ext_workspace_group_handle_v1_add_listener(g, &l, c);
    }
    static void groupCapabilities(void *, ext_workspace_group_handle_v1 *, uint32_t) {}
    static void outputEnter(void *data, ext_workspace_group_handle_v1 *g, wl_output *o) { static_cast<Capture *>(data)->groups[g].outputs.insert(o); }
    static void outputLeave(void *data, ext_workspace_group_handle_v1 *g, wl_output *o) { static_cast<Capture *>(data)->groups[g].outputs.remove(o); }
    static void workspaceEnter(void *data, ext_workspace_group_handle_v1 *g, ext_workspace_handle_v1 *w) { static_cast<Capture *>(data)->groups[g].workspaces.insert(w); }
    static void workspaceLeave(void *data, ext_workspace_group_handle_v1 *g, ext_workspace_handle_v1 *w) { static_cast<Capture *>(data)->groups[g].workspaces.remove(w); }
    static void groupRemoved(void *data, ext_workspace_group_handle_v1 *g) { auto *c = static_cast<Capture *>(data); c->groups.remove(g); ext_workspace_group_handle_v1_destroy(g); }
    static void workspace(void *data, ext_workspace_manager_v1 *, ext_workspace_handle_v1 *w) {
        auto *c = static_cast<Capture *>(data); c->activeWorkspaces.insert(w, false);
        static const ext_workspace_handle_v1_listener l = {workspaceId, workspaceName, workspaceCoords, workspaceState, workspaceCapabilities, workspaceRemoved};
        ext_workspace_handle_v1_add_listener(w, &l, c);
    }
    static void managerDone(void *data, ext_workspace_manager_v1 *) { static_cast<Capture *>(data)->selectWorkspace(); }
    static void managerFinished(void *, ext_workspace_manager_v1 *) {}
    static void workspaceId(void *, ext_workspace_handle_v1 *, const char *) {}
    static void workspaceName(void *, ext_workspace_handle_v1 *, const char *) {}
    static void workspaceCoords(void *, ext_workspace_handle_v1 *, wl_array *) {}
    static void workspaceState(void *data, ext_workspace_handle_v1 *w, uint32_t state) { static_cast<Capture *>(data)->activeWorkspaces[w] = state & EXT_WORKSPACE_HANDLE_V1_STATE_ACTIVE; }
    static void workspaceCapabilities(void *, ext_workspace_handle_v1 *, uint32_t) {}
    static void workspaceRemoved(void *data, ext_workspace_handle_v1 *w) {
        auto *c = static_cast<Capture *>(data); c->activeWorkspaces.remove(w);
        if (c->target == w) c->resetSession();
        ext_workspace_handle_v1_destroy(w);
    }
    void resetSession() {
        timer.stop();
        if (frame) { ext_image_copy_capture_frame_v1_destroy(frame); frame = nullptr; }
        if (session) { ext_image_copy_capture_session_v1_destroy(session); session = nullptr; }
        if (buffer) { wl_buffer_destroy(buffer); buffer = nullptr; }
        if (pixels) { munmap(pixels, size); pixels = nullptr; }
        target = nullptr; constraints = false; argb = false; failed = false;
        { QMutexLocker lock(&mutex); image = QImage(); }
        emit changed();
    }
    void selectWorkspace() {
        if (!shm || !cm || !im) return;
        ext_workspace_handle_v1 *wanted = nullptr;
        for (auto i = groups.cbegin(); i != groups.cend(); ++i) {
            bool matches = false;
            for (auto *o : i->outputs) if (outputs.value(o) == name) matches = true;
            if (!matches) continue;
            for (auto *w : i->workspaces) if (activeWorkspaces.value(w, false)) { wanted = w; break; }
        }
        if (wanted == target) return;
        resetSession();
        if (!wanted) return;
        target = wanted;
        auto *source = hyprland_workspace_image_capture_source_manager_v1_create_source(cm, target, 0);
        session = ext_image_copy_capture_manager_v1_create_session(im, source, 0);
        ext_image_capture_source_v1_destroy(source);
        static const ext_image_copy_capture_session_v1_listener listener = {sessionSize, sessionFormat, sessionDevice, sessionModifier, sessionDone, sessionStopped};
        ext_image_copy_capture_session_v1_add_listener(session, &listener, this);
        wl_display_flush(display);
    }
    static void sessionSize(void *data, ext_image_copy_capture_session_v1 *, uint32_t w, uint32_t h) { auto *c = static_cast<Capture *>(data); c->width = int(w); c->height = int(h); }
    static void sessionFormat(void *data, ext_image_copy_capture_session_v1 *, uint32_t format) { if (format == WL_SHM_FORMAT_ARGB8888) static_cast<Capture *>(data)->argb = true; }
    static void sessionDevice(void *, ext_image_copy_capture_session_v1 *, wl_array *) {}
    static void sessionModifier(void *, ext_image_copy_capture_session_v1 *, uint32_t, wl_array *) {}
    static void sessionDone(void *data, ext_image_copy_capture_session_v1 *) { auto *c = static_cast<Capture *>(data); c->constraints = true; if (!c->frame) c->timer.start(0); }
    static void sessionStopped(void *data, ext_image_copy_capture_session_v1 *) {
        auto *c = static_cast<Capture *>(data); c->failed = true; c->timer.stop();
        { QMutexLocker lock(&c->mutex); c->image = QImage(); }
        emit c->changed();
    }
    bool makeBuffer() {
        if (buffer && width == bufferWidth && height == bufferHeight) return true;
        if (buffer) wl_buffer_destroy(buffer);
        if (pixels) munmap(pixels, size);
        buffer = nullptr; pixels = nullptr;
        if (!argb || width <= 0 || height <= 0 || width > 16384 || height > 16384 || qint64(width) * height * 4 > INT_MAX) return false;
        size = size_t(width) * size_t(height) * 4;
        int fd = memfd_create("serpantinum-glass", MFD_CLOEXEC);
        if (fd < 0) return false;
        if (ftruncate(fd, off_t(size)) == -1) { close(fd); return false; }
        pixels = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (pixels == MAP_FAILED) { pixels = nullptr; close(fd); return false; }
        wl_shm_pool *pool = wl_shm_create_pool(shm, fd, int(size)); close(fd);
        buffer = wl_shm_pool_create_buffer(pool, 0, width, height, width * 4, WL_SHM_FORMAT_ARGB8888);
        wl_shm_pool_destroy(pool);
        bufferWidth = width; bufferHeight = height;
        return buffer != nullptr;
    }
    void capture() {
        if (failed || !session || !constraints || frame || !makeBuffer()) return;
        frame = ext_image_copy_capture_session_v1_create_frame(session);
        static const ext_image_copy_capture_frame_v1_listener listener = {frameTransform, frameDamage, frameTime, frameReady, frameFailed};
        ext_image_copy_capture_frame_v1_add_listener(frame, &listener, this);
        ext_image_copy_capture_frame_v1_attach_buffer(frame, buffer);
        ext_image_copy_capture_frame_v1_damage_buffer(frame, 0, 0, bufferWidth, bufferHeight);
        ext_image_copy_capture_frame_v1_capture(frame);
        wl_display_flush(display);
    }
    static void frameTransform(void *, ext_image_copy_capture_frame_v1 *, uint32_t) {}
    static void frameDamage(void *, ext_image_copy_capture_frame_v1 *, int32_t, int32_t, int32_t, int32_t) {}
    static void frameTime(void *, ext_image_copy_capture_frame_v1 *, uint32_t, uint32_t, uint32_t) {}
    static void frameReady(void *data, ext_image_copy_capture_frame_v1 *f) {
        auto *c = static_cast<Capture *>(data);
        QImage next(static_cast<uchar *>(c->pixels), c->bufferWidth, c->bufferHeight, QImage::Format_ARGB32_Premultiplied);
        { QMutexLocker lock(&c->mutex); c->image = next.copy(); }
        ext_image_copy_capture_frame_v1_destroy(f); c->frame = nullptr;
        emit c->changed();
        if (!c->failed) c->timer.start(100);
    }
    static void frameFailed(void *data, ext_image_copy_capture_frame_v1 *f, uint32_t) {
        auto *c = static_cast<Capture *>(data); ext_image_copy_capture_frame_v1_destroy(f); c->frame = nullptr; if (!c->failed) c->timer.start(1000);
    }
};
QHash<QString, Capture *> Capture::instances;

class DesktopCapture : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QString screenName READ screenName WRITE setScreenName NOTIFY screenNameChanged)
    Q_PROPERTY(bool hasContent READ hasContent NOTIFY hasContentChanged)
public:
    using QQuickPaintedItem::QQuickPaintedItem;
    ~DesktopCapture() override { if (capture) capture->release(); }
    QString screenName() const { return screen; }
    bool hasContent() const { return capture && capture->hasFrame(); }
    void setScreenName(const QString &value) {
        if (screen == value) return;
        if (capture) { disconnect(capture, nullptr, this, nullptr); capture->release(); capture = nullptr; }
        screen = value;
        if (!screen.isEmpty()) {
            capture = Capture::acquire(screen);
            connect(capture, &Capture::changed, this, [this] { update(); emit hasContentChanged(); emit frameChanged(); });
        }
        update(); emit screenNameChanged(); emit hasContentChanged();
    }
    void paint(QPainter *p) override { if (capture) p->drawImage(boundingRect(), capture->frameImage()); }
signals:
    void screenNameChanged();
    void hasContentChanged();
    void frameChanged();
private:
    QString screen;
    Capture *capture = nullptr;
};
class DesktopCapturePlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override { qmlRegisterType<DesktopCapture>(uri, 1, 0, "DesktopCapture"); }
};
#include "capture.moc"
