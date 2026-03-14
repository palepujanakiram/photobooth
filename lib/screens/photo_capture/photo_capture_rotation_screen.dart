import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import '../../views/widgets/app_colors.dart';

/// Screen to choose camera preview rotation (0, 90, 180, 270 degrees).
/// Selected value is saved to SharedPreferences and used on Capture Photo screen.
class PhotoCaptureRotationScreen extends StatelessWidget {
  const PhotoCaptureRotationScreen({super.key, this.currentRotation = 0});

  final int currentRotation;

  static const List<int> _options = [0, 90, 180, 270];

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: appColors.backgroundColor,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Preview rotation'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            const SizedBox(height: 8),
            Text(
              'Choose how the camera preview is rotated. Saved for all sessions.',
              style: TextStyle(
                fontSize: 14,
                color: appColors.textColor.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 24),
            ..._options.map((degrees) {
              final isSelected = degrees == currentRotation;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: isSelected
                      ? appColors.primaryColor.withValues(alpha: 0.3)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => Navigator.pop(context, degrees),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                            color: isSelected ? appColors.primaryColor : Colors.grey,
                            size: 24,
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '$degrees°',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: appColors.textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
