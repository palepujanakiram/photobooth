import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import '../../utils/alice_inspector.dart';

/// Floating debug button to open Alice HTTP inspector
/// 
/// Only visible in debug mode on mobile platforms
/// Shows a small floating button that opens the Alice network inspector
/// 
/// Usage:
/// ```dart
/// Stack(
///   children: [
///     YourMainContent(),
///     AliceDebugButton(), // Add this at the end
///   ],
/// )
/// ```
class AliceDebugButton extends StatelessWidget {
  const AliceDebugButton({super.key});

  @override
  Widget build(BuildContext context) {
    // Only show in debug mode and not on web
    if (!kDebugMode || kIsWeb) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 16,
      right: 16,
      child: FloatingActionButton(
        mini: true,
        backgroundColor: Colors.blue.withOpacity(0.8),
        onPressed: () => AliceInspector.show(context),
        child: const Icon(
          Icons.network_check,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

/// Alternative: Small badge-style button that's less intrusive
class AliceDebugBadge extends StatelessWidget {
  const AliceDebugBadge({super.key});

  @override
  Widget build(BuildContext context) {
    // Only show in debug mode and not on web
    if (!kDebugMode || kIsWeb) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 50,
      right: 16,
      child: GestureDetector(
        onTap: () => AliceInspector.show(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.network_check,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 4),
              const Text(
                'API',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
