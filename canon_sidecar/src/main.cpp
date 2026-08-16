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

// Retry camera init in background so /health reports the real state
// without blocking the HTTP server from starting.
static void cameraInitLoop() {
    while (!g_shuttingDown.load()) {
        if (!g_camera.isConnected()) {
            fprintf(stderr, "[sidecar] attempting camera init...\n");
            g_camera.init();
        }
        std::this_thread::sleep_for(5s);
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

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

// ── Entry point ───────────────────────────────────────────────────────────────

int main() {
    fprintf(stderr, "[sidecar] Canon EDSDK sidecar v1.0 starting\n");

    // Start the HTTP server before camera init so health checks can start.
    httplib::Server svr;
    svr.new_task_queue = [] { return new httplib::ThreadPool(4); };

    // GET /health
    svr.Get("/health", [](const httplib::Request&, httplib::Response& res) {
        bool ok = g_camera.isConnected();
        jsonOk(res,
            ok ? R"({"ok":true,"connected":true})"
               : R"({"ok":false,"connected":false})");
    });

    // POST /camera/live-view
    svr.Post("/camera/live-view",
        [](const httplib::Request&, httplib::Response& res) {
        if (!g_camera.isConnected()) {
            err503(res, "camera not connected");
            return;
        }
        bool ok = g_camera.startLiveView();
        jsonOk(res,
            ok ? R"({"enabled":true,"woke":true,"holding":true})"
               : R"({"enabled":false,"woke":false,"holding":false})");
    });

    auto handlePreview = [](const httplib::Request&, httplib::Response& res) {
        if (!g_camera.isConnected()) { err503(res, "camera not connected"); return; }
        auto jpeg = g_camera.getPreviewJpeg();
        if (jpeg.empty()) { err503(res, "no frame"); return; }
        jpegOk(res, jpeg);
    };
    svr.Post("/camera/preview", handlePreview);
    svr.Get("/camera/preview", handlePreview);

    // POST /camera/prepare-still
    svr.Post("/camera/prepare-still",
        [](const httplib::Request&, httplib::Response& res) {
        if (!g_camera.isConnected()) { err503(res, "camera not connected"); return; }
        g_camera.prepareStill();
        res.status = 200;
        res.set_content("", "text/plain");
    });

    // POST /camera/capture?download=1
    svr.Post("/camera/capture",
        [](const httplib::Request&, httplib::Response& res) {
        if (!g_camera.isConnected()) { err503(res, "camera not connected"); return; }
        auto jpeg = g_camera.capture(30);
        if (jpeg.empty()) { err503(res, "capture failed"); return; }
        jpegOk(res, jpeg);
    });

    // POST /camera/client-log  — best-effort breadcrumb, no action needed
    svr.Post("/camera/client-log",
        [](const httplib::Request&, httplib::Response& res) {
        res.status = 200;
        res.set_content("", "text/plain");
    });

    // Background thread retries camera init every 5 s until connected.
    std::thread initThread(cameraInitLoop);

    const int port = 8791;
    fprintf(stderr, "[sidecar] listening on 127.0.0.1:%d\n", port);
    svr.listen("127.0.0.1", port);

    g_shuttingDown = true;
    initThread.join();
    g_camera.shutdown();
    return 0;
}
