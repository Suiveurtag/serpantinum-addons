/* Offer text and PNG together over ext-data-control. Input: two uint32 big-endian
 * lengths (UINT32_MAX means absent), followed by text and PNG bytes. */
#include <arpa/inet.h>
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>
#include "ext-data-control-v1-client-protocol.h"

#define MAX_DATA (8 * 1024 * 1024)
#define OWN_MIME "application/x-beamer-hyprland-clipboard"
static struct wl_seat *seat;
static struct ext_data_control_manager_v1 *manager;
static unsigned char *text_data, *png_data;
static uint32_t text_size, png_size;
static int finished;

static int read_all(void *data, size_t size) {
    size_t done = 0;
    while (done < size) {
        ssize_t n = read(STDIN_FILENO, (char *)data + done, size - done);
        if (n <= 0) return -1;
        done += (size_t)n;
    }
    return 0;
}
static void write_all(int fd, const void *data, size_t size) {
    const char *p = data;
    while (size) {
        ssize_t n = write(fd, p, size);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        p += n; size -= (size_t)n;
    }
}
static void global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t version) {
    (void)d; (void)version;
    if (!strcmp(iface, wl_seat_interface.name) && !seat)
        seat = wl_registry_bind(r, name, &wl_seat_interface, 1);
    else if (!strcmp(iface, ext_data_control_manager_v1_interface.name))
        manager = wl_registry_bind(r, name, &ext_data_control_manager_v1_interface, 1);
}
static void global_remove(void *d, struct wl_registry *r, uint32_t name) { (void)d; (void)r; (void)name; }
static const struct wl_registry_listener registry_listener = { global, global_remove };
static void offer_mime(void *d, struct ext_data_control_offer_v1 *o, const char *mime) { (void)d; (void)o; (void)mime; }
static const struct ext_data_control_offer_v1_listener offer_listener = { offer_mime };
static void data_offer(void *d, struct ext_data_control_device_v1 *dev, struct ext_data_control_offer_v1 *offer) {
    (void)d; (void)dev; ext_data_control_offer_v1_add_listener(offer, &offer_listener, NULL);
}
static struct ext_data_control_offer_v1 *selection, *primary;
static void selection_changed(void *d, struct ext_data_control_device_v1 *dev, struct ext_data_control_offer_v1 *offer) {
    (void)d; (void)dev;
    if (selection) ext_data_control_offer_v1_destroy(selection);
    selection = offer;
}
static void primary_changed(void *d, struct ext_data_control_device_v1 *dev, struct ext_data_control_offer_v1 *offer) {
    (void)d; (void)dev;
    if (primary) ext_data_control_offer_v1_destroy(primary);
    primary = offer;
}
static void device_finished(void *d, struct ext_data_control_device_v1 *dev) { (void)d; (void)dev; finished = 1; }
static const struct ext_data_control_device_v1_listener device_listener = { data_offer, selection_changed, device_finished, primary_changed };
static void send_data(void *d, struct ext_data_control_source_v1 *source, const char *mime, int fd) {
    (void)d; (void)source;
    /* A slow receiving client must never block Wayland event processing. */
    pid_t child = fork();
    if (child == 0) {
        if (!strcmp(mime, "image/png")) write_all(fd, png_data, png_size);
        else if (!strcmp(mime, OWN_MIME)) write_all(fd, "1", 1);
        else write_all(fd, text_data, text_size);
        close(fd); _exit(0);
    }
    close(fd);
}
static void cancelled(void *d, struct ext_data_control_source_v1 *source) { (void)d; (void)source; finished = 1; }
static const struct ext_data_control_source_v1_listener source_listener = { send_data, cancelled };
int main(void) {
    uint32_t lengths[2];
    if (read_all(lengths, sizeof lengths)) return 1;
    text_size = ntohl(lengths[0]); png_size = ntohl(lengths[1]);
    if ((text_size != UINT32_MAX && text_size > MAX_DATA) ||
        (png_size != UINT32_MAX && png_size > MAX_DATA) ||
        (text_size == UINT32_MAX && png_size == UINT32_MAX)) return 1;
    if (text_size != UINT32_MAX) {
        text_data = malloc(text_size ? text_size : 1);
        if (!text_data || read_all(text_data, text_size)) return 1;
    }
    if (png_size != UINT32_MAX) {
        png_data = malloc(png_size ? png_size : 1);
        if (!png_data || read_all(png_data, png_size)) return 1;
    }
    signal(SIGCHLD, SIG_IGN); signal(SIGPIPE, SIG_IGN);
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) return 1;
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !seat || !manager) return 1;
    struct ext_data_control_device_v1 *device = ext_data_control_manager_v1_get_data_device(manager, seat);
    ext_data_control_device_v1_add_listener(device, &device_listener, NULL);
    struct ext_data_control_source_v1 *source = ext_data_control_manager_v1_create_data_source(manager);
    ext_data_control_source_v1_add_listener(source, &source_listener, NULL);
    if (text_data) {
        ext_data_control_source_v1_offer(source, "text/plain;charset=utf-8");
        ext_data_control_source_v1_offer(source, "text/plain");
        ext_data_control_source_v1_offer(source, "UTF8_STRING");
    }
    if (png_data) ext_data_control_source_v1_offer(source, "image/png");
    ext_data_control_source_v1_offer(source, OWN_MIME);
    ext_data_control_device_v1_set_selection(device, source);
    if (wl_display_roundtrip(display) < 0) return 1;
    if (write(STDOUT_FILENO, "1", 1) != 1) return 1;
    close(STDOUT_FILENO);
    while (!finished && wl_display_dispatch(display) >= 0) {}
    wl_display_disconnect(display);
    free(text_data); free(png_data);
    return 0;
}
