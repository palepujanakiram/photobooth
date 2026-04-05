import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart';

import '../../utils/process_rss.dart';

/// Live process RSS (MB) + sparkline for spotting camera-related memory spikes.
class DebugRamMonitorOverlay extends StatefulWidget {
  const DebugRamMonitorOverlay({super.key});

  @override
  State<DebugRamMonitorOverlay> createState() => _DebugRamMonitorOverlayState();
}

class _DebugRamMonitorOverlayState extends State<DebugRamMonitorOverlay> {
  static const int _maxSamples = 90;
  static const Duration _sampleInterval = Duration(milliseconds: 500);

  final List<int> _samples = [];
  Timer? _timer;
  int? _lastBytes;
  int _peakBytes = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_sampleInterval, (_) => _tick());
    _tick();
  }

  void _tick() {
    if (!mounted) return;
    final bytes = currentProcessResidentBytes();
    setState(() {
      _lastBytes = bytes;
      if (bytes != null) {
        if (bytes > _peakBytes) _peakBytes = bytes;
        _samples.add(bytes);
        while (_samples.length > _maxSamples) {
          _samples.removeAt(0);
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _lastBytes;
    final mb = bytes != null ? bytes / (1024 * 1024) : null;
    final peakMb = _peakBytes > 0 ? _peakBytes / (1024 * 1024) : null;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: 132,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RAM (RSS)',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              mb != null
                  ? '${mb.toStringAsFixed(1)} MB'
                  : (kIsWeb ? 'n/a (web)' : 'n/a'),
              style: const TextStyle(
                color: Colors.limeAccent,
                fontSize: 13,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (peakMb != null) ...[
              const SizedBox(height: 2),
              Text(
                'peak ${peakMb.toStringAsFixed(1)} MB',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 9,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            const SizedBox(height: 4),
            SizedBox(
              height: 36,
              width: double.infinity,
              child: CustomPaint(
                painter: _RamSparklinePainter(List<int>.from(_samples)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RamSparklinePainter extends CustomPainter {
  _RamSparklinePainter(this.samples);

  final List<int> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.white10;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(4),
    );
    canvas.drawRRect(r, bg);

    if (samples.length < 2) return;

    var minV = samples.first;
    var maxV = samples.first;
    for (final v in samples) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final range = math.max(maxV - minV, 1);

    final line = Paint()
      ..color = Colors.limeAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final t = samples.length > 1 ? i / (samples.length - 1) : 0.0;
      final x = t * size.width;
      final y = size.height * (1 - (samples[i] - minV) / range);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _RamSparklinePainter oldDelegate) {
    return !listEquals(oldDelegate.samples, samples);
  }
}
