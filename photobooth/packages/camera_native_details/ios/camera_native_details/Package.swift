// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "camera_native_details",
  platforms: [
    .iOS("26.0"),
  ],
  products: [
    .library(name: "camera-native-details", targets: ["camera_native_details"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "camera_native_details",
      dependencies: [],
      path: "Sources/camera_native_details"
    ),
  ]
)
