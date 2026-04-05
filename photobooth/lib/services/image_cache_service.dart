import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// Service for caching theme images to disk for persistent storage
class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;
  ImageCacheService._internal();

  Directory? _cacheDir;
  static const String _cacheSubDir = 'theme_images';
  static const int _maxCacheSizeMB = 100; // Maximum cache size in MB
  static const int maxCacheAgeDays = 30; // Maximum age of cached images in days

  /// Initialize cache directory
  Future<void> _ensureCacheDir() async {
    if (_cacheDir != null && await _cacheDir!.exists()) return;

    final appCacheDir = await getTemporaryDirectory();
    _cacheDir = Directory(path.join(appCacheDir.path, _cacheSubDir));
    
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
  }

  /// Get cache file path for a given image URL
  /// Normalizes the URL to ensure consistent caching
  Future<String> _getCacheFilePath(String imageUrl) async {
    await _ensureCacheDir();
    
    // Normalize URL: remove query parameters, fragments, and normalize path
    final uri = Uri.parse(imageUrl);
    final normalizedUrl = '${uri.scheme}://${uri.host}${uri.path}';
    
    // Create a safe filename from normalized URL
    final bytes = utf8.encode(normalizedUrl);
    final hash = bytes.fold<int>(0, (prev, byte) => prev + byte);
    // Use a combination of hash and normalized URL length for better uniqueness
    final urlHash = '${hash.toRadixString(36)}_${normalizedUrl.length}';
    
    // Get extension from URL path or default to jpg
    final extension = path.extension(uri.path).isEmpty 
        ? '.jpg' 
        : path.extension(uri.path);
    
    return path.join(_cacheDir!.path, '$urlHash$extension');
  }

  /// Check if image is cached
  Future<bool> isCached(String imageUrl) async {
    try {
      final cacheFile = File(await _getCacheFilePath(imageUrl));
      if (!await cacheFile.exists()) return false;

      // Check if cache is too old
      final stat = await cacheFile.stat();
      final age = DateTime.now().difference(stat.modified);
      if (age.inDays > maxCacheAgeDays) {
        // Delete old cache
        await cacheFile.delete();
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error checking cache: $e');
      return false;
    }
  }

  /// Get cached image file
  Future<File?> getCachedFile(String imageUrl) async {
    try {
      if (!await isCached(imageUrl)) return null;
      
      final cacheFile = File(await _getCacheFilePath(imageUrl));
      if (await cacheFile.exists()) {
        return cacheFile;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting cached file: $e');
      return null;
    }
  }

  /// Download and cache image
  Future<File?> cacheImage(String imageUrl) async {
    try {
      // Check if already cached
      final cachedFile = await getCachedFile(imageUrl);
      if (cachedFile != null) {
        return cachedFile;
      }

      // Download image
      debugPrint('Downloading and caching image: $imageUrl');
      final response = await http.get(Uri.parse(imageUrl)).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Image download timeout');
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to download image: ${response.statusCode}');
      }

      // Save to cache
      final cacheFile = File(await _getCacheFilePath(imageUrl));
      await cacheFile.writeAsBytes(response.bodyBytes);

      // Check cache size and clean if needed
      await _cleanCacheIfNeeded();

      debugPrint('Image cached successfully: ${cacheFile.path}');
      return cacheFile;
    } catch (e) {
      debugPrint('Error caching image: $e');
      return null;
    }
  }

  /// Get image file (cached or download)
  /// Returns the file path if cached, or null if download failed
  Future<File?> getImageFile(String imageUrl) async {
    // Try to get from cache first
    final cachedFile = await getCachedFile(imageUrl);
    if (cachedFile != null) {
      return cachedFile;
    }

    // Download and cache
    return await cacheImage(imageUrl);
  }

  /// Clean cache if it exceeds maximum size
  Future<void> _cleanCacheIfNeeded() async {
    try {
      await _ensureCacheDir();
      
      final files = await _cacheDir!.list().toList();
      int totalSize = 0;
      final fileInfo = <({File file, FileStat stat})>[];

      for (var file in files) {
        if (file is File) {
          final stat = await file.stat();
          totalSize += stat.size;
          fileInfo.add((file: file, stat: stat));
        }
      }

      const maxSizeBytes = _maxCacheSizeMB * 1024 * 1024;
      
      if (totalSize > maxSizeBytes) {
        // Sort by modification time (oldest first)
        fileInfo.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
        
        // Delete oldest files until under limit
        int currentSize = totalSize;
        for (var info in fileInfo) {
          if (currentSize <= maxSizeBytes) break;
          
          try {
            if (await info.file.exists()) {
              await info.file.delete();
              currentSize -= info.stat.size;
              debugPrint('Deleted old cache file: ${info.file.path}');
            }
          } catch (e) {
            debugPrint('Error deleting cache file: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning cache: $e');
    }
  }

  /// Clear all cached images
  Future<void> clearCache() async {
    try {
      await _ensureCacheDir();
      
      if (await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
        debugPrint('Cache cleared');
      }
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  /// Get cache size in bytes
  Future<int> getCacheSize() async {
    try {
      await _ensureCacheDir();
      
      if (!await _cacheDir!.exists()) return 0;
      
      int totalSize = 0;
      await for (var entity in _cacheDir!.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }
      
      return totalSize;
    } catch (e) {
      debugPrint('Error getting cache size: $e');
      return 0;
    }
  }
}

