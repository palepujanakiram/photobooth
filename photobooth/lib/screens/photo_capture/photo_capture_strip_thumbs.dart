import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../models/strip_models.dart';
import 'photo_image_from_xfile_io.dart'
    if (dart.library.html) 'photo_image_from_xfile_web.dart' as photo_image;

/// Top strip of accepted FotoFlashback shots on the POSE screen.
///
/// Stamp-sized thumbs use the print cell aspect for [total] shots (same cover
/// crop as the 2×6 print), so a 3-shot strip previews its taller cells.
class PhotoCaptureStripThumbs extends StatelessWidget {
  const PhotoCaptureStripThumbs({
    super.key,
    required this.shotFiles,
    required this.total,
    this.pendingFile,
  });

  final List<XFile> shotFiles;
  final int total;
  final XFile? pendingFile;

  static const double _gap = 10;
  /// Stamp height; width = height × print cell aspect (4-shot ≈ 592/448).
  static const double stampHeight = 64;

  /// Legacy 4-shot stamp width; [stampWidthFor] follows the real strip length.
  static double get stampWidth => stampHeight * kStripCellAspectRatio;

  static double stampWidthFor(int shotCount) =>
      stampHeight * stripCellAspectRatioForShots(shotCount);

  @override
  Widget build(BuildContext context) {
    final slotWidth = stampWidthFor(total);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: SizedBox(
        height: stampHeight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < total; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              _StripThumbSlot(
                index: i,
                file: _fileAt(i),
                isActive: _isActive(i),
                width: slotWidth,
                height: stampHeight,
              ),
            ],
          ],
        ),
      ),
    );
  }

  XFile? _fileAt(int index) {
    if (index < shotFiles.length) return shotFiles[index];
    if (index == shotFiles.length) return pendingFile;
    return null;
  }

  bool _isActive(int index) => index == shotFiles.length;
}

class _StripThumbSlot extends StatelessWidget {
  const _StripThumbSlot({
    required this.index,
    required this.file,
    required this.isActive,
    required this.width,
    required this.height,
  });

  final int index;
  final XFile? file;
  final bool isActive;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final border = isActive
        ? Colors.amber.shade400
        : (file != null ? Colors.white60 : Colors.white24);
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border, width: isActive ? 2 : 1),
          color: Colors.black45,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: file != null
              ? photo_image.imageFromXFileSized(
                  file!,
                  width,
                  height,
                  fit: BoxFit.cover,
                )
              : ColoredBox(
                  color: Colors.white10,
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color:
                            isActive ? Colors.amber.shade200 : Colors.white38,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
