#include "canon_camera.h"
#include "httplib.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <string>
#include <thread>

using namespace std::chrono_literals;

static CanonCamera g_camera;
static std::atomic<bool> g_shuttingDown{false};

static void cameraInitLoop() {
    while (!g_shuttingDown.load()) {
        if (!g_camera.isConnected()) {
            fprintf(stderr, "[sidecar] attempting camera init...\n");
            g_camera.init();
        }
        std::this_thread::sleep_for(5s);
    }
}

static void jsonOk(httplib::Response& res, const char* body) {
    res.set_content(body, "application/json");
}

static void jpegOk(httplib::Response& res, const std::vector<uint8_t>& jpeg) {
    res.set_content(
        reinterpret_cast<const char*>(jpeg.data()),
        jpeg.size(),
        "image/jpeg");
}

static void err503(httplib::Response& res, const char* msg) {
    res.status = 503;
    res.set_content(
        std::string("{\"error\":\"") + msg + "\"}",
        "application/json");
}

static bool requireCamera(httplib::Response& res) {
    if (g_camera.isConnected()) {
        return true;
    }
    err503(res, "camera not connected");
    return false;
}

static void handleHealth(const httplib::Request&, httplib::Response& res) {
    jsonOk(
        res,
        g_camera.isConnected() ? R"({"ok":true,"connected":true})"
                               : R"({"ok":false,"connected":false})");
}

static void handleLiveView(const httplib::Request&, httplib::Response& res) {
    if (!requireCamera(res)) {
        return;
    }
    jsonOk(
        res,
        g_camera.startLiveView()
            ? R"({"enabled":true,"woke":true,"holding":true})"
            : R"({"enabled":false,"woke":false,"holding":false})");
}

static void handlePreview(const httplib::Request&, httplib::Response& res) {
    if (!requireCamera(res)) {
        return;
    }
    auto jpeg = g_camera.getPreviewJpeg();
    if (jpeg.empty()) {
        err503(res, "no frame");
        return;
    }
    jpegOk(res, jpeg);
}

static void handlePrepareStill(const httplib::Request&, httplib::Response& res) {
    if (!requireCamera(res)) {
        return;
    }
    g_camera.prepareStill();
    res.status = 200;
    res.set_content("", "text/plain");
}

static void handleCapture(const httplib::Request&, httplib::Response& res) {
    if (!requireCamera(res)) {
        return;
    }
    auto jpeg = g_camera.capture(30);
    if (jpeg.empty()) {
        err503(res, "capture failed");
        return;
    }
    jpegOk(res, jpeg);
}

static void handleClientLog(const httplib::Request&, httplib::Response& res) {
    res.status = 200;
    res.set_content("", "text/plain");
}

static void registerRoutes(httplib::Server& svr) {
    svr.Get("/health", handleHealth);
    svr.Post("/camera/live-view", handleLiveView);
    svr.Post("/camera/preview", handlePreview);
    svr.Get("/camera/preview", handlePreview);
    svr.Post("/camera/prepare-still", handlePrepareStill);
    svr.Post("/camera/capture", handleCapture);
    svr.Post("/camera/client-log", handleClientLog);
}

int main() {
    fprintf(stderr, "[sidecar] Canon EDSDK sidecar v1.0 starting\n");

    httplib::Server svr;
    svr.new_task_queue = [] { return new httplib::ThreadPool(4); };
    registerRoutes(svr);

    std::thread initThread(cameraInitLoop);

    const int port = 8791;
    fprintf(stderr, "[sidecar] listening on 127.0.0.1:%d\n", port);
    svr.listen("127.0.0.1", port);

    g_shuttingDown = true;
    initThread.join();
    g_camera.shutdown();
    return 0;
}
