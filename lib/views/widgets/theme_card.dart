import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../screens/theme_selection/theme_model.dart';
import '../../utils/app_config.dart';

class ThemeCard extends StatelessWidget {
  final ThemeModel theme;
  final bool isSelected;
  final VoidCallback onTap;

  const ThemeCard({
    super.key,
    required this.theme,
    required this.isSelected,
    required this.onTap,
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
      elevation: isSelected ? 8 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected 
              ? CupertinoColors.systemBlue 
              : Colors.transparent,
          width: isSelected ? 3 : 0,
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
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: Colors.grey[200],
                        child: Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                            color: CupertinoColors.systemBlue,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[200],
                        child: const Center(
                          child: Icon(
                            Icons.image_not_supported,
                            size: 48,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                  )
                : Container(
                    color: Colors.grey[200],
                    child: const Center(
                      child: Icon(
                        Icons.palette,
                        size: 48,
                        color: Colors.grey,
                      ),
                    ),
                  ),
            // Background color overlay at bottom for text
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: _parseColor(theme.backgroundColor) ?? 
                    Colors.black.withValues(alpha: 0.8),
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      theme.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected 
                            ? FontWeight.bold 
                            : FontWeight.w600,
                        color: _parseColor(theme.textColor) ?? Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      theme.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: (_parseColor(theme.textColor) ?? Colors.white)
                            .withValues(alpha: 0.9),
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

