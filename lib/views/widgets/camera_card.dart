import 'package:flutter/cupertino.dart';
import '../../screens/camera_selection/camera_info_model.dart';

class CameraCard extends StatelessWidget {
  final CameraInfoModel camera;
  final bool isSelected;
  final VoidCallback onTap;

  const CameraCard({
    super.key,
    required this.camera,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: CupertinoColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? CupertinoColors.systemBlue 
                : CupertinoColors.separator,
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: CupertinoColors.systemBlue.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: CupertinoColors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? CupertinoColors.systemBlue.withValues(alpha: 0.1)
                      : CupertinoColors.systemGrey5,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  camera.isFrontFacing 
                      ? CupertinoIcons.camera_fill 
                      : CupertinoIcons.camera,
                  size: 32,
                  color: isSelected 
                      ? CupertinoColors.systemBlue 
                      : CupertinoColors.systemGrey,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  camera.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: isSelected 
                        ? FontWeight.bold 
                        : FontWeight.w500,
                    color: isSelected 
                        ? CupertinoColors.systemBlue 
                        : CupertinoColors.black,
                  ),
                ),
              ),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: CupertinoColors.systemBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    CupertinoIcons.check_mark,
                    color: CupertinoColors.white,
                    size: 16,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

