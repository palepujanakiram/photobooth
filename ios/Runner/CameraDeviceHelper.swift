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
  private var captureTimeoutTimer: Timer?
  
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
    if handleDeviceDiscoveryMethod(call, result: result) { return }
    if handleCameraControlMethod(call, result: result) { return }
    result(FlutterMethodNotImplemented)
  }
  
  private func handleDeviceDiscoveryMethod(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool {
    switch call.method {
    case "initializeCameraByDeviceId":
      handleInitializeCameraByDeviceId(call: call, result: result)
      return true
    case "getCameraDeviceId":
      handleGetCameraDeviceId(call: call, result: result)
      return true
    case "getAllAvailableCameras":
      getAllAvailableCameras(result: result)
      return true
    case "testExternalCameras":
      testExternalCameras(result: result)
      return true
    case "requestCameraPermission":
      requestCameraPermission(result: result)
      return true
    default:
      return false
    }
  }
  
  private func handleCameraControlMethod(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool {
    switch call.method {
    case "initializeCamera":
      handleInitializeCamera(call: call, result: result)
      return true
    case "startPreview":
      startPreview(result: result)
      return true
    case "takePicture":
      takePicture(result: result)
      return true
    case "disposeCamera":
      disposeCamera(result: result)
      return true
    default:
      return false
    }
  }
  
  // MARK: - Method Call Handlers
  
  private func handleInitializeCameraByDeviceId(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let deviceId = args["deviceId"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
      return
    }
    initializeCameraByDeviceId(deviceId: deviceId, result: result)
  }
  
  private func handleGetCameraDeviceId(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let cameraName = args["cameraName"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
      return
    }
    getCameraDeviceId(cameraName: cameraName, result: result)
  }
  
  private func handleInitializeCamera(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let deviceId = args["deviceId"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
      return
    }
    initializeCameraControl(deviceId: deviceId, result: result)
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
    print("📸 photoOutput delegate called")
    
    // Cancel timeout since we received the callback
    captureTimeoutTimer?.invalidate()
    captureTimeoutTimer = nil
    print("   ✅ Cancelled capture timeout")
    
    if let error = error {
      print("❌ Photo capture error: \(error.localizedDescription)")
      pendingPhotoResult?(FlutterError(code: "PHOTO_ERROR", message: error.localizedDescription, details: nil))
      pendingPhotoResult = nil
      return
    }
    
    guard let imageData = photo.fileDataRepresentation() else {
      print("❌ Failed to get image data representation")
      pendingPhotoResult?(FlutterError(code: "PHOTO_ERROR", message: "Failed to get image data", details: nil))
      pendingPhotoResult = nil
      return
    }
    
    print("   Processing photo data (\(imageData.count) bytes)...")
    savePhotoToFile(imageData: imageData)
  }
  
  private func savePhotoToFile(imageData: Data) {
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
    handleAuthorizationStatus(authStatus, result: result)
  }
  
  private func handleAuthorizationStatus(_ status: AVAuthorizationStatus, result: @escaping FlutterResult) {
    switch status {
    case .authorized:
      result(["status": "authorized"])
    case .notDetermined:
      requestCameraAccess(result: result)
    case .denied:
      result(["status": "denied"])
    case .restricted:
      result(["status": "restricted"])
    @unknown default:
      result(["status": "unknown"])
    }
  }
  
  private func requestCameraAccess(result: @escaping FlutterResult) {
    AVCaptureDevice.requestAccess(for: .video) { granted in
      DispatchQueue.main.async {
        result(["status": granted ? "authorized" : "denied"])
      }
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
    return true
  }
  
  /// Extracts device ID from uniqueID (e.g., ":8" -> "8")
  private func extractDeviceId(from uniqueID: String) -> String {
    guard uniqueID.contains(":") else { return "" }
    return uniqueID.components(separatedBy: ":").last ?? ""
  }
  
  /// Creates a camera info dictionary for Flutter
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
  private func logDeviceDetails(_ device: AVCaptureDevice, index: Int) {
    print("")
    print("Camera #\(index):")
    logDeviceName(device)
    logDeviceIdentifiers(device)
    logDeviceType(device)
    logDeviceState(device)
    logDeviceCapabilities(device)
    print(String(repeating: "-", count: 78))
  }
  
  private func logDeviceName(_ device: AVCaptureDevice) {
    let rawLocalizedName = device.localizedName
    let localizedName = rawLocalizedName.isEmpty ? "(No name)" : rawLocalizedName
    print("  📷 Localized Name: \(localizedName)")
    if rawLocalizedName.isEmpty {
      print("     ⚠️  WARNING: localizedName is empty!")
    }
  }
  
  private func logDeviceIdentifiers(_ device: AVCaptureDevice) {
    print("  🆔 Unique ID: \(device.uniqueID)")
    print("  🏷️  Model ID: \(device.modelID)")
    print("  📍 Position: \(device.position.rawValue)")
  }
  
  private func logDeviceType(_ device: AVCaptureDevice) {
    let isExternal = device.deviceType == .external
    print("  🔧 Device Type: \(isExternal ? "External" : "Built-in")")
  }
  
  private func logDeviceState(_ device: AVCaptureDevice) {
    print("  ✅ Connected: \(isDeviceConnected(device))")
    if #available(iOS 13.0, *) {
      print("  ⏸️  Suspended: \(device.isSuspended)")
    }
  }
  
  private func logDeviceCapabilities(_ device: AVCaptureDevice) {
    let isExternal = device.deviceType == .external
    print("  💡 Has Flash: \(device.hasFlash)")
    print("  🔦 Has Torch: \(device.hasTorch)")
    print("  🏠 Is Built-in: \(!isExternal)")
    print("  🔌 Is External: \(isExternal)")
    
    if #available(iOS 13.0, *) {
      print("  📐 Active Format: \(device.activeFormat.description)")
    }
  }
  
  // MARK: - Device Discovery Methods
  
  private func initializeCameraByDeviceId(deviceId: String, result: @escaping FlutterResult) {
    print("🔍 Looking for camera with device ID: \(deviceId)")
    
    checkCameraPermission { [weak self] granted in
      guard let self = self else { return }
      
      guard granted else {
        self.handlePermissionDenied(result: result)
        return
      }
      
      self.findAndReturnDevice(deviceId: deviceId, result: result)
    }
  }
  
  private func handlePermissionDenied(result: @escaping FlutterResult) {
    result(FlutterError(
      code: "PERMISSION_DENIED",
      message: "Camera permission not granted",
      details: nil
    ))
  }
  
  private func findAndReturnDevice(deviceId: String, result: @escaping FlutterResult) {
    let discoverySession = createDiscoverySession()
    print("🔍 Found \(discoverySession.devices.count) devices in discovery session")
    
    logAllDevices(discoverySession.devices)
    
    guard let device = findDeviceByDeviceId(deviceId, in: discoverySession.devices) else {
      handleDeviceNotFound(deviceId: deviceId, result: result)
      return
    }
    
    returnDeviceInfo(device: device, deviceId: deviceId, result: result)
  }
  
  private func logAllDevices(_ devices: [AVCaptureDevice]) {
    for device in devices {
      print("   - Device uniqueID: \(device.uniqueID), localizedName: \(device.localizedName)")
    }
  }
  
  private func findDeviceByDeviceId(_ deviceId: String, in devices: [AVCaptureDevice]) -> AVCaptureDevice? {
    if let device = devices.first(where: { $0.uniqueID.hasSuffix(":\(deviceId)") }) {
      print("✅ Found device by device ID suffix: \(device.uniqueID)")
      return device
    }
    return nil
  }
  
  private func handleDeviceNotFound(deviceId: String, result: @escaping FlutterResult) {
    print("❌ Device not found for device ID: \(deviceId)")
    result(FlutterError(
      code: "DEVICE_NOT_FOUND",
      message: "Camera device with ID \(deviceId) not found",
      details: nil
    ))
  }
  
  private func returnDeviceInfo(device: AVCaptureDevice, deviceId: String, result: @escaping FlutterResult) {
    let deviceInfo: [String: Any] = [
      "success": true,
      "deviceId": deviceId,
      "uniqueID": device.uniqueID,
      "localizedName": device.localizedName,
      "position": device.position.rawValue
    ]
    print("✅ Returning device info for device ID: \(deviceId)")
    result(deviceInfo)
  }
  
  private func getCameraDeviceId(cameraName: String, result: @escaping FlutterResult) {
    checkCameraPermission { [weak self] granted in
      guard let self = self else { return }
      
      guard granted else {
        self.handlePermissionDenied(result: result)
        return
      }
      
      self.findDeviceByCameraName(cameraName: cameraName, result: result)
    }
  }
  
  private func findDeviceByCameraName(cameraName: String, result: @escaping FlutterResult) {
    let deviceId = extractDeviceIdFromCameraName(cameraName)
    print("🔍 Looking for camera with device ID: \(deviceId)")
    print("🔍 Camera name: \(cameraName)")
    
    let discoverySession = createDiscoverySession()
    logDiscoverySessionDevices(discoverySession)
    
    guard let device = searchForDevice(cameraName: cameraName, deviceId: deviceId, discoverySession: discoverySession) else {
      handleCameraNotFound(cameraName: cameraName, deviceId: deviceId, discoverySession: discoverySession, result: result)
      return
    }
    
    returnCameraDeviceInfo(device: device, deviceId: deviceId, result: result)
  }
  
  private func extractDeviceIdFromCameraName(_ cameraName: String) -> String {
    return cameraName.components(separatedBy: ":").last?.components(separatedBy: ",").first ?? ""
  }
  
  private func logDiscoverySessionDevices(_ discoverySession: AVCaptureDevice.DiscoverySession) {
    print("🔍 Found \(discoverySession.devices.count) devices in discovery session")
    for (index, device) in discoverySession.devices.enumerated() {
      print("   [\(index)] Device uniqueID: \(device.uniqueID), localizedName: \(device.localizedName)")
    }
  }
  
  private func searchForDevice(cameraName: String, deviceId: String, discoverySession: AVCaptureDevice.DiscoverySession) -> AVCaptureDevice? {
    let searchStrategies: [(String, () -> AVCaptureDevice?)] = [
      ("exact name match", { self.findDeviceByExactName(cameraName, in: discoverySession.devices) }),
      ("device ID suffix match", { self.findDeviceByDeviceIdSuffix(deviceId, in: discoverySession.devices) }),
      ("external camera match", { self.findExternalDevice(deviceId: deviceId, discoverySession: discoverySession) })
    ]
    
    for (strategyName, strategy) in searchStrategies {
      if let device = strategy() {
        print("✅ Found device using \(strategyName)")
        return device
      }
    }
    
    return nil
  }
  
  private func findDeviceByExactName(_ cameraName: String, in devices: [AVCaptureDevice]) -> AVCaptureDevice? {
    return devices.first { $0.uniqueID == cameraName }
  }
  
  private func findDeviceByDeviceIdSuffix(_ deviceId: String, in devices: [AVCaptureDevice]) -> AVCaptureDevice? {
    return devices.first { $0.uniqueID.hasSuffix(":\(deviceId)") }
  }
  
  private func findExternalDevice(deviceId: String, discoverySession: AVCaptureDevice.DiscoverySession) -> AVCaptureDevice? {
    guard let deviceIdInt = Int(deviceId), deviceIdInt >= 2 else {
      return nil
    }
    
    print("🔍 Device ID \(deviceId) is external (>= 2), looking for UUID format device...")
    let externalDevices = discoverySession.devices.filter { $0.deviceType == .external }
    
    logExternalDevices(externalDevices)
    return selectExternalDevice(externalDevices: externalDevices, deviceIdInt: deviceIdInt)
  }
  
  private func logExternalDevices(_ externalDevices: [AVCaptureDevice]) {
    print("🔍 Found \(externalDevices.count) external device(s)")
    for (index, device) in externalDevices.enumerated() {
      print("   External [\(index)]: \(device.uniqueID) - \(device.localizedName)")
    }
  }
  
  private func selectExternalDevice(externalDevices: [AVCaptureDevice], deviceIdInt: Int) -> AVCaptureDevice? {
    guard !externalDevices.isEmpty else { return nil }
    
    if externalDevices.count == 1 {
      print("✅ Found external device (only one): \(externalDevices[0].uniqueID) - \(externalDevices[0].localizedName)")
      return externalDevices.first
    }
    
    return selectFromMultipleExternalDevices(externalDevices: externalDevices, deviceIdInt: deviceIdInt)
  }
  
  private func selectFromMultipleExternalDevices(externalDevices: [AVCaptureDevice], deviceIdInt: Int) -> AVCaptureDevice? {
    let externalIndex = deviceIdInt - 2
    
    if externalIndex < externalDevices.count {
      let device = externalDevices[externalIndex]
      print("✅ Found external device at index \(externalIndex): \(device.uniqueID) - \(device.localizedName)")
      return device
    }
    
    // Fallback: use the first external camera
    let device = externalDevices.first!
    print("⚠️ Using first external device (index out of range): \(device.uniqueID) - \(device.localizedName)")
    return device
  }
  
  private func handleCameraNotFound(cameraName: String, deviceId: String, discoverySession: AVCaptureDevice.DiscoverySession, result: @escaping FlutterResult) {
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
  
  private func returnCameraDeviceInfo(device: AVCaptureDevice, deviceId: String, result: @escaping FlutterResult) {
    let deviceInfo: [String: Any] = [
      "deviceId": deviceId,
      "uniqueID": device.uniqueID,
      "localizedName": device.localizedName,
      "position": device.position.rawValue
    ]
    print("✅ Returning device info for device ID: \(deviceId)")
    print("   Matched device: \(device.uniqueID) -> \(device.localizedName)")
    result(deviceInfo)
  }
  
  /// Returns all currently available camera devices
  private func getAllAvailableCameras(result: @escaping FlutterResult) {
    checkCameraPermission { [weak self] granted in
      guard let self = self else { return }
      
      guard granted else {
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
    
    logDetailedCameraInfo(discoverySession.devices)
    
    let cameras = buildCameraList(from: discoverySession.devices)
    printCameraSummary(cameras: cameras, devices: discoverySession.devices)
    
    result(cameras)
  }
  
  private func logDetailedCameraInfo(_ devices: [AVCaptureDevice]) {
    print("📸 DETAILED CAMERA INFORMATION:")
    print(String(repeating: "=", count: 80))
    for (index, device) in devices.enumerated() {
      logDeviceDetails(device, index: index + 1)
    }
    print(String(repeating: "=", count: 80))
    print("")
  }
  
  private func buildCameraList(from devices: [AVCaptureDevice]) -> [[String: Any]] {
    var cameras: [[String: Any]] = []
    var builtInCount = 0
    var externalCount = 0
    
    for device in devices {
      let isExternal = device.deviceType == .external
      let deviceId = calculateDeviceId(isExternal: isExternal, builtInCount: builtInCount, externalCount: externalCount, device: device)
      
      if isExternal {
        externalCount += 1
      } else {
        builtInCount += 1
      }
      
      let cameraInfo = buildCameraInfo(device: device, deviceId: deviceId, isExternal: isExternal)
      cameras.append(cameraInfo)
      
      logCameraInfo(cameraInfo: cameraInfo, device: device, isExternal: isExternal, deviceId: deviceId)
    }
    
    return cameras
  }
  
  private func calculateDeviceId(isExternal: Bool, builtInCount: Int, externalCount: Int, device: AVCaptureDevice) -> String {
    if isExternal {
      return String(builtInCount + externalCount)
    } else {
      return extractDeviceId(from: device.uniqueID)
    }
  }
  
  private func buildCameraInfo(device: AVCaptureDevice, deviceId: String, isExternal: Bool) -> [String: Any] {
    let fallbackName = isExternal ? "External Camera \(deviceId)" : "Camera \(deviceId)"
    return createCameraInfo(
      device: device,
      deviceId: deviceId,
      isExternal: isExternal,
      fallbackName: fallbackName
    )
  }
  
  private func logCameraInfo(cameraInfo: [String: Any], device: AVCaptureDevice, isExternal: Bool, deviceId: String) {
    let localizedName = cameraInfo["localizedName"] as? String ?? ""
    let cameraType = isExternal ? "External" : "Built-in"
    print("   ✅ \(cameraType) - Device ID: \(deviceId), uniqueID: \(device.uniqueID), name: \(localizedName)")
  }
  
  private func printCameraSummary(cameras: [[String: Any]], devices: [AVCaptureDevice]) {
    let builtInCount = devices.filter { $0.deviceType != .external }.count
    let externalCount = devices.filter { $0.deviceType == .external }.count
    
    print("")
    print("📊 Summary:")
    print("   Built-in cameras: \(builtInCount)")
    print("   External cameras: \(externalCount)")
    print("")
  }
  
  /// Test method to specifically check external camera detection
  private func testExternalCameras(result: @escaping FlutterResult) {
    checkCameraPermission { [weak self] granted in
      guard let self = self else { return }
      
      guard granted else {
        self.handlePermissionDenied(result: result)
        return
      }
      
      self.performExternalCameraTest(result: result)
    }
  }
  
  private func performExternalCameraTest(result: @escaping FlutterResult) {
    print("🔍 Testing External Camera Detection")
    print(String(repeating: "=", count: 80))
    
    let discoverySession = createDiscoverySession()
    let categorizedDevices = categorizeDevices(discoverySession.devices)
    
    printDeviceSummary(categorizedDevices: categorizedDevices)
    logBuiltInCameras(categorizedDevices.builtIn)
    logExternalCamerasForTest(categorizedDevices.external)
    
    print(String(repeating: "=", count: 80))
    
    let info = buildExternalCameraTestInfo(categorizedDevices: categorizedDevices)
    result(info)
  }
  
  private typealias CategorizedDevices = (all: [AVCaptureDevice], builtIn: [AVCaptureDevice], external: [AVCaptureDevice])
  
  private func categorizeDevices(_ devices: [AVCaptureDevice]) -> CategorizedDevices {
    let builtIn = devices.filter { $0.deviceType == .builtInWideAngleCamera }
    let external = devices.filter { $0.deviceType == .external }
    return (devices, builtIn, external)
  }
  
  private func printDeviceSummary(categorizedDevices: CategorizedDevices) {
    print("📊 Device Summary:")
    print("   Total devices: \(categorizedDevices.all.count)")
    print("   Built-in devices: \(categorizedDevices.builtIn.count)")
    print("   External devices: \(categorizedDevices.external.count)")
    print("")
  }
  
  private func logBuiltInCameras(_ devices: [AVCaptureDevice]) {
    print("🏠 Built-in Cameras:")
    for (index, device) in devices.enumerated() {
      print("   [\(index)] \(device.localizedName)")
      print("       UniqueID: \(device.uniqueID)")
      print("       Connected: \(isDeviceConnected(device))")
    }
    print("")
  }
  
  private func logExternalCamerasForTest(_ devices: [AVCaptureDevice]) {
    print("🔌 External Cameras:")
    if devices.isEmpty {
      printExternalCameraTroubleshooting()
    } else {
      for (index, device) in devices.enumerated() {
        logExternalCameraDetails(device: device, index: index)
      }
    }
  }
  
  private func printExternalCameraTroubleshooting() {
    print("   ❌ No external cameras detected")
    print("")
    print("💡 Troubleshooting tips:")
    print("   1. Check Settings > Privacy & Security > Camera")
    print("   2. Try unplugging and replugging the camera")
    print("   3. Ensure camera works in the built-in Camera app")
    print("   4. Some cameras may require a powered USB hub")
    print("   5. Check iOS version (iOS 17.0+ required for .external)")
  }
  
  private func logExternalCameraDetails(device: AVCaptureDevice, index: Int) {
    print("   ✅ [\(index)] \(device.localizedName)")
    print("       UniqueID: \(device.uniqueID)")
    print("       Connected: \(isDeviceConnected(device))")
    print("       ModelID: \(device.modelID)")
    
    if #available(iOS 13.0, *) {
      print("       Suspended: \(device.isSuspended)")
    }
  }
  
  private func buildExternalCameraTestInfo(categorizedDevices: CategorizedDevices) -> [String: Any] {
    return [
      "totalDevices": categorizedDevices.all.count,
      "builtInDevices": categorizedDevices.builtIn.count,
      "externalDevices": categorizedDevices.external.count,
      "externalNames": categorizedDevices.external.map { $0.localizedName },
      "externalUniqueIDs": categorizedDevices.external.map { $0.uniqueID }
    ]
  }
  
  // MARK: - Camera Control Methods
  
  /// Initializes camera control with specific device ID
  private func initializeCameraControl(deviceId: String, result: @escaping FlutterResult) {
    cleanupCameraSession()
    
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
    guard device.isConnected else {
      result(FlutterError(code: "DEVICE_NOT_CONNECTED", message: "Camera device is not connected", details: nil))
      return
    }
    
    self.textureId = registrar.textures().register(self)
    
    let session = AVCaptureSession()
    session.beginConfiguration()
    
    if session.canSetSessionPreset(.high) {
      session.sessionPreset = .high
    }
    
    do {
      try configureCameraSession(session: session, device: device, result: result)
    } catch {
      cleanupCameraSession()
      result(FlutterError(code: "INIT_ERROR", message: error.localizedDescription, details: nil))
    }
  }
  
  private func configureCameraSession(session: AVCaptureSession, device: AVCaptureDevice, result: @escaping FlutterResult) throws {
    try device.lockForConfiguration()
    defer { device.unlockForConfiguration() }
    
    try addVideoInput(to: session, device: device, result: result)
    try addPhotoOutput(to: session, result: result)
    try addVideoDataOutput(to: session, result: result)
    
    session.commitConfiguration()
    
    self.captureSession = session
    configureConnections(device: device)
    
    result(["success": true, "textureId": self.textureId])
  }
  
  private func addVideoInput(to session: AVCaptureSession, device: AVCaptureDevice, result: @escaping FlutterResult) throws {
    let videoInput = try AVCaptureDeviceInput(device: device)
    guard session.canAddInput(videoInput) else {
      throw NSError(domain: "CameraError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input to session"])
    }
    session.addInput(videoInput)
  }
  
  private func addPhotoOutput(to session: AVCaptureSession, result: @escaping FlutterResult) throws {
    let photoOutput = AVCapturePhotoOutput()
    guard session.canAddOutput(photoOutput) else {
      throw NSError(domain: "CameraError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add photo output to session"])
    }
    session.addOutput(photoOutput)
    self.photoOutput = photoOutput
  }
  
  private func addVideoDataOutput(to session: AVCaptureSession, result: @escaping FlutterResult) throws {
    let videoOutput = AVCaptureVideoDataOutput()
    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
    
    guard session.canAddOutput(videoOutput) else {
      throw NSError(domain: "CameraError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot add video output to session"])
    }
    session.addOutput(videoOutput)
    self.videoDataOutput = videoOutput
  }
  
  /// Configures video and photo connections to match orientation
  private func configureConnections(device: AVCaptureDevice) {
    let videoOrientation = getVideoOrientation()
    
    configureVideoConnection(device: device, videoOrientation: videoOrientation)
    configurePhotoConnection(videoOrientation: videoOrientation)
    setupRotationCoordination(device: device)
    
    logConnectionConfiguration(device: device, videoOrientation: videoOrientation)
  }
  
  private func getVideoOrientation() -> AVCaptureVideoOrientation {
    let deviceOrientation = UIDevice.current.orientation
    
    switch deviceOrientation {
    case .portrait:
      return .portrait
    case .portraitUpsideDown:
      return .portraitUpsideDown
    case .landscapeLeft:
      return .landscapeRight
    case .landscapeRight:
      return .landscapeLeft
    default:
      return .portrait
    }
  }
  
  private func configureVideoConnection(device: AVCaptureDevice, videoOrientation: AVCaptureVideoOrientation) {
    guard let videoConnection = videoDataOutput?.connection(with: .video) else { return }
    
    if videoConnection.isVideoOrientationSupported {
      videoConnection.videoOrientation = videoOrientation
    }
    
    videoConnection.isVideoMirrored = false
  }
  
  private func configurePhotoConnection(videoOrientation: AVCaptureVideoOrientation) {
    guard let photoConnection = photoOutput?.connection(with: .video) else { return }
    
    if photoConnection.isVideoOrientationSupported {
      photoConnection.videoOrientation = videoOrientation
    }
    
    photoConnection.isVideoMirrored = false
  }
  
  private func setupRotationCoordination(device: AVCaptureDevice) {
    guard #available(iOS 17.0, *) else { return }
    
    let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
    self.rotationCoordinator = coordinator
    
    setupRotationObserver(coordinator: coordinator)
    applyInitialRotation(coordinator: coordinator)
  }
  
  @available(iOS 17.0, *)
  private func setupRotationObserver(coordinator: AVCaptureDevice.RotationCoordinator) {
    rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { [weak self] coord, change in
      guard let self = self, let angle = change.newValue else { return }
      self.applyRotationAngle(angle)
    }
  }
  
  @available(iOS 17.0, *)
  private func applyInitialRotation(coordinator: AVCaptureDevice.RotationCoordinator) {
    let initialAngle = coordinator.videoRotationAngleForHorizonLevelPreview
    applyRotationAngle(initialAngle)
  }
  
  private func applyRotationAngle(_ angle: CGFloat) {
    if let videoConnection = videoDataOutput?.connection(with: .video),
       videoConnection.isVideoRotationAngleSupported(angle) {
      videoConnection.videoRotationAngle = angle
    }
    
    if let photoConnection = photoOutput?.connection(with: .video),
       photoConnection.isVideoRotationAngleSupported(angle) {
      photoConnection.videoRotationAngle = angle
    }
  }
  
  private func logConnectionConfiguration(device: AVCaptureDevice, videoOrientation: AVCaptureVideoOrientation) {
    let previewMirrored = device.position == .front
    print("📸 Configured connections:")
    print("   Video orientation: \(videoOrientation.rawValue)")
    print("   Preview mirrored: \(previewMirrored) (for user comfort)")
    print("   Photo mirrored: false (actual scene orientation)")
  }
  
  /// Finds device for camera control by device ID
  private func findDeviceForControl(deviceId: String) -> AVCaptureDevice? {
    let discoverySession = createDiscoverySession()
    
    // Try to find by device ID suffix (for built-in cameras)
    if let device = findBuiltInDevice(deviceId: deviceId, in: discoverySession.devices) {
      return device
    }
    
    // For external cameras, try to match by index
    return findExternalDeviceForControl(deviceId: deviceId, discoverySession: discoverySession)
  }
  
  private func findBuiltInDevice(deviceId: String, in devices: [AVCaptureDevice]) -> AVCaptureDevice? {
    return devices.first { $0.uniqueID.hasSuffix(":\(deviceId)") }
  }
  
  private func findExternalDeviceForControl(deviceId: String, discoverySession: AVCaptureDevice.DiscoverySession) -> AVCaptureDevice? {
    let builtInCameras = discoverySession.devices.filter { $0.deviceType != .external }
    let externalCameras = discoverySession.devices.filter { $0.deviceType == .external }
    
    guard let deviceIdInt = Int(deviceId), deviceIdInt >= builtInCameras.count else {
      return discoverySession.devices.first
    }
    
    let externalIndex = deviceIdInt - builtInCameras.count
    if externalIndex < externalCameras.count {
      return externalCameras[externalIndex]
    }
    
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
    print("📸 takePicture() called")
    print("   photoOutput: \(photoOutput != nil ? "exists" : "nil")")
    print("   captureSession: \(captureSession != nil ? "exists" : "nil")")
    
    guard let photoOutput = photoOutput else {
      print("❌ Error: photoOutput is nil")
      result(FlutterError(code: "NOT_INITIALIZED", message: "Camera not initialized - photoOutput is nil", details: nil))
      return
    }
    
    guard let session = captureSession, session.isRunning else {
      print("❌ Error: captureSession is not running")
      result(FlutterError(code: "NOT_INITIALIZED", message: "Camera session not running", details: nil))
      return
    }
    
    print("📸 Capturing photo...")
    pendingPhotoResult = result
    
    // Set up timeout (8 seconds) - if photo delegate is not called, return error
    captureTimeoutTimer?.invalidate()
    captureTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
      guard let self = self else { return }
      
      print("❌ TIMEOUT: Photo capture timed out after 8 seconds")
      print("   Photo delegate was never called")
      print("   This may indicate the camera doesn't support photo capture properly")
      
      if let pendingResult = self.pendingPhotoResult {
        pendingResult(FlutterError(
          code: "CAPTURE_TIMEOUT",
          message: "Photo capture timed out after 8 seconds. The camera may not support still image capture or is not responding.",
          details: nil
        ))
        self.pendingPhotoResult = nil
      }
      
      self.captureTimeoutTimer = nil
    }
    
    let settings = AVCapturePhotoSettings()
    photoOutput.capturePhoto(with: settings, delegate: self)
    print("✅ capturePhoto called on photoOutput")
    print("   Waiting for photo delegate callback (timeout: 8s)...")
  }
  
  /// Cleans up camera session
  private func cleanupCameraSession() {
    stopAndCleanSession()
    unregisterTexture()
    cleanupObservations()
    clearReferences()
  }
  
  private func stopAndCleanSession() {
    guard let session = captureSession else { return }
    
    if session.isRunning {
      session.stopRunning()
    }
    
    session.beginConfiguration()
    session.inputs.forEach { session.removeInput($0) }
    session.outputs.forEach { session.removeOutput($0) }
    session.commitConfiguration()
  }
  
  private func unregisterTexture() {
    if textureId != -1 {
      registrar.textures().unregisterTexture(textureId)
      textureId = -1
    }
  }
  
  private func cleanupObservations() {
    rotationObservation?.invalidate()
    rotationObservation = nil
  }
  
  private func clearReferences() {
    // Cancel any pending capture timeout
    captureTimeoutTimer?.invalidate()
    captureTimeoutTimer = nil
    
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
