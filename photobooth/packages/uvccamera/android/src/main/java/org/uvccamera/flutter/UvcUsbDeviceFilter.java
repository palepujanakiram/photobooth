package org.uvccamera.flutter;

import android.hardware.usb.UsbConstants;
import android.hardware.usb.UsbDevice;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Distinguishes UVC / HDMI capture devices from HID dongles and other USB gear.
 *
 * <p>Wireless mouse/keyboard receivers often report device class 0 (per-interface)
 * with only HID interfaces. libuvc then fails with {@code UVC_ERROR_INVALID_DEVICE}.
 */
/* package-private */ final class UvcUsbDeviceFilter {

    /** DNP DS-RX1(S)HS — matches Dart {@code kDnpPrinterUsbVendorId}. */
    static final int VENDOR_DNP = 0x1343;

    /** Canon PTP/EDSDK — not UVC. */
    static final int VENDOR_CANON = 0x04A9;

    /** Apple USB gadgets (wireless-debug NCM) — not capture cards. */
    static final int VENDOR_APPLE = 0x05AC;

    private UvcUsbDeviceFilter() {
    }

    static boolean isLikelyUvcCaptureDevice(final UsbDevice device) {
        if (device == null) {
            return false;
        }
        final int vendorId = device.getVendorId();
        if (vendorId == VENDOR_DNP || vendorId == VENDOR_CANON || vendorId == VENDOR_APPLE) {
            return false;
        }
        if (isUvcDeviceClass(device.getDeviceClass(), device.getDeviceSubclass())) {
            return true;
        }
        if (isNonCameraDeviceClass(device.getDeviceClass())) {
            return false;
        }
        return hasCaptureInterface(device);
    }

    static Map<String, Object> toDeviceMap(final @NonNull UsbDevice device) {
        final Map<String, Object> map = new HashMap<>();
        map.put("name", device.getDeviceName());
        map.put("deviceClass", device.getDeviceClass());
        map.put("deviceSubclass", device.getDeviceSubclass());
        map.put("vendorId", device.getVendorId());
        map.put("productId", device.getProductId());
        map.put("interfaceClasses", interfaceClasses(device));
        return map;
    }

    static List<Integer> interfaceClasses(final @NonNull UsbDevice device) {
        final int count = device.getInterfaceCount();
        final List<Integer> classes = new ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            classes.add(device.getInterface(i).getInterfaceClass());
        }
        return classes;
    }

    static boolean isUvcDeviceClass(final int deviceClass, final int deviceSubclass) {
        if (deviceClass == UsbConstants.USB_CLASS_VIDEO) {
            return true;
        }
        if (deviceClass == UsbConstants.USB_CLASS_MISC && deviceSubclass == 2) {
            return true;
        }
        return deviceClass == UsbConstants.USB_CLASS_VENDOR_SPEC;
    }

    static boolean isNonCameraDeviceClass(final int deviceClass) {
        return deviceClass == UsbConstants.USB_CLASS_HID
                || deviceClass == UsbConstants.USB_CLASS_PRINTER
                || deviceClass == UsbConstants.USB_CLASS_HUB
                || deviceClass == UsbConstants.USB_CLASS_COMM
                || deviceClass == UsbConstants.USB_CLASS_STILL_IMAGE
                || deviceClass == UsbConstants.USB_CLASS_MASS_STORAGE;
    }

    static boolean hasCaptureInterface(final @NonNull UsbDevice device) {
        final int count = device.getInterfaceCount();
        for (int i = 0; i < count; i++) {
            if (isCaptureInterfaceClass(device.getInterface(i).getInterfaceClass())) {
                return true;
            }
        }
        return false;
    }

    static boolean isCaptureInterfaceClass(final int interfaceClass) {
        return interfaceClass == UsbConstants.USB_CLASS_VIDEO
                || interfaceClass == UsbConstants.USB_CLASS_MISC
                || interfaceClass == UsbConstants.USB_CLASS_VENDOR_SPEC;
    }
}
