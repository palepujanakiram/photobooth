import '../models/device_memory_snapshot.dart';
import 'process_rss_web.dart';

Future<DeviceMemorySnapshot> readDeviceMemorySnapshot() async {
  final jsHeap = currentProcessResidentBytes();
  return DeviceMemorySnapshot(processRssBytes: jsHeap);
}
