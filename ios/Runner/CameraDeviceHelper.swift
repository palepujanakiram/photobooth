import Flutter
import AVFoundation

class CameraDeviceHelper: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.photobooth/camera_device",
      binaryMessenger: registrar.messenger()
    )
    let instance = CameraDeviceHelper()
    registrar.addMethodCallDelegate(instance, channel: channel)
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
      
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  private func initializeCameraByDeviceId(deviceId: String, result: @escaping FlutterResult) {
    print("🔍 Looking for camera with device ID: \(deviceId)")
    
    // Use all available device types including external
    var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
    if #available(iOS 17.0, *) {
      deviceTypes.append(.external)
    }
    
    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes,
      mediaType: .video,
      position: .unspecified
    )
    
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
        "modelID": device.modelID,
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
  
  private func getCameraDeviceId(cameraName: String, result: @escaping FlutterResult) {
    // Extract device ID from camera name
    // Format: "com.apple.avfoundation.avcapturedevice.built-in_video:8"
    let deviceId = cameraName.components(separatedBy: ":").last?.components(separatedBy: ",").first ?? ""
    
    print("🔍 Looking for camera with device ID: \(deviceId)")
    print("🔍 Camera name: \(cameraName)")
    
    // Use all available device types including external
    var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
    if #available(iOS 17.0, *) {
      deviceTypes.append(.external)
    }
    
    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes,
      mediaType: .video,
      position: .unspecified
    )
    
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
      
      // Find all external cameras (UUID format or not matching built-in pattern)
      let externalDevices = discoverySession.devices.filter { device in
        let uid = device.uniqueID
        // External cameras have UUID format (contains dashes) or don't match built-in pattern
        return uid.contains("-") || !uid.contains("built-in")
      }
      
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
        "modelID": device.modelID,
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

