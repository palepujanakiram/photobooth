import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import '../utils/secure_image_url.dart';
import '../utils/session_photo_sync_helpers.dart';
import 'protected_image_loader.dart';

/// Parsed result of POST `/api/kiosk/upload-links`.
class PhoneUploadLinkInfo {
  const PhoneUploadLinkInfo({
    required this.token,
    required this.url,
    this.expiresAt,
  });

  final String token;
  final String url;
  final DateTime? expiresAt;

  static PhoneUploadLinkInfo? tryParse(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    final token = (raw['token'] ?? '').toString().trim();
    final url = (raw['url'] ?? raw['longUrl'] ?? '').toString().trim();
    if (token.isEmpty || url.isEmpty) return null;
    DateTime? expires;
    final expRaw = raw['expiresAt'];
    if (expRaw != null) {
      expires = DateTime.tryParse(expRaw.toString());
    }
    return PhoneUploadLinkInfo(token: token, url: url, expiresAt: expires);
  }
}

/// Poll interval and overall timeout for waiting on phone upload.
const Duration kPhoneUploadPollInterval = Duration(seconds: 2);
const Duration kPhoneUploadPollTimeout = Duration(minutes: 12);

/// Downloads a session preview URL into an [XFile] for local kiosk preview.
Future<XFile> downloadPhoneUploadPreviewToXFile(
  String imageUrl, {
  Dio? dio,
}) async {
  final trimmed = imageUrl.trim();
  if (trimmed.isEmpty) {
    throw StateError('Missing preview URL after phone upload');
  }
  final url = SecureImageUrl.absolutize(trimmed);

  List<int> bytes;
  if (ProtectedImageLoader.isProtectedUrl(url)) {
    bytes = await ProtectedImageLoader.instance.fetchBytes(url);
  } else {
    final client = dio ?? Dio();
    final response = await client.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        validateStatus: (c) => c != null && c >= 200 && c < 400,
      ),
    );
    bytes = response.data ?? const <int>[];
  }
  if (bytes.isEmpty) {
    throw StateError('Empty preview after phone upload');
  }

  final data = Uint8List.fromList(bytes);
  final name = 'phone_upload_${DateTime.now().millisecondsSinceEpoch}.jpg';
  return XFile.fromData(data, mimeType: 'image/jpeg', name: name);
}

/// True when a lightweight session GET indicates the guest selfie is present.
bool phoneUploadSessionReady(Map<String, dynamic>? session) =>
    sessionResponseHasUserImage(session);

/// Preview URL preferred from the lightweight GET payload.
String? phoneUploadPreviewUrlFromSession(Map<String, dynamic>? session) {
  if (session == null) return null;
  for (final key in const ['userImageUrl', 'userImagePreviewUrl']) {
    final v = (session[key] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return null;
}
