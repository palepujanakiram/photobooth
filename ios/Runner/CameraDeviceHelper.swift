import Flutter
import AVFoundation
import UIKit

// MARK: - Camera Device Helper
// Consolidated camera helper that handles both device discovery and camera control
class CameraDeviceHelper: NSObject, FlutterPlugin, FlutterTexture, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
  private var methodChannel: FlutterMethodChannel?
  private var observers: [NSObjectProtocol] = []
  private let registrar: FlutterPluginRegistrar
  
  // MARK: - Camera Control Properties
  private var captureSession: AVCaptureSession?
  private var photoOutput: AVCapturePhotoOutput?
  private var videoDataOutput: AVCaptureVideoDataOutput?
  private var textureId: Int64 = -1
  private var latestPixelBuffer: CVPixelBuffer?
  private var rotationCoordinator: Any? // Type-erased for safety
  private var rotationObservation: NSKeyValueObservation?
  private var pendingPhotoResult: FlutterResult?
  
  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
  }
  
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.photobooth/camera_device",
      binaryMessenger: registrar.messenger()
    )
    let instance = CameraDeviceHelper(registrar: registrar)
    instance.methodChannel = channel
    instance.setupCameraObservers()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }
  
  deinit {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
  }
  
  // MARK: - Camera Connection Observers
  
  private func setupCameraObservers() {
    let connectObserver = NotificationCenter.default.addObserver(
      forName: .AVCaptureDeviceWasConnected,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      if let device = notification.object as? AVCaptureDevice {
        print("🔌 Camera CONNECTED: \(device.localizedName) - \(device.uniqueID)")
        self?.notifyCameraChange(event: "connected", device: device)
      }
    }
    
    let disconnectObserver = NotificationCenter.default.addObserver(
      forName: .AVCaptureDeviceWasDisconnected,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      if let device = notification.object as? AVCaptureDevice {
        print("🔌 Camera DISCONNECTED: \(device.localizedName) - \(device.uniqueID)")
        self?.notifyCameraChange(event: "disconnected", device: device)
      }
    }
    
    observers = [connectObserver, disconnectObserver]
  }
  
  private func notifyCameraChange(event: String, device: AVCaptureDevice) {
    let eventData: [String: Any] = [
      "event": event,
      "uniqueID": device.uniqueID,
      "localizedName": device.localizedName
    ]
    
    methodChannel?.invokeMethod("onCameraChange", arguments: eventData)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initializeCameraByDeviceId":
      guard let args = call.arguments as? [String: Any],
            let deviceId = args["deviceId"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
        return
      }
      initializeCameraByDeviceId(deviceId: deviceId, result: result)
      
    case "getCameraDeviceId":
      guard let args = call.arguments as? [String: Any],
            let cameraName = args["cameraName"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
        return
      }
      getCameraDeviceId(cameraName: cameraName, result: result)
      
    case "getAllAvailableCameras":
      getAllAvailableCameras(result: result)
      
    case "testExternalCameras":
      testExternalCameras(result: result)
      
    case "requestCameraPermission":
      requestCameraPermission(result: result)
      
    // MARK: - Camera Control Methods
    case "initializeCamera":
      guard let args = call.arguments as? [String: Any],
            let deviceId = args["deviceId"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
        return
      }
      initializeCameraControl(deviceId: deviceId, result: result)
      
    case "startPreview":
      startPreview(result: result)
      
    case "takePicture":
      takePicture(result: result)
      
    case "disposeCamera":
      disposeCamera(result: result)
      
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  // MARK: - FlutterTexture Protocol
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let pixelBuffer = latestPixelBuffer else { return nil }
    return Unmanaged.passRetained(pixelBuffer)
  }
  
  // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    self.latestPixelBuffer = pixelBuffer
    if textureId != -1 {
      self.registrar.textures().textureFrameAvailable(self.textureId)
    }
  }
  
  // MARK: - AVCapturePhotoCaptureDelegate
  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
    if let error = error {
      pendingPhotoResult?(FlutterError(code: "PHOTO_ERROR", message: error.localizedDescription, details: nil))
      pendingPhotoResult = nil
      return
    }
    
    guard let imageData = photo.fileDataRepresentation() else {
      pendingPhotoResult?(FlutterError(code: "PHOTO_ERROR", message: "Failed to get image data", details: nil))
      pendingPhotoResult = nil
      return
    }
    
    // Save to temporary directory
    let tempDir = FileManager.default.temporaryDirectory
    let fileName = "photo_\(UUID().uuidString).jpg"
    let fileURL = tempDir.appendingPathComponent(fileName)
    
    do {
      try imageData.write(to: fileURL)
      pendingPhotoResult?(["success": true, "path": fileURL.path])
    } catch {
      pendingPhotoResult?(FlutterError(code: "PHOTO_ERROR", message: error.localizedDescription, details: nil))
    }
    
    pendingPhotoResult = nil
  }
  
  // MARK: - Permission Handling
  
  private func requestCameraPermission(result: @escaping FlutterResult) {
    let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
    
    switch authStatus {
    case .authorized:
      result(["status": "authorized"])
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
          result(["status": granted ? "authorized" : "denied"])
        }
      }
    case .denied:
      result(["status": "denied"])
    case .restricted:
      result(["status": "restricted"])
    @unknown default:
      result(["status": "unknown"])
    }
  }
  
  private func checkCameraPermission(completion: @escaping (Bool) -> Void) {
    let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
    
    switch authStatus {
    case .authorized:
      completion(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
          completion(granted)
        }
      }
    default:
      completion(false)
    }
  }
  
  // MARK: - Helper Methods
  
  /// Creates a discovery session for all available camera devices
  /// Includes both built-in and external cameras (iOS 17.0+ deployment target)
  private func createDiscoverySession() -> AVCaptureDevice.DiscoverySession {
    let deviceTypes: [AVCaptureDevice.DeviceType] = [
      .builtInWideAngleCamera,
      .external
    ]
    
    return AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes,
      mediaType: .video,
      position: .unspecified
    )
  }
  
  /// Checks if a device is connected (iOS 13.0+)
  private func isDeviceConnected(_ device: AVCaptureDevice) -> Bool {
    if #available(iOS 13.0, *) {
      return device.isConnected
    }
    return true // Assume connected on older iOS
  }
  
  /// Extracts device ID from uniqueID (e.g., ":8" -> "8")
  private func extractDeviceId(from uniqueID: String) -> String {
    guard uniqueID.contains(":") else { return "" }
    return uniqueID.components(separatedBy: ":").last ?? ""
  }
  
  /// Creates a camera info dictionary for Flutter
  /// Returns only essential fields: uniqueID and localizedName
  private func createCameraInfo(
    device: AVCaptureDevice,
    deviceId: String,
    isExternal: Bool,
    fallbackName: String
  ) -> [String: Any] {
    let localizedName = device.localizedName.isEmpty ? fallbackName : device.localizedName
    
    return [
      "uniqueID": device.uniqueID,
      "localizedName": localizedName
    ]
  }
  
  /// Logs detailed information about a camera device
  ///
  /// Shows all relevant properties including:
  /// - deviceType: The type of device (iOS 10.2+)
  ///   - .external: Explicitly marks external cameras (iOS 17.0+)
  ///   - .builtIn*: Various built-in camera types
  /// - uniqueID: Device identifier (used for heuristics on older iOS)
  /// - isConnected: Whether device is currently connected (iOS 13.0+)
  /// - position: Camera position (back, front, unspecified)
  private func logDeviceDetails(_ device: AVCaptureDevice, index: Int) {
    print("")
    print("Camera #\(index):")
    
    let rawLocalizedName = device.localizedName
    let localizedName = rawLocalizedName.isEmpty ? "(No name)" : rawLocalizedName
    print("  📷 Localized Name: \(localizedName)")
    if rawLocalizedName.isEmpty {
      print("     ⚠️  WARNING: localizedName is empty!")
    }
    
    print("  🆔 Unique ID: \(device.uniqueID)")
    print("  🏷️  Model ID: \(device.modelID)")
    print("  📍 Position: \(device.position.rawValue)")
    
    // Show device type with external detection info
    let isExternal = device.deviceType == .external
    print("  🔧 Device Type: \(isExternal ? "External" : "Built-in")")
    
    print("  ✅ Connected: \(isDeviceConnected(device))")
    
    if #available(iOS 13.0, *) {
      print("  ⏸️  Suspended: \(device.isSuspended)")
    }
    
    print("  💡 Has Flash: \(device.hasFlash)")
    print("  🔦 Has Torch: \(device.hasTorch)")
    print("  🏠 Is Built-in: \(!isExternal)")
    print("  🔌 Is External: \(isExternal)")
    
    if #available(iOS 13.0, *) {
      print("  📐 Active Format: \(device.activeFormat.description)")
    }
    
    print(String(repeating: "-", count: 78))
  }
  
  // MARK: - Public Methods
  
  private func initializeCameraByDeviceId(deviceId: String, result: @escaping FlutterResult) {
    print("🔍 Looking for camera with device ID: \(deviceId)")
    
    checkCameraPermission { [weak self] granted in
      guard let self = self else { return }
      
      if !granted {
        result(FlutterError(
          code: "PERMISSION_DENIED",
          message: "Camera permission not granted",
          details: nil
        ))
        return
      }
      
      let discoverySession = self.createDiscoverySession()
      
      print("🔍 Found \(discoverySession.devices.count) devices in discovery session")
      
      // Log all devices for debugging
      for device in discoverySession.devices {
        print("   - Device uniqueID: \(device.uniqueID), localizedName: \(device.localizedName)")
      }
      
      // Find device by matching the device ID in the uniqueID
      var foundDevice: AVCaptureDevice?
      for device in discoverySession.devices {
        let deviceUniqueId = device.uniqueID
        // Match by device ID suffix (e.g., ":8")
        if deviceUniqueId.hasSuffix(":\(deviceId)") {
          foundDevice = device
          print("✅ Found device by device ID suffix: \(deviceUniqueId)")
          break
        }
      }
      
      if let device = foundDevice {
        let deviceInfo: [String: Any] = [
          "success": true,
          "deviceId": deviceId,
          "uniqueID": device.uniqueID,
          "localizedName": device.localizedName,
          "position": device.position.rawValue
        ]
        print("✅ Returning device info for device ID: \(deviceId)")
        result(deviceInfo)
      } else {
        print("❌ Device not found for device ID: \(deviceId)")
        result(FlutterError(
          code: "DEVICE_NOT_FOUND",
          message: "Camera device with ID \(deviceId) not found",
          details: nil
        ))
      }
    }
  }
  
  private func getCameraDeviceId(cameraName: String, result: @escaping FlutterResult) {
    checkCameraPermission { [weak self] granted in
      guard let self = self else { return }
      
      if !granted {
        result(FlutterError(
          code: "PERMISSION_DENIED",
          message: "Camera permission not granted",
          details: nil
        ))
        return
      }
      
      // Extract device ID from camera name
      // Format: "com.apple.avfoundation.avcapturedevice.built-in_video:8"
      let deviceId = cameraName.components(separatedBy: ":").last?.components(separatedBy: ",").first ?? ""
      
      print("🔍 Looking for camera with device ID: \(deviceId)")
      print("🔍 Camera name: \(cameraName)")
      
      let discoverySession = self.createDiscoverySession()
      
      print("🔍 Found \(discoverySession.devices.count) devices in discovery session")
      
      // Log all devices for debugging
      var deviceIndex = 0
      for device in discoverySession.devices {
        print("   [\(deviceIndex)] Device uniqueID: \(device.uniqueID), localizedName: \(device.localizedName)")
        deviceIndex += 1
      }
      
      var foundDevice: AVCaptureDevice?
      
      // Strategy 1: Try exact match first (for built-in cameras)
      for device in discoverySession.devices {
        if device.uniqueID == cameraName {
          foundDevice = device
          print("✅ Found device by exact name match: \(device.uniqueID)")
          break
        }
      }
      
      // Strategy 2: If not found, try matching by device ID suffix (for built-in cameras)
      // Built-in cameras have format: "com.apple.avfoundation.avcapturedevice.built-in_video:X"
      if foundDevice == nil {
        for device in discoverySession.devices {
          let deviceUniqueId = device.uniqueID
          if deviceUniqueId.hasSuffix(":\(deviceId)") {
            foundDevice = device
            print("✅ Found device by device ID suffix match: \(deviceUniqueId)")
            break
          }
        }
      }
      
      // Strategy 3: For external cameras, Flutter reports them as "built-in_video:8"
      // but iOS uses UUID format. External cameras have device ID >= 2
      if foundDevice == nil, let deviceIdInt = Int(deviceId), deviceIdInt >= 2 {
        print("🔍 Device ID \(deviceId) is external (>= 2), looking for UUID format device...")
        
        // Find all external cameras
        let externalDevices = discoverySession.devices.filter { $0.deviceType == .external }
        
        print("🔍 Found \(externalDevices.count) external device(s)")
        for (index, device) in externalDevices.enumerated() {
          print("   External [\(index)]: \(device.uniqueID) - \(device.localizedName)")
        }
        
        if externalDevices.count == 1 {
          // Only one external camera - that must be it
          foundDevice = externalDevices.first
          print("✅ Found external device (only one): \(foundDevice!.uniqueID) - \(foundDevice!.localizedName)")
        } else if externalDevices.count > 1 {
          // Multiple external cameras - try to match by index
          // Device ID 8 means it's the 3rd camera (0=back, 1=front, 2+=external)
          // So external index would be deviceId - 2
          let externalIndex = deviceIdInt - 2
          if externalIndex < externalDevices.count {
            foundDevice = externalDevices[externalIndex]
            print("✅ Found external device at index \(externalIndex): \(foundDevice!.uniqueID) - \(foundDevice!.localizedName)")
          } else {
            // Fallback: use the first external camera
            foundDevice = externalDevices.first
            print("⚠️ Using first external device (index out of range): \(foundDevice!.uniqueID) - \(foundDevice!.localizedName)")
          }
        }
      }
      
      if let device = foundDevice {
        let deviceInfo: [String: Any] = [
          "deviceId": deviceId,
          "uniqueID": device.uniqueID,
          "localizedName": device.localizedName,
          "position": device.position.rawValue
        ]
        print("✅ Returning device info for device ID: \(deviceId)")
        print("   Matched device: \(device.uniqueID) -> \(device.localizedName)")
        result(deviceInfo)
      } else {
        print("❌ Device not found for camera name: \(cameraName), device ID: \(deviceId)")
        print("   Available devices:")
        for (index, device) in discoverySession.devices.enumerated() {
          print("     [\(index)] \(device.uniqueID) - \(device.localizedName)")
        }
        result(FlutterError(
          code: "DEVICE_NOT_FOUND",
          message: "Camera device not found: \(cameraName) (device ID: \(deviceId))",
          details: nil
        ))
      }
    }
  }
  
  /// Returns all currently available camera devices
  /// This is used to filter out cameras that aren't actually connected
  private func getAllAvailableCameras(result: @escaping FlutterResult) {
    checkCameraPermission { [weak self] granted in
      guard let self = self else { return }
      
      if !granted {
        result(FlutterError(
          code: "PERMISSION_DENIED",
          message: "Camera permission not granted. Please enable camera access in Settings.",
          details: nil
        ))
        return
      }
      
      self.performGetAllAvailableCameras(result: result)
    }
  }
  
  private func performGetAllAvailableCameras(result: @escaping FlutterResult) {
    let discoverySession = createDiscoverySession()
    
    print("🔍 getAllAvailableCameras: Found \(discoverySession.devices.count) devices")
    print("")
    
    // Log detailed information about ALL devices
    print("📸 DETAILED CAMERA INFORMATION:")
    print(String(repeating: "=", count: 80))
    for (index, device) in discoverySession.devices.enumerated() {
      logDeviceDetails(device, index: index + 1)
    }
    print(String(repeating: "=", count: 80))
    print("")
    
    var cameras: [[String: Any]] = []
    var builtInCount = 0
    var externalCount = 0
    
    // Process all devices in a single loop
    for device in discoverySession.devices {
      let isExternal = device.deviceType == .external
      let deviceId: String
      
      if isExternal {
        // External cameras: device IDs start after built-in cameras
        // Use sequential numbering based on external camera index
        deviceId = String(builtInCount + externalCount)
        externalCount += 1
      } else {
        // Built-in cameras: use device ID from uniqueID (0, 1, etc.)
        deviceId = extractDeviceId(from: device.uniqueID)
        builtInCount += 1
      }
      
      let fallbackName = isExternal ? "External Camera \(deviceId)" : "Camera \(deviceId)"
      let cameraInfo = createCameraInfo(
        device: device,
        deviceId: deviceId,
        isExternal: isExternal,
        fallbackName: fallbackName
      )
      cameras.append(cameraInfo)
      
      let localizedName = cameraInfo["localizedName"] as? String ?? ""
      let statusIcon = "✅"
      let cameraType = isExternal ? "External" : "Built-in"
      
      print("   \(statusIcon) \(cameraType) - Device ID: \(deviceId), uniqueID: \(device.uniqueID), name: \(localizedName)")
    }
    
    print("")
    print("📊 Summary:")
    print("   Built-in cameras: \(builtInCount)")
    print("   External cameras: \(externalCount)")
    print("")
        
    result(cameras)
  }
  
  /// Test method to specifically check external camera detection
  private func testExternalCameras(result: @escaping FlutterResult) {
    checkCameraPermission { [weak self] granted in
      guard let self = self else { return }
      
      if !granted {
        result(FlutterError(
          code: "PERMISSION_DENIED",
          message: "Camera permission not granted",
          details: nil
        ))
        return
      }
      
      print("🔍 Testing External Camera Detection")
      print(String(repeating: "=", count: 80))
      
      let discoverySession = self.createDiscoverySession()
      let allDevices = discoverySession.devices
      let builtInDevices = allDevices.filter { $0.deviceType == .builtInWideAngleCamera }
      let externalDevices = allDevices.filter { $0.deviceType == .external }
      
      print("📊 Device Summary:")
      print("   Total devices: \(allDevices.count)")
      print("   Built-in devices: \(builtInDevices.count)")
      print("   External devices: \(externalDevices.count)")
      print("")
      
      print("🏠 Built-in Cameras:")
      for (index, device) in builtInDevices.enumerated() {
        print("   [\(index)] \(device.localizedName)")
        print("       UniqueID: \(device.uniqueID)")
        print("       Connected: \(self.isDeviceConnected(device))")
      }
      print("")
      
      print("🔌 External Cameras:")
      if externalDevices.isEmpty {
        print("   ❌ No external cameras detected")
        print("")
        print("💡 Troubleshooting tips:")
        print("   1. Check Settings > Privacy & Security > Camera")
        print("   2. Try unplugging and replugging the camera")
        print("   3. Ensure camera works in the built-in Camera app")
        print("   4. Some cameras may require a powered USB hub")
        print("   5. Check iOS version (iOS 17.0+ required for .external)")
      } else {
        for (index, device) in externalDevices.enumerated() {
          print("   ✅ [\(index)] \(device.localizedName)")
          print("       UniqueID: \(device.uniqueID)")
          print("       Connected: \(self.isDeviceConnected(device))")
          print("       ModelID: \(device.modelID)")
          
          if #available(iOS 13.0, *) {
            print("       Suspended: \(device.isSuspended)")
          }
        }
      }
      
      print(String(repeating: "=", count: 80))
      
      let info: [String: Any] = [
        "totalDevices": allDevices.count,
        "builtInDevices": builtInDevices.count,
        "externalDevices": externalDevices.count,
        "externalNames": externalDevices.map { $0.localizedName },
        "externalUniqueIDs": externalDevices.map { $0.uniqueID }
      ]
      
      result(info)
    }
  }
  
  // MARK: - Camera Control Methods
  
  /// Initializes camera control with specific device ID
  /// Returns texture ID for Flutter preview
  private func initializeCameraControl(deviceId: String, result: @escaping FlutterResult) {
    // Clean up any existing session first
    cleanupCameraSession()
    
    // Small delay to ensure previous session is fully released
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      guard let self = self else {
        result(FlutterError(code: "INIT_ERROR", message: "Helper deallocated", details: nil))
        return
      }
      
      guard let device = self.findDeviceForControl(deviceId: deviceId) else {
        result(FlutterError(code: "DEVICE_NOT_FOUND", message: "Device not found", details: nil))
        return
      }
      
      self.performCameraInitialization(device: device, result: result)
    }
  }
  
  /// Performs the actual camera initialization
  private func performCameraInitialization(device: AVCaptureDevice, result: @escaping FlutterResult) {
    // Check if device is available
    guard device.isConnected else {
      result(FlutterError(code: "DEVICE_NOT_CONNECTED", message: "Camera device is not connected", details: nil))
      return
    }
    
    // Register texture to get ID for Flutter
    self.textureId = registrar.textures().register(self)
    
    let session = AVCaptureSession()
    session.beginConfiguration()
    
    // Set session preset
    if session.canSetSessionPreset(.high) {
      session.sessionPreset = .high
    }
    
    do {
      // Input - lock device for configuration
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }
      
      let videoInput = try AVCaptureDeviceInput(device: device)
      guard session.canAddInput(videoInput) else {
        result(FlutterError(code: "INIT_ERROR", message: "Cannot add video input to session", details: nil))
        return
      }
      session.addInput(videoInput)
      
      // Photo Output
      let photoOutput = AVCapturePhotoOutput()
      guard session.canAddOutput(photoOutput) else {
        result(FlutterError(code: "INIT_ERROR", message: "Cannot add photo output to session", details: nil))
        return
      }
      session.addOutput(photoOutput)
      
      // Video Data Output (for Texture Preview)
      let videoOutput = AVCaptureVideoDataOutput()
      videoOutput.alwaysDiscardsLateVideoFrames = true
      videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
      videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
      guard session.canAddOutput(videoOutput) else {
        result(FlutterError(code: "INIT_ERROR", message: "Cannot add video output to session", details: nil))
        return
      }
      session.addOutput(videoOutput)

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
      // Clean up on error
      cleanupCameraSession()
      result(FlutterError(code: "INIT_ERROR", message: error.localizedDescription, details: nil))
    }
  }
  
  /// Applies rotation angle to video and photo connections
  private func applyRotation(angle: CGFloat) {
    if let connection = videoDataOutput?.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
      connection.videoRotationAngle = angle
    }
    if let photoConnection = photoOutput?.connection(with: .video), photoConnection.isVideoRotationAngleSupported(angle) {
      photoConnection.videoRotationAngle = angle
    }
  }
  
  /// Finds device for camera control by device ID
  private func findDeviceForControl(deviceId: String) -> AVCaptureDevice? {
    let discoverySession = createDiscoverySession()
    
    // Try to find by device ID suffix (for built-in cameras)
    for device in discoverySession.devices {
      if device.uniqueID.hasSuffix(":\(deviceId)") {
        return device
      }
    }
    
    // For external cameras, try to match by index
    let builtInCameras = discoverySession.devices.filter { $0.deviceType != .external }
    let externalCameras = discoverySession.devices.filter { $0.deviceType == .external }
    
    if let deviceIdInt = Int(deviceId), deviceIdInt >= builtInCameras.count {
      let externalIndex = deviceIdInt - builtInCameras.count
      if externalIndex < externalCameras.count {
        return externalCameras[externalIndex]
      }
    }
    
    // Fallback: return first device
    return discoverySession.devices.first
  }
  
  /// Starts camera preview
  private func startPreview(result: @escaping FlutterResult) {
    guard let session = captureSession else {
      result(FlutterError(code: "NOT_INITIALIZED", message: "Camera not initialized", details: nil))
      return
    }
    
    DispatchQueue.global(qos: .userInitiated).async {
      session.startRunning()
      DispatchQueue.main.async { result(["success": true]) }
    }
  }
  
  /// Takes a picture
  private func takePicture(result: @escaping FlutterResult) {
    guard let photoOutput = photoOutput else {
      result(FlutterError(code: "NOT_INITIALIZED", message: "Camera not initialized", details: nil))
      return
    }
    
    pendingPhotoResult = result
    let settings = AVCapturePhotoSettings()
    photoOutput.capturePhoto(with: settings, delegate: self)
  }
  
  /// Cleans up camera session
  private func cleanupCameraSession() {
    // Stop session first
    if let session = captureSession {
      if session.isRunning {
        session.stopRunning()
      }
      // Remove all inputs and outputs
      session.beginConfiguration()
      for input in session.inputs {
        session.removeInput(input)
      }
      for output in session.outputs {
        session.removeOutput(output)
      }
      session.commitConfiguration()
    }
    
    // Unregister texture
    if textureId != -1 {
      registrar.textures().unregisterTexture(textureId)
      textureId = -1
    }
    
    // Clean up observations
    rotationObservation?.invalidate()
    rotationObservation = nil
    
    // Clear all references
    captureSession = nil
    photoOutput = nil
    videoDataOutput = nil
    latestPixelBuffer = nil
    rotationCoordinator = nil
    pendingPhotoResult = nil
  }
  
  /// Disposes camera control
  private func disposeCamera(result: @escaping FlutterResult) {
    cleanupCameraSession()
    result(["success": true])
  }
}

