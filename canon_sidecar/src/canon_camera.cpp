#include "canon_camera.h"

#include <cstdio>

using namespace std::chrono_literals;

CanonCamera::CanonCamera() = default;

CanonCamera::~CanonCamera() { shutdown(); }

bool CanonCamera::init() {
    if (!_running.load()) {
        _running = true;
        _edsdkThread = std::thread(&CanonCamera::_edsdkLoop, this);
    }
    if (_connected.load()) return true;
    return _dispatch([this] { return _initImpl(); });
}

void CanonCamera::shutdown() {
    if (!_running.load()) return;
    _dispatch([this] { _shutdownImpl(); });
    _running = false;
    _taskReady.notify_all();
    if (_edsdkThread.joinable()) _edsdkThread.join();
}

bool CanonCamera::startLiveView() {
    return _dispatch([this] { return _startLiveViewImpl(); });
}

bool CanonCamera::stopLiveView() {
    return _dispatch([this] { return _stopLiveViewImpl(); });
}

std::vector<uint8_t> CanonCamera::getPreviewJpeg() {
    return _dispatch([this] { return _getPreviewJpegImpl(); });
}

void CanonCamera::prepareStill() {
    _dispatch([this] { _prepareStillImpl(); });
}

std::vector<uint8_t> CanonCamera::capture(int timeoutSeconds) {
    return _dispatch([this, timeoutSeconds] {
        return _captureImpl(timeoutSeconds);
    });
}

void CanonCamera::_edsdkLoop() {
    while (_running.load()) {
        std::function<void()> task;
        {
            std::unique_lock<std::mutex> lk(_taskMutex);
            _taskReady.wait_for(lk, 10ms,
                [this] { return !_tasks.empty() || !_running.load(); });
            if (!_tasks.empty()) {
                task = std::move(_tasks.front());
                _tasks.pop_front();
            }
        }
        if (task) {
            task();
        } else {
            EdsGetEvent();
        }
    }
}

bool CanonCamera::_ensureSdkInitialised() {
    if (_sdkInitialised) return true;
    EdsError err = EdsInitializeSDK();
    if (err != EDS_ERR_OK) {
        fprintf(stderr, "[canon] EdsInitializeSDK: 0x%08X\n", err);
        return false;
    }
    _sdkInitialised = true;
    canonSleepMs(200);  // USB fd is already open via the Android hook
    return true;
}

bool CanonCamera::_openFirstCamera() {
    EdsCameraListRef list = nullptr;
    EdsError err = EdsGetCameraList(&list);
    if (err != EDS_ERR_OK || !list) {
        fprintf(stderr, "[canon] EdsGetCameraList: 0x%08X\n", err);
        return false;
    }

    EdsUInt32 count = 0;
    EdsGetChildCount(list, &count);
    if (count == 0) {
        EdsRelease(list);
        fprintf(stderr, "[canon] no camera found\n");
        // Drop the SDK so the next attempt re-enumerates USB from scratch.
        // EDSDK can cache an empty list across GetCameraList retries.
        if (_sdkInitialised) {
            EdsTerminateSDK();
            _sdkInitialised = false;
        }
        return false;
    }

    err = EdsGetChildAtIndex(list, 0, &_camera);
    EdsRelease(list);
    if (err != EDS_ERR_OK || !_camera) {
        fprintf(stderr, "[canon] EdsGetChildAtIndex: 0x%08X\n", err);
        return false;
    }

    err = EdsOpenSession(_camera);
    if (err != EDS_ERR_OK) {
        fprintf(stderr, "[canon] EdsOpenSession: 0x%08X\n", err);
        EdsRelease(_camera);
        _camera = nullptr;
        return false;
    }
    return true;
}

bool CanonCamera::_initImpl() {
    if (_connected.load()) return true;
    if (!_ensureSdkInitialised()) return false;
    if (!_openFirstCamera()) return false;

    EdsSetObjectEventHandler(_camera, kEdsObjectEvent_All, _onObject, this);
    EdsSetCameraStateEventHandler(_camera, kEdsStateEvent_All, _onState, this);

    // Route captured images directly to host (no SD card write).
    EdsUInt32 saveTo = kEdsSaveTo_Host;
    EdsSetPropertyData(_camera, kEdsPropID_SaveTo, 0, sizeof(saveTo), &saveTo);
    _setHostCapacity();
    _preferHostJpeg();

    _connected = true;
    fprintf(stderr, "[canon] camera ready\n");
    if (_startLiveViewImpl()) {
        fprintf(stderr, "[canon] live view armed\n");
    }
    return true;
}

void CanonCamera::_shutdownImpl() {
    _cancelPendingTransfers();
    if (_lvActive) _stopLiveViewImpl();
    if (_camera) {
        EdsCloseSession(_camera);
        EdsRelease(_camera);
        _camera = nullptr;
    }
    _connected = false;
    if (_sdkInitialised) {
        EdsTerminateSDK();
        _sdkInitialised = false;
    }
}

bool CanonCamera::_setProp(EdsPropertyID id, EdsUInt32 value) {
    return EdsSetPropertyData(_camera, id, 0, sizeof(value), &value)
           == EDS_ERR_OK;
}

std::vector<uint8_t> CanonCamera::_streamToBytes(EdsStreamRef stream) {
    EdsUInt64 length = 0;
    EdsGetLength(stream, &length);
    if (length == 0) return {};

    EdsVoid* ptr = nullptr;
    EdsGetPointer(stream, &ptr);
    if (!ptr) return {};

    auto* b = reinterpret_cast<const uint8_t*>(ptr);
    return {b, b + static_cast<size_t>(length)};
}

void CanonCamera::_setHostCapacity() {
    EdsCapacity cap{};
    cap.numberOfFreeClusters = 0x7FFFFFFF;
    cap.bytesPerSector       = 512;
    cap.reset                = true;
    EdsSetCapacity(_camera, cap);
}

void CanonCamera::_preferHostJpeg() {
    EdsUInt32 quality = static_cast<EdsUInt32>(EdsImageQuality_LJF);
    if (EdsSetPropertyData(
            _camera, kEdsPropID_ImageQuality, 0, sizeof(quality), &quality)
        == EDS_ERR_OK) {
        fprintf(stderr, "[canon] ImageQuality = JPEG Large Fine\n");
        return;
    }
    quality = static_cast<EdsUInt32>(EdsImageQuality_LJ);
    if (EdsSetPropertyData(
            _camera, kEdsPropID_ImageQuality, 0, sizeof(quality), &quality)
        == EDS_ERR_OK) {
        fprintf(stderr, "[canon] ImageQuality = JPEG Large\n");
        return;
    }
    fprintf(stderr, "[canon] ImageQuality JPEG set failed; will skip RAW\n");
}

void CanonCamera::_cancelPendingTransfers() {
    while (!_pendingItems.empty()) {
        auto item = _pendingItems.front();
        _pendingItems.pop_front();
        if (!item) continue;
        EdsDownloadCancel(item);
        EdsRelease(item);
    }
}

static bool isHostTransferEvent(EdsObjectEvent event) {
    return event == kEdsObjectEvent_DirItemRequestTransfer ||
           event == kEdsObjectEvent_DirItemRequestTransferDT ||
           event == kEdsObjectEvent_DirItemCreated;
}

EdsError EDSCALLBACK CanonCamera::_onObject(
        EdsObjectEvent event, EdsBaseRef ref, EdsVoid* ctx) {
    auto* cam = reinterpret_cast<CanonCamera*>(ctx);

    if (isHostTransferEvent(event) && ref) {
        cam->_pendingItems.push_back(static_cast<EdsDirectoryItemRef>(ref));
        // ref ownership transferred — do not release here.
    } else if (ref) {
        EdsRelease(ref);
    }
    return EDS_ERR_OK;
}

EdsError EDSCALLBACK CanonCamera::_onState(
        EdsStateEvent event, EdsUInt32 /*param*/, EdsVoid* ctx) {
    auto* cam = reinterpret_cast<CanonCamera*>(ctx);
    if (event == kEdsStateEvent_Shutdown) {
        fprintf(stderr, "[canon] camera disconnected\n");
        cam->_connected = false;
        cam->_lvActive  = false;
    }
    return EDS_ERR_OK;
}
