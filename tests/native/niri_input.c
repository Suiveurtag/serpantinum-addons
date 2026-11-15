#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include "virtual-keyboard-unstable-v1-client-protocol.h"
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"
static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *pointer_manager;
static struct zwp_virtual_keyboard_manager_v1 *keyboard_manager;
static void capabilities(void *d, struct wl_seat *s, uint32_t c) {(void)d;(void)s;(void)c;}
static const struct wl_seat_listener seat_listener = {.capabilities=capabilities};
static void global(void *d, struct wl_registry *r, uint32_t id, const char *name, uint32_t version) {
    (void)d;(void)version;
    if (!strcmp(name,"wl_seat")) {seat=wl_registry_bind(r,id,&wl_seat_interface,1);wl_seat_add_listener(seat,&seat_listener,NULL);}
    else if (!strcmp(name,"zwlr_virtual_pointer_manager_v1")) pointer_manager=wl_registry_bind(r,id,&zwlr_virtual_pointer_manager_v1_interface,1);
    else if (!strcmp(name,"zwp_virtual_keyboard_manager_v1")) keyboard_manager=wl_registry_bind(r,id,&zwp_virtual_keyboard_manager_v1_interface,1);
}
static void removed(void *d, struct wl_registry *r, uint32_t id) {(void)d;(void)r;(void)id;}
static const struct wl_registry_listener registry_listener={global,removed};
int main(int argc,char **argv) {
    if(argc<3 || !getenv("SERPANTINUM_NIRI_TEST") || strcmp(getenv("SERPANTINUM_NIRI_TEST"),"1")) return 2;
    struct wl_display *display=wl_display_connect(NULL); if(!display) return 2;
    struct wl_registry *registry=wl_display_get_registry(display);
    wl_registry_add_listener(registry,&registry_listener,NULL);wl_display_roundtrip(display);
    if(!seat||!pointer_manager||!keyboard_manager) return 3;
    if(!strcmp(argv[1],"motion")&&argc==4) {
        struct zwlr_virtual_pointer_v1 *pointer=zwlr_virtual_pointer_manager_v1_create_virtual_pointer(pointer_manager,seat);
        zwlr_virtual_pointer_v1_motion(pointer,1,wl_fixed_from_double(atof(argv[2])),wl_fixed_from_double(atof(argv[3])));
        zwlr_virtual_pointer_v1_frame(pointer);wl_display_roundtrip(display);
        zwlr_virtual_pointer_v1_destroy(pointer);
    } else if(!strcmp(argv[1],"stroke")) {
        struct zwlr_virtual_pointer_v1 *pointer=zwlr_virtual_pointer_manager_v1_create_virtual_pointer(pointer_manager,seat);
        zwlr_virtual_pointer_v1_button(pointer,1,272,WL_POINTER_BUTTON_STATE_PRESSED);
        zwlr_virtual_pointer_v1_frame(pointer);
        zwlr_virtual_pointer_v1_motion(pointer,2,wl_fixed_from_int(40),wl_fixed_from_int(30));
        zwlr_virtual_pointer_v1_frame(pointer);
        zwlr_virtual_pointer_v1_button(pointer,3,272,WL_POINTER_BUTTON_STATE_RELEASED);
        zwlr_virtual_pointer_v1_frame(pointer);wl_display_roundtrip(display);
        zwlr_virtual_pointer_v1_destroy(pointer);
    } else if(!strcmp(argv[1],"key")) {
        struct zwp_virtual_keyboard_v1 *keyboard=zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(keyboard_manager,seat);
        struct xkb_context *ctx=xkb_context_new(XKB_CONTEXT_NO_FLAGS);
        struct xkb_rule_names names={.layout="fr"};
        struct xkb_keymap *map=xkb_keymap_new_from_names(ctx,&names,XKB_KEYMAP_COMPILE_NO_FLAGS);
        char *text=xkb_keymap_get_as_string(map,XKB_KEYMAP_FORMAT_TEXT_V1);size_t length=strlen(text)+1;
        int fd=memfd_create("niri-test-keymap",MFD_CLOEXEC);if(fd<0||write(fd,text,length)!=(ssize_t)length)return 4;
        zwp_virtual_keyboard_v1_keymap(keyboard,1,fd,length);
        zwp_virtual_keyboard_v1_key(keyboard,1,atoi(argv[2]),1);
        zwp_virtual_keyboard_v1_key(keyboard,2,atoi(argv[2]),0);
        wl_display_roundtrip(display);zwp_virtual_keyboard_v1_destroy(keyboard);
        close(fd);free(text);xkb_keymap_unref(map);xkb_context_unref(ctx);
    } else return 5;
    wl_display_roundtrip(display);wl_display_disconnect(display);return 0;
}
