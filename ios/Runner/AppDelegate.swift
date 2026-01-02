import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialize Flutter plugins first
    GeneratedPluginRegistrant.register(with: self)
    
    // Register consolidated camera device helper
    // This handles both device discovery and camera control
    // registrar(forPlugin:) creates a new registrar if one doesn't exist for the plugin name
    if let cameraRegistrar = self.registrar(forPlugin: "CameraDeviceHelper") {
      CameraDeviceHelper.register(with: cameraRegistrar)
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
