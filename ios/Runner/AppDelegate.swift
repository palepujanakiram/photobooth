import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register camera device helper for device ID selection
    CameraDeviceHelper.register(with: registrar(forPlugin: "CameraDeviceHelper")!)
    
    // Register custom camera controller
    CustomCameraController.register(with: registrar(forPlugin: "CustomCameraController")!)
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
