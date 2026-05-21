import Flutter
import UIKit

public class CameraNativeDetailsPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.photobooth/camera_native_details",
            binaryMessenger: registrar.messenger()
        )
        let instance = CameraNativeDetailsPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "getCameraDetails" {
            // iOS: return default values for now; real implementation can be added later.
            result(defaultDetailsMap())
        } else {
            result(FlutterMethodNotImplemented)
        }
    }

    private func defaultDetailsMap() -> [String: Any?] {
        return [
            "activeArrayWidth": nil,
            "activeArrayHeight": nil,
            "zoomRatioRangeMin": nil,
            "zoomRatioRangeMax": nil,
            "maxDigitalZoom": nil,
            "supportedPreviewSizes": [] as [String],
            "supportedCaptureSizes": [] as [String],
            "lensFacing": nil,
            "platform": "ios",
        ]
    }
}
