import Flutter
import AVFoundation
import UIKit

class CustomCameraController: NSObject, FlutterPlugin, FlutterTexture, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // MARK: - Properties
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.photobooth/custom_camera",
            binaryMessenger: registrar.messenger()
        )
        let instance = CustomCameraController(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    private let registrar: FlutterPluginRegistrar
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    
    // Texture and Frame properties
    private var textureId: Int64 = -1
    private var latestPixelBuffer: CVPixelBuffer?
    
    // Rotation properties (iOS 17+)
    private var rotationCoordinator: Any? // Type-erased for safety
    private var rotationObservation: NSKeyValueObservation?
    
    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
        setupNotifications() // Listen for plug/unplug events
    }

    // MARK: - FlutterTexture Protocol
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let pixelBuffer = latestPixelBuffer else { return nil }
        return Unmanaged.passRetained(pixelBuffer)
    }

    // MARK: - Method Channel Handler
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initializeCamera":
            guard let args = call.arguments as? [String: Any],
                  let deviceId = args["deviceId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
                return
            }
            initializeCamera(deviceId: deviceId, result: result)
            
        case "startPreview":
            startPreview(result: result)
            
        case "takePicture":
            takePicture(result: result)
            
        case "dispose":
            dispose(result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Camera Logic
    private func initializeCamera(deviceId: String, result: @escaping FlutterResult) {
        cleanupSession()
        
        guard let device = findDeviceById(deviceId: deviceId) else {
            result(FlutterError(code: "DEVICE_NOT_FOUND", message: "Device not found", details: nil))
            return
        }

        // Register texture to get ID for Flutter
        self.textureId = registrar.textures().register(self)
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        
        do {
            // Input
            let videoInput = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(videoInput) { session.addInput(videoInput) }
            
            // Photo Output
            let photoOutput = AVCapturePhotoOutput()
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            
            // Video Data Output (for Texture Preview)
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

            session.commitConfiguration()
            
            self.captureSession = session
            self.photoOutput = photoOutput
            self.videoDataOutput = videoOutput
            
            // Setup Rotation Coordination (iOS 17+)
            if #available(iOS 17.0, *) {
                let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
                self.rotationCoordinator = coordinator
                rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { [weak self] coord, change in
                    if let angle = change.newValue { self?.applyRotation(angle: angle) }
                }
                applyRotation(angle: coordinator.videoRotationAngleForHorizonLevelPreview)
            }
            
            result(["success": true, "textureId": self.textureId])
        } catch {
            result(FlutterError(code: "INIT_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func applyRotation(angle: CGFloat) {
        if let connection = videoDataOutput?.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        if let photoConnection = photoOutput?.connection(with: .video), photoConnection.isVideoRotationAngleSupported(angle) {
            photoConnection.videoRotationAngle = angle
        }
    }

    // MARK: - Delegates
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        self.latestPixelBuffer = pixelBuffer
        self.registrar.textures().textureFrameAvailable(self.textureId)
    }

    // MARK: - Hot-Plugging
    private func setupNotifications() {
        NotificationCenter.default.addObserver(forName: .AVCaptureDeviceWasConnected, object: nil, queue: .main) { [weak self] _ in
            // Logic to notify Flutter to re-scan devices
            print("Device Connected")
        }
        NotificationCenter.default.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: nil, queue: .main) { [weak self] _ in
            print("Device Disconnected")
            self?.cleanupSession()
        }
    }

    private func findDeviceById(deviceId: String) -> AVCaptureDevice? {
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.external, .builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        return session.devices.first { $0.uniqueID.contains(deviceId) } ?? session.devices.first
    }

    private func startPreview(result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.startRunning()
            DispatchQueue.main.async { result(["success": true]) }
        }
    }

    private func takePicture(result: @escaping FlutterResult) {
        let settings = AVCapturePhotoSettings()
        photoOutput?.capturePhoto(with: settings, delegate: self)
        // Store result to call back later
    }

    private func cleanupSession() {
        captureSession?.stopRunning()
        if textureId != -1 {
            registrar.textures().unregisterTexture(textureId)
            textureId = -1
        }
        rotationObservation?.invalidate()
    }
    
    private func dispose(result: FlutterResult?) {
        cleanupSession()
        result?(["success": true])
    }
}
