#include "canon_camera.h"

#include <chrono>
#include <cstdio>
#include <thread>

using namespace std::chrono_literals;

// ── Helpers ──────────────────────────────────────────────────────────────────

static void sleepMs(int ms) {
    std::this_thread::sleep_for(std::chrono::milliseconds(ms));
}

// ── Lifecycle ─────────────────────────────────────────────────────────────────

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

// ── Public API (any thread) ───────────────────────────────────────────────────

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

// ── EDSDK thread loop ─────────────────────────────────────────────────────────

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

// ── EDSDK operations (called on _edsdkThread only) ───────────────────────────

bool CanonCamera::_initImpl() {
    if (_connected.load()) return true;

    if (!_sdkInitialised) {
        EdsError err = EdsInitializeSDK();
        if (err != EDS_ERR_OK) {
            fprintf(stderr, "[canon] EdsInitializeSDK: 0x%08X\n", err);
            return false;
        }
        _sdkInitialised = true;
        sleepMs(200);  // USB fd is already open via the Android hook
    }

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

bool CanonCamera::_startLiveViewImpl() {
    if (_lvActive) return true;
    if (!_camera) return false;

    if (!_setProp(kEdsPropID_Evf_Mode, 1)) {
        fprintf(stderr, "[canon] set Evf_Mode failed\n");
        return false;
    }
    sleepMs(100);
    if (!_setProp(kEdsPropID_Evf_OutputDevice, kEdsEvfOutputDevice_PC)) {
        fprintf(stderr, "[canon] set Evf_OutputDevice failed\n");
        return false;
    }
    sleepMs(150);
    _lvActive = true;
    return true;
}

bool CanonCamera::_stopLiveViewImpl() {
    if (!_lvActive || !_camera) return true;
    _setProp(kEdsPropID_Evf_OutputDevice, 0);
    sleepMs(100);
    _lvActive = false;
    return true;
}

// EVF often returns OBJECT_NOTREADY / DEVICE_BUSY until the first frame.
static bool isEvfRetryable(EdsError err) {
    return err == 0x000000A2 ||  // EDS_ERR_OBJECT_NOTREADY
           err == 0x0000A102 ||  // same, as reported by EDSDK 13.20
           err == 0x00000081;    // EDS_ERR_DEVICE_BUSY
}

std::vector<uint8_t> CanonCamera::_getPreviewJpegImpl() {
    if (!_camera) return {};
    // Do not re-arm EVF after prepare-still — that made shutter fire in live
    // view and returned a dark, soft JPEG vs the gain-boosted preview.
    if (_stillArmed) return {};
    if (!_lvActive && !_startLiveViewImpl()) return {};

    EdsStreamRef    stream   = nullptr;
    EdsEvfImageRef  evfImage = nullptr;
    std::vector<uint8_t> result;

    if (EdsCreateMemoryStream(0, &stream) != EDS_ERR_OK) return {};
    if (EdsCreateEvfImageRef(stream, &evfImage) != EDS_ERR_OK) {
        EdsRelease(stream);
        return {};
    }

    EdsError err = 0x0000A102;
    // Fail fast: a 2s retry loop froze pose mid-countdown while shutter still
    // grabbed a later EVF frame.
    for (int i = 0; i < 8; i++) {
        EdsGetEvent();
        err = EdsDownloadEvfImage(_camera, evfImage);
        if (err == EDS_ERR_OK) {
            result = _streamToBytes(stream);
            break;
        }
        if (!isEvfRetryable(err)) {
            fprintf(stderr, "[canon] EdsDownloadEvfImage: 0x%08X\n", err);
            break;
        }
        sleepMs(50);
    }

    EdsRelease(evfImage);
    EdsRelease(stream);
    return result;
}

void CanonCamera::_prepareStillImpl() {
    _stillArmed = true;
    _stopLiveViewImpl();
    sleepMs(500);
}

std::vector<uint8_t> CanonCamera::_captureImpl(int timeoutSeconds) {
    if (!_camera) return {};

    _cancelPendingTransfers();

    _stillArmed = true;
    if (_lvActive) {
        _stopLiveViewImpl();
        sleepMs(600);
    }

    EdsSendCommand(_camera, kEdsCameraCommand_PressShutterButton,
                   kEdsCameraCommand_ShutterButton_OFF);
    sleepMs(50);
    EdsError err = EdsSendCommand(
        _camera,
        kEdsCameraCommand_PressShutterButton,
        kEdsCameraCommand_ShutterButton_Halfway);
    if (err != EDS_ERR_OK) {
        fprintf(stderr, "[canon] shutter halfway: 0x%08X\n", err);
    }
    sleepMs(400);
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
        _stillArmed = false;
        _startLiveViewImpl();
        return {};
    }
    sleepMs(200);
    EdsSendCommand(_camera, kEdsCameraCommand_PressShutterButton,
                   kEdsCameraCommand_ShutterButton_OFF);

    // RAW+JPEG bodies transfer RAW first. Skip non-JPEG and wait for JPEG.
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
        if (result.empty()) sleepMs(20);
    }

    if (result.empty()) {
        fprintf(stderr, "[canon] capture timeout (no JPEG still)\n");
        _cancelPendingTransfers();
        _stillArmed = false;
        _startLiveViewImpl();
        return {};
    }

    // Cancel a trailing RAW/HEIF transfer so the camera does not stall.
    auto drainUntil = std::chrono::steady_clock::now()
                      + std::chrono::milliseconds(800);
    while (std::chrono::steady_clock::now() < drainUntil) {
        EdsGetEvent();
        _cancelPendingTransfers();
        sleepMs(20);
    }

    _stillArmed = false;
    _startLiveViewImpl();
    return result;
}

// ── Utility (called on _edsdkThread) ─────────────────────────────────────────

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

    EdsStreamRef stream = nullptr;
    if (EdsCreateMemoryStream(info.size, &stream) != EDS_ERR_OK) {
        EdsDownloadCancel(item);
        EdsRelease(item);
        return {};
    }
    EdsError dl = EdsDownload(item, info.size, stream);
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

    if (!bytesLookLikeJpeg(result)) {
        fprintf(stderr,
                "[canon] downloaded %zu bytes are not JPEG\n",
                result.size());
        return {};
    }
    fprintf(stderr, "[canon] JPEG still %zu bytes\n", result.size());
    return result;
}

// ── EDSDK callbacks ───────────────────────────────────────────────────────────

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
