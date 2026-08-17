import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

@immutable
class UvcCameraDevice extends Equatable {
  final String name;
  final int deviceClass;
  final int deviceSubclass;
  final int vendorId;
  final int productId;

  /// USB interface classes from the native descriptor.
  ///
  /// Empty when the plugin did not send them (unit tests / older native).
  /// HID-only class-0 dongles look like webcams at the device class, so Dart
  /// uses this list to reject them.
  final List<int> interfaceClasses;

  const UvcCameraDevice({
    required this.name,
    required this.deviceClass,
    required this.deviceSubclass,
    required this.vendorId,
    required this.productId,
    this.interfaceClasses = const [],
  });

  factory UvcCameraDevice.fromMap(Map<dynamic, dynamic> map) {
    return UvcCameraDevice(
      name: map['name'] as String,
      deviceClass: map['deviceClass'] as int,
      deviceSubclass: map['deviceSubclass'] as int,
      vendorId: map['vendorId'] as int,
      productId: map['productId'] as int,
      interfaceClasses: interfaceClassesFromMap(map),
    );
  }

  /// Parses optional `interfaceClasses` from a platform-channel map.
  static List<int> interfaceClassesFromMap(Map<dynamic, dynamic> map) {
    final raw = map['interfaceClasses'];
    if (raw is! List) return const <int>[];
    final classes = <int>[];
    for (final value in raw) {
      if (value is int) {
        classes.add(value);
      } else if (value is num) {
        classes.add(value.toInt());
      }
    }
    return classes;
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'deviceClass': deviceClass,
      'deviceSubclass': deviceSubclass,
      'vendorId': vendorId,
      'productId': productId,
      'interfaceClasses': interfaceClasses,
    };
  }

  @override
  List<Object?> get props => [
        name,
        deviceClass,
        deviceSubclass,
        vendorId,
        productId,
        interfaceClasses,
      ];
}
