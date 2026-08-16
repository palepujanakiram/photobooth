#include "canon_camera.h"

#include <cstdio>

static bool bytesLookLikeJpeg(const std::vector<uint8_t>& bytes) {
    return bytes.size() >= 3 &&
           bytes[0] == 0xFF &&
           bytes[1] == 0xD8 &&
           bytes[2] == 0xFF;
}

static bool formatIsNonJpegStill(EdsUInt32 format) {
    return format == kEdsObjectFormat_CR2 ||
           format == kEdsObjectFormat_CR3 ||
           format == kEdsObjectFormat_HEIF_CODE;
}

void CanonCamera::_prepareStillImpl() {
    _stillArmed = true;
    _stopLiveViewImpl();
    canonSleepMs(500);
}

bool CanonCamera::_pressShutter() {
    EdsSendCommand(_camera, kEdsCameraCommand_PressShutterButton,
                   kEdsCameraCommand_ShutterButton_OFF);
    canonSleepMs(50);
    EdsError err = EdsSendCommand(
        _camera,
        kEdsCameraCommand_PressShutterButton,
        kEdsCameraCommand_ShutterButton_Halfway);
    if (err != EDS_ERR_OK) {
        fprintf(stderr, "[canon] shutter halfway: 0x%08X\n", err);
    }
    canonSleepMs(400);
    err = EdsSendCommand(
        _camera,
        kEdsCameraCommand_PressShutterButton,
        kEdsCameraCommand_ShutterButton_Completely);
    if (err != EDS_ERR_OK) {
        fprintf(stderr, "[canon] shutter completely: 0x%08X; trying NonAF\n", err);
        err = EdsSendCommand(
            _camera,
            kEdsCameraCommand_PressShutterButton,
            kEdsCameraCommand_ShutterButton_Completely_NonAF);
    }
    if (err != EDS_ERR_OK) {
        fprintf(stderr, "[canon] PressShutterButton: 0x%08X\n", err);
        EdsSendCommand(_camera, kEdsCameraCommand_PressShutterButton,
                       kEdsCameraCommand_ShutterButton_OFF);
        return false;
    }
    canonSleepMs(200);
    EdsSendCommand(_camera, kEdsCameraCommand_PressShutterButton,
                   kEdsCameraCommand_ShutterButton_OFF);
    return true;
}

std::vector<uint8_t> CanonCamera::_waitForJpeg(int timeoutSeconds) {
    std::vector<uint8_t> result;
    auto deadline = std::chrono::steady_clock::now()
                    + std::chrono::seconds(timeoutSeconds);
    while (result.empty() && std::chrono::steady_clock::now() < deadline) {
        EdsGetEvent();
        while (result.empty() && !_pendingItems.empty()) {
            auto item = _pendingItems.front();
            _pendingItems.pop_front();
            result = _downloadJpegOrCancel(item);
        }
        if (result.empty()) canonSleepMs(20);
    }
    return result;
}

void CanonCamera::_drainTrailingTransfers() {
    auto drainUntil = std::chrono::steady_clock::now()
                      + std::chrono::milliseconds(800);
    while (std::chrono::steady_clock::now() < drainUntil) {
        EdsGetEvent();
        _cancelPendingTransfers();
        canonSleepMs(20);
    }
}

void CanonCamera::_restoreLiveViewAfterStill() {
    _stillArmed = false;
    _startLiveViewImpl();
}

std::vector<uint8_t> CanonCamera::_captureImpl(int timeoutSeconds) {
    if (!_camera) return {};

    _cancelPendingTransfers();

    _stillArmed = true;
    if (_lvActive) {
        _stopLiveViewImpl();
        canonSleepMs(600);
    }

    if (!_pressShutter()) {
        _restoreLiveViewAfterStill();
        return {};
    }

    // RAW+JPEG bodies transfer RAW first. Skip non-JPEG and wait for JPEG.
    std::vector<uint8_t> result = _waitForJpeg(timeoutSeconds);
    if (result.empty()) {
        fprintf(stderr, "[canon] capture timeout (no JPEG still)\n");
        _cancelPendingTransfers();
        _restoreLiveViewAfterStill();
        return {};
    }

    // Cancel a trailing RAW/HEIF transfer so the camera does not stall.
    _drainTrailingTransfers();
    _restoreLiveViewAfterStill();
    return result;
}

std::vector<uint8_t> CanonCamera::_downloadItemBytes(
        EdsDirectoryItemRef item, EdsUInt64 size) {
    EdsStreamRef stream = nullptr;
    if (EdsCreateMemoryStream(size, &stream) != EDS_ERR_OK) {
        EdsDownloadCancel(item);
        EdsRelease(item);
        return {};
    }
    EdsError dl = EdsDownload(item, size, stream);
    if (dl != EDS_ERR_OK) {
        fprintf(stderr, "[canon] EdsDownload: 0x%08X\n", dl);
        EdsDownloadCancel(item);
        EdsRelease(stream);
        EdsRelease(item);
        return {};
    }
    EdsDownloadComplete(item);
    auto result = _streamToBytes(stream);
    EdsRelease(stream);
    EdsRelease(item);
    return result;
}

std::vector<uint8_t> CanonCamera::_downloadJpegOrCancel(
        EdsDirectoryItemRef item) {
    if (!item) return {};

    EdsDirectoryItemInfo info{};
    EdsGetDirectoryItemInfo(item, &info);
    fprintf(stderr,
            "[canon] dir item name=%s format=0x%X size=%llu\n",
            info.szFileName,
            info.format,
            static_cast<unsigned long long>(info.size));

    if (formatIsNonJpegStill(info.format)) {
        fprintf(stderr, "[canon] skip non-JPEG transfer\n");
        EdsDownloadCancel(item);
        EdsRelease(item);
        return {};
    }

    auto result = _downloadItemBytes(item, info.size);
    if (!bytesLookLikeJpeg(result)) {
        fprintf(stderr,
                "[canon] downloaded %zu bytes are not JPEG\n",
                result.size());
        return {};
    }
    fprintf(stderr, "[canon] JPEG still %zu bytes\n", result.size());
    return result;
}
