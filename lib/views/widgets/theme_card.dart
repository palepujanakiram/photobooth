import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../screens/theme_selection/theme_model.dart';
import '../../utils/app_config.dart';
import 'cached_network_image.dart';

class ThemeCard extends StatelessWidget {
  final ThemeModel theme;
  final bool isSelected;
  final VoidCallback onTap;
  /// When set and [isSelected] is true, shows a "Select" button to proceed (e.g. to next screen).
  final VoidCallback? onSelectPressed;
  final String actionButtonLabel;
  final double selectedBorderWidth;
  /// When true and [isSelected], shows "Selected" label in blue instead of the Select button (e.g. add-one-more flow).
  final bool showSelectedLabel;

  const ThemeCard({
    super.key,
    required this.theme,
    required this.isSelected,
    required this.onTap,
    this.onSelectPressed,
    this.showSelectedLabel = false,
    this.actionButtonLabel = 'Select',
    this.selectedBorderWidth = 1.0,
  });

  String _getImageUrl() {
    if (theme.sampleImageUrl == null || theme.sampleImageUrl!.isEmpty) {
      return '';
    }
    final imageUrl = theme.sampleImageUrl!;
    // Check if URL is already absolute
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return imageUrl;
    }
    // Prepend base URL if it's a relative path
    final baseUrl = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    final relativePath = imageUrl.startsWith('/') ? imageUrl : '/$imageUrl';
    return '$baseUrl$relativePath';
  }

  /// Parses hex color string to Color
  /// Supports formats: "#RRGGBB", "RRGGBB", "#AARRGGBB", "AARRGGBB"
  Color? _parseColor(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return null;
    
    final String hex = hexColor.replaceAll('#', '');
    
    // Handle 6-digit hex (RRGGBB)
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    
    // Handle 8-digit hex (AARRGGBB)
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _getImageUrl();
    
    return Card(
      elevation: isSelected ? 14 : 6,
      shadowColor: isSelected
          ? CupertinoColors.systemBlue.withValues(alpha: 0.55)
          : Colors.black.withValues(alpha: 0.38),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? CupertinoColors.systemBlue.withValues(alpha: 0.9)
              : const Color(0xFF4A4A4A),
          width: isSelected ? selectedBorderWidth : 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Image fills the complete box
            imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    cacheWidth: 480,
                    cacheHeight: 720,
                    filterQuality: FilterQuality.medium,
                    placeholder: Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: CupertinoColors.systemBlue,
                        ),
                      ),
                    ),
                    errorWidget: Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: Icon(
                          Icons.image_not_supported,
                          size: 48,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  )
                : Container(
                    color: Colors.grey[200],
                    child: const Center(
                      child: Icon(
                        CupertinoIcons.paintbrush,
                        size: 48,
                        color: Colors.grey,
                      ),
                    ),
                  ),
            // Bottom bar: name left, Select button right (sleek, no description)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  color: _parseColor(theme.backgroundColor) ??
                      Colors.black.withValues(alpha: 0.8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          theme.name,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: _parseColor(theme.textColor) ??
                                Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSelected && showSelectedLabel) ...[
                        const SizedBox(width: 6),
                        const Text(
                          'Selected',
                          style: TextStyle(
                            color: CupertinoColors.systemBlue,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      ] else if (isSelected && onSelectPressed != null) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onSelectPressed,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemBlue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              actionButtonLabel,
                              style: TextStyle(
                                color: CupertinoColors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

