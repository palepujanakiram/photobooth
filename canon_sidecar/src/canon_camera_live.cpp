#include "canon_camera.h"

#include <cstdio>
#include <functional>

bool CanonCamera::_startLiveViewImpl() {
    if (_lvActive) return true;
    if (!_camera) return false;

    if (!_setProp(kEdsPropID_Evf_Mode, 1)) {
        fprintf(stderr, "[canon] set Evf_Mode failed\n");
        return false;
    }
    canonSleepMs(100);
    if (!_setProp(kEdsPropID_Evf_OutputDevice, kEdsEvfOutputDevice_PC)) {
        fprintf(stderr, "[canon] set Evf_OutputDevice failed\n");
        return false;
    }
    canonSleepMs(150);
    _lvActive = true;
    return true;
}

bool CanonCamera::_stopLiveViewImpl() {
    if (!_lvActive || !_camera) return true;
    _setProp(kEdsPropID_Evf_OutputDevice, 0);
    canonSleepMs(100);
    _lvActive = false;
    return true;
}

static bool isEvfRetryable(EdsError err) {
    return err == 0x000000A2 ||  // EDS_ERR_OBJECT_NOTREADY
           err == 0x0000A102 ||  // same, as reported by EDSDK 13.20
           err == 0x00000081;    // EDS_ERR_DEVICE_BUSY
}

static bool downloadEvfFrame(
        EdsCameraRef camera,
        EdsEvfImageRef evfImage,
        EdsStreamRef stream,
        std::vector<uint8_t>* result,
        std::function<std::vector<uint8_t>(EdsStreamRef)> toBytes) {
    EdsError err = 0x0000A102;
    for (int i = 0; i < 8; i++) {
        EdsGetEvent();
        err = EdsDownloadEvfImage(camera, evfImage);
        if (err == EDS_ERR_OK) {
            *result = toBytes(stream);
            return true;
        }
        if (!isEvfRetryable(err)) {
            fprintf(stderr, "[canon] EdsDownloadEvfImage: 0x%08X\n", err);
            return false;
        }
        canonSleepMs(50);
    }
    return false;
}

std::vector<uint8_t> CanonCamera::_getPreviewJpegImpl() {
    if (!_camera) return {};
    // Do not re-arm EVF after prepare-still — that made shutter fire in live
    // view and returned a dark, soft JPEG vs the gain-boosted preview.
    if (_stillArmed) return {};
    if (!_lvActive && !_startLiveViewImpl()) return {};

    EdsStreamRef stream = nullptr;
    EdsEvfImageRef evfImage = nullptr;
    std::vector<uint8_t> result;

    if (EdsCreateMemoryStream(0, &stream) != EDS_ERR_OK) return {};
    if (EdsCreateEvfImageRef(stream, &evfImage) != EDS_ERR_OK) {
        EdsRelease(stream);
        return {};
    }

    downloadEvfFrame(
        _camera,
        evfImage,
        stream,
        &result,
        [this](EdsStreamRef s) { return _streamToBytes(s); });

    EdsRelease(evfImage);
    EdsRelease(stream);
    return result;
}
