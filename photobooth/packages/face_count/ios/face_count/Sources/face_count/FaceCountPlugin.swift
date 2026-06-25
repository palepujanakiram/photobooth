import Flutter
import UIKit
import Vision

public class FaceCountPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.photobooth/face_count",
            binaryMessenger: registrar.messenger()
        )
        let instance = FaceCountPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "detectFaceCount" else {
            result(FlutterMethodNotImplemented)
            return
        }

        guard let path = call.arguments as? String, !path.isEmpty else {
            result(0)
            return
        }

        result(Self.detectFaceCount(imagePath: path))
    }

    private static func detectFaceCount(imagePath: String) -> Int {
        guard let uiImage = UIImage(contentsOfFile: imagePath),
              let cgImage = uiImage.cgImage else {
            return 0
        }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            return request.results?.count ?? 0
        } catch {
            return 0
        }
    }
}
