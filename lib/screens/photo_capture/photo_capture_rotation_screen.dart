import 'package:flutter/cupertino.dart';
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
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        backgroundColor: appColors.backgroundColor,
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.back),
        ),
        middle: const Text('Preview rotation'),
      ),
      child: SafeArea(
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
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  color: isSelected
                      ? appColors.primaryColor.withValues(alpha: 0.3)
                      : CupertinoColors.systemGrey6,
                  borderRadius: BorderRadius.circular(12),
                  onPressed: () {
                    Navigator.pop(context, degrees);
                  },
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                        color: isSelected ? appColors.primaryColor : CupertinoColors.systemGrey,
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
              );
            }),
          ],
        ),
      ),
    );
  }
}
