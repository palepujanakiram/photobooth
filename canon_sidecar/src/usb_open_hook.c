#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/usb/ch9.h>
#include <linux/usbdevice_fs.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
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
static int (*real_ioctl)(int, unsigned long, ...) = NULL;
static int g_ioctl_fail_logs = 0;

static int is_target(const char *path) {
    return g_usb_fd >= 0 && g_usb_path && path && strcmp(path, g_usb_path) == 0;
}

static int is_usb_fd(int fd) {
    struct stat hooked;
    struct stat other;
    if (g_usb_fd < 0 || fd < 0) {
        return 0;
    }
    if (fstat(g_usb_fd, &hooked) != 0 || fstat(fd, &other) != 0) {
        return 0;
    }
    return hooked.st_dev == other.st_dev && hooked.st_ino == other.st_ino;
}

static void probe_usb_descriptor(void) {
    unsigned char buf[18];
    struct usbdevfs_ctrltransfer ctrl;
    int rc;
    unsigned vid;
    unsigned pid;
    if (g_usb_fd < 0 || real_ioctl == NULL) {
        return;
    }
    memset(&ctrl, 0, sizeof(ctrl));
    memset(buf, 0, sizeof(buf));
    ctrl.bRequestType = USB_DIR_IN | USB_TYPE_STANDARD | USB_RECIP_DEVICE;
    ctrl.bRequest = USB_REQ_GET_DESCRIPTOR;
    ctrl.wValue = (USB_DT_DEVICE << 8);
    ctrl.wIndex = 0;
    ctrl.wLength = sizeof(buf);
    ctrl.timeout = 1000;
    ctrl.data = buf;
    rc = real_ioctl(g_usb_fd, USBDEVFS_CONTROL, &ctrl);
    if (rc < 0) {
        fprintf(stderr, "[usb-hook] GET_DESCRIPTOR failed: %s\n", strerror(errno));
        return;
    }
    vid = (unsigned)buf[8] | ((unsigned)buf[9] << 8);
    pid = (unsigned)buf[10] | ((unsigned)buf[11] << 8);
    fprintf(stderr, "[usb-hook] GET_DESCRIPTOR vid=0x%04x pid=0x%04x\n", vid, pid);
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
    real_ioctl = dlsym(RTLD_NEXT, "ioctl");
    fprintf(
        stderr,
        "[usb-hook] loaded fd=%d path=%s\n",
        g_usb_fd,
        g_usb_path ? g_usb_path : "(null)");
    probe_usb_descriptor();
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

int ioctl(int fd, unsigned long request, ...) {
    va_list ap;
    void *arg;
    int rc;
    va_start(ap, request);
    arg = va_arg(ap, void *);
    va_end(ap);
    if (!real_ioctl) {
        errno = ENOSYS;
        return -1;
    }
    rc = real_ioctl(fd, request, arg);
    if (rc < 0 && is_usb_fd(fd) && g_ioctl_fail_logs < 8) {
        g_ioctl_fail_logs++;
        fprintf(
            stderr,
            "[usb-hook] ioctl fd=%d req=0x%lx failed: %s\n",
            fd,
            request,
            strerror(errno));
    }
    return rc;
}
