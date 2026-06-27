import Flutter
import UIKit
import Darwin.Mach
import os

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerDeviceMemoryChannel(with: engineBridge.applicationRegistrar.messenger())
  }

  private func registerDeviceMemoryChannel(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "photobooth/device_memory",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "getMemoryInfo" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(Self.readMemoryInfo())
    }
  }

  private static func readMemoryInfo() -> [String: Any] {
    var processRssBytes: Int? = nil
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
    )
    let kerr = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    if kerr == KERN_SUCCESS {
      processRssBytes = Int(info.resident_size)
    }

    let totalBytes = Int(ProcessInfo.processInfo.physicalMemory)
    var availableBytes: Int? = nil
    if #available(iOS 13.0, *) {
      let available = os_proc_available_memory()
      if available > 0 {
        availableBytes = Int(available)
      }
    }

    var payload: [String: Any] = [
      "totalBytes": totalBytes,
      "lowMemory": false,
    ]
    if let processRssBytes {
      payload["processRssBytes"] = processRssBytes
    }
    if let availableBytes {
      payload["availableBytes"] = availableBytes
    }
    return payload
  }
}
