/// Classifies the app's device for UI/camera behavior.
/// Used to show only external cameras on tablet/TV and only built-in on phone.
enum AppDeviceType {
  iosPhone,
  iosTablet,
  iosTv,
  androidPhone,
  androidTablet,
  androidTv,
  unknown,
}
