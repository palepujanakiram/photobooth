#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/*
 * LD_PRELOAD helper for the glibc Canon sidecar.
 *
 * Android UsbManager.hasPermission() does not chmod usbfs nodes.
 * Java opens the node via UsbManager.openDevice(); the spawn helper inherits
 * that fd. This hook returns dup(CANON_USB_FD) when EDSDK/libusb opens
 * CANON_USB_PATH.
 *
 * Ubuntu's libusb is built with _FORTIFY_SOURCE, so it calls __open_2 rather
 * than open(). Both must be interposed.
 */

static int g_usb_fd = -1;
static const char *g_usb_path = NULL;

static int (*real_open)(const char *, int, ...) = NULL;
static int (*real_open64)(const char *, int, ...) = NULL;
static int (*real_openat)(int, const char *, int, ...) = NULL;
static int (*real_openat64)(int, const char *, int, ...) = NULL;
static int (*real_open2)(const char *, int) = NULL;
static int (*real_open64_2)(const char *, int) = NULL;
static int (*real_openat2)(int, const char *, int) = NULL;
static int (*real_openat64_2)(int, const char *, int) = NULL;
static int (*real_access)(const char *, int) = NULL;

static int is_target(const char *path) {
    return g_usb_fd >= 0 && g_usb_path && path && strcmp(path, g_usb_path) == 0;
}

static int dup_usb(const char *path) {
    int fd = dup(g_usb_fd);
    fprintf(stderr, "[usb-hook] dup fd=%d -> %d for %s\n", g_usb_fd, fd, path);
    return fd;
}

__attribute__((constructor))
static void init_hook(void) {
    const char *fdstr = getenv("CANON_USB_FD");
    g_usb_path = getenv("CANON_USB_PATH");
    if (fdstr) {
        g_usb_fd = atoi(fdstr);
    }
    real_open = dlsym(RTLD_NEXT, "open");
    real_open64 = dlsym(RTLD_NEXT, "open64");
    real_openat = dlsym(RTLD_NEXT, "openat");
    real_openat64 = dlsym(RTLD_NEXT, "openat64");
    real_open2 = dlsym(RTLD_NEXT, "__open_2");
    real_open64_2 = dlsym(RTLD_NEXT, "__open64_2");
    real_openat2 = dlsym(RTLD_NEXT, "__openat_2");
    real_openat64_2 = dlsym(RTLD_NEXT, "__openat64_2");
    real_access = dlsym(RTLD_NEXT, "access");
    fprintf(
        stderr,
        "[usb-hook] loaded fd=%d path=%s\n",
        g_usb_fd,
        g_usb_path ? g_usb_path : "(null)");
}

static mode_t creat_mode(int flags, va_list ap) {
    if (flags & O_CREAT) {
        return (mode_t)va_arg(ap, int);
    }
#ifdef O_TMPFILE
    if (flags & O_TMPFILE) {
        return (mode_t)va_arg(ap, int);
    }
#endif
    return 0;
}

int open(const char *pathname, int flags, ...) {
    if (is_target(pathname)) {
        return dup_usb(pathname);
    }
    va_list ap;
    va_start(ap, flags);
    mode_t mode = creat_mode(flags, ap);
    va_end(ap);
    if (!real_open) {
        return -1;
    }
    if (flags & O_CREAT) {
        return real_open(pathname, flags, mode);
    }
    return real_open(pathname, flags);
}

int open64(const char *pathname, int flags, ...) {
    if (is_target(pathname)) {
        return dup_usb(pathname);
    }
    va_list ap;
    va_start(ap, flags);
    mode_t mode = creat_mode(flags, ap);
    va_end(ap);
    if (!real_open64) {
        return open(pathname, flags, mode);
    }
    if (flags & O_CREAT) {
        return real_open64(pathname, flags, mode);
    }
    return real_open64(pathname, flags);
}

int openat(int dirfd, const char *pathname, int flags, ...) {
    if (is_target(pathname)) {
        return dup_usb(pathname);
    }
    va_list ap;
    va_start(ap, flags);
    mode_t mode = creat_mode(flags, ap);
    va_end(ap);
    if (!real_openat) {
        return -1;
    }
    if (flags & O_CREAT) {
        return real_openat(dirfd, pathname, flags, mode);
    }
    return real_openat(dirfd, pathname, flags);
}

int openat64(int dirfd, const char *pathname, int flags, ...) {
    if (is_target(pathname)) {
        return dup_usb(pathname);
    }
    va_list ap;
    va_start(ap, flags);
    mode_t mode = creat_mode(flags, ap);
    va_end(ap);
    if (!real_openat64) {
        return openat(dirfd, pathname, flags, mode);
    }
    if (flags & O_CREAT) {
        return real_openat64(dirfd, pathname, flags, mode);
    }
    return real_openat64(dirfd, pathname, flags);
}

int __open_2(const char *pathname, int flags) {
    if (is_target(pathname)) {
        return dup_usb(pathname);
    }
    if (!real_open2) {
        return open(pathname, flags);
    }
    return real_open2(pathname, flags);
}

int __open64_2(const char *pathname, int flags) {
    if (is_target(pathname)) {
        return dup_usb(pathname);
    }
    if (!real_open64_2) {
        return __open_2(pathname, flags);
    }
    return real_open64_2(pathname, flags);
}

int __openat_2(int dirfd, const char *pathname, int flags) {
    if (is_target(pathname)) {
        return dup_usb(pathname);
    }
    if (!real_openat2) {
        return openat(dirfd, pathname, flags);
    }
    return real_openat2(dirfd, pathname, flags);
}

int __openat64_2(int dirfd, const char *pathname, int flags) {
    if (is_target(pathname)) {
        return dup_usb(pathname);
    }
    if (!real_openat64_2) {
        return __openat_2(dirfd, pathname, flags);
    }
    return real_openat64_2(dirfd, pathname, flags);
}

int access(const char *pathname, int mode) {
    if (is_target(pathname)) {
        return 0;
    }
    if (!real_access) {
        return -1;
    }
    return real_access(pathname, mode);
}
