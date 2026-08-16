#pragma once

#include "EDSDK.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <functional>
#include <future>
#include <memory>
#include <mutex>
#include <thread>
#include <type_traits>
#include <vector>

inline void canonSleepMs(int ms) {
    std::this_thread::sleep_for(std::chrono::milliseconds(ms));
}

// Owns the EDSDK session and exposes blocking camera operations.
// All EDSDK calls are serialised on a private thread (_edsdkThread).
// Public methods are safe to call from any thread; they block until
// the operation completes or the timeout fires.
class CanonCamera {
public:
    CanonCamera();
    ~CanonCamera();

    // Initialise the SDK, discover the first USB camera, open a session.
    // Returns false if no camera is attached — the caller should retry.
    bool init();

    void shutdown();

    bool isConnected() const { return _connected.load(); }

    // Arms Canon EVF (live view) and routes output to PC.
    bool startLiveView();

    // Stops EVF output to PC (keeps EVF mode on for fast restart).
    bool stopLiveView();

    // Returns a single EVF JPEG frame, or empty on error.
    std::vector<uint8_t> getPreviewJpeg();

    // Stops live view so the mechanical shutter can fire cleanly.
    void prepareStill();

    // Triggers a full shutter cycle, downloads the JPEG, re-arms live view.
    // Blocks until the image arrives or timeoutSeconds elapses.
    std::vector<uint8_t> capture(int timeoutSeconds = 30);

private:
    // ── EDSDK state (only touched on _edsdkThread) ──────────────────────────
    EdsCameraRef _camera       = nullptr;
    bool         _lvActive     = false;  // live-view output routed to PC
    bool         _stillArmed   = false;  // EVF off for a mechanical still
    bool         _sdkInitialised = false;

    // Capture handshake (object-event callback pushes; _captureImpl pops).
    std::deque<EdsDirectoryItemRef> _pendingItems;

    // ── Thread coordination ──────────────────────────────────────────────────
    std::atomic<bool>      _connected{false};
    std::atomic<bool>      _running{false};
    std::thread            _edsdkThread;
    std::deque<std::function<void()>> _tasks;
    std::mutex             _taskMutex;
    std::condition_variable _taskReady;

    // Posts a callable to _edsdkThread and blocks until it returns.
    template <typename F>
    auto _dispatch(F&& f) -> std::invoke_result_t<F>;

    void _edsdkLoop();

    // ── EDSDK operations (run on _edsdkThread only) ──────────────────────────
    bool                 _initImpl();
    bool                 _ensureSdkInitialised();
    bool                 _openFirstCamera();
    void                 _shutdownImpl();
    bool                 _startLiveViewImpl();
    bool                 _stopLiveViewImpl();
    std::vector<uint8_t> _getPreviewJpegImpl();
    void                 _prepareStillImpl();
    std::vector<uint8_t> _captureImpl(int timeoutSeconds);
    bool                 _pressShutter();
    std::vector<uint8_t> _waitForJpeg(int timeoutSeconds);
    void                 _drainTrailingTransfers();
    void                 _restoreLiveViewAfterStill();

    bool _setProp(EdsPropertyID id, EdsUInt32 value);
    std::vector<uint8_t> _streamToBytes(EdsStreamRef stream);
    void _setHostCapacity();
    void _preferHostJpeg();
    void _cancelPendingTransfers();
    std::vector<uint8_t> _downloadJpegOrCancel(EdsDirectoryItemRef item);
    std::vector<uint8_t> _downloadItemBytes(
        EdsDirectoryItemRef item, EdsUInt64 size);

    // ── EDSDK callbacks (static, called from EdsGetEvent on _edsdkThread) ───
    static EdsError EDSCALLBACK _onObject(
        EdsObjectEvent event, EdsBaseRef ref, EdsVoid* ctx);
    static EdsError EDSCALLBACK _onState(
        EdsStateEvent event, EdsUInt32 param, EdsVoid* ctx);
};

// ── Template implementation ──────────────────────────────────────────────────

template <typename F>
auto CanonCamera::_dispatch(F&& f) -> std::invoke_result_t<F> {
    using R = std::invoke_result_t<F>;
    auto promise = std::make_shared<std::promise<R>>();
    auto future  = promise->get_future();
    {
        std::lock_guard<std::mutex> lk(_taskMutex);
        _tasks.push_back([fn = std::forward<F>(f), p = promise]() mutable {
            if constexpr (std::is_void_v<R>) {
                fn();
                p->set_value();
            } else {
                p->set_value(fn());
            }
        });
    }
    _taskReady.notify_one();
    return future.get();
}
