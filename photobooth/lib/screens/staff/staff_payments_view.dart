import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/staff_api_service.dart';
import '../../services/api_service.dart';
import '../../services/app_settings_manager.dart';
import '../../services/print_service.dart';
import '../../utils/constants.dart';
import '../../utils/exceptions.dart';
import '../../utils/secure_image_url.dart';
import '../../views/widgets/app_colors.dart';

class StaffPaymentsScreen extends StatefulWidget {
  const StaffPaymentsScreen({super.key});

  @override
  State<StaffPaymentsScreen> createState() => _StaffPaymentsScreenState();
}

class _StaffPaymentsScreenState extends State<StaffPaymentsScreen> {
  final _api = StaffApiService();
  final _publicApi = ApiService();
  final _printService = PrintService();

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _payments = const [];
  String _progressMessage = '';

  final Map<String, String> _sessionThumbUrlCache = {};
  final Set<String> _sessionThumbLoadInFlight = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  static String _pickString(Map<String, dynamic> p, List<String> keys) {
    for (final k in keys) {
      final v = p[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static String _paymentId(Map<String, dynamic> p) =>
      _pickString(p, const ['id', 'paymentId', 'payment_id']);

  static String _paymentStatus(Map<String, dynamic> p) =>
      _pickString(p, const ['status', 'paymentStatus', 'payment_status'])
          .toUpperCase();

  static String _sessionId(Map<String, dynamic> p) {
    // Common flat keys.
    final direct = _pickString(p, const ['sessionId', 'session_id']);
    if (direct.isNotEmpty) return direct;

    // Sometimes the payment embeds a session object.
    final sessionObj = p['session'];
    if (sessionObj is Map) {
      final m = Map<String, dynamic>.from(sessionObj);
      final embedded = _pickString(m, const ['id', 'sessionId', 'session_id']);
      if (embedded.isNotEmpty) return embedded;
    }

    // Last resort: search nested payload for a session id.
    final any = _deepFindFirstValueForKeys(
      p,
      const ['sessionId', 'session_id', 'sessionID', 'session'],
    );
    return any?.trim() ?? '';
  }

  static String? _deepFindFirstValueForKeys(
    dynamic node,
    List<String> keys, {
    int depth = 0,
  }) {
    if (node == null || depth > 5) return null;
    if (node is Map) {
      final m = Map<String, dynamic>.from(node);
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
        // If the value is an object, try pulling id from it.
        if ((k == 'session' || k.toLowerCase() == 'session') && v is Map) {
          final id = Map<String, dynamic>.from(v)['id'];
          if (id is String && id.trim().isNotEmpty) return id.trim();
        }
      }
      for (final v in m.values) {
        final found =
            _deepFindFirstValueForKeys(v, keys, depth: depth + 1);
        if (found != null) return found;
      }
      return null;
    }
    if (node is List) {
      for (final e in node) {
        final found =
            _deepFindFirstValueForKeys(e, keys, depth: depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  static String _baseUrlNoTrailingSlash() {
    const b = AppConstants.kBaseUrl;
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  static String _absolutizeIfRelative(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    // data:image/... is already absolute in a sense (inline image).
    if (trimmed.startsWith('data:image')) return trimmed;
    final base = _baseUrlNoTrailingSlash();
    if (trimmed.startsWith('/')) return '$base$trimmed';
    return '$base/$trimmed';
  }

  static bool _looksLikeUrl(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    if (t.startsWith('http://') || t.startsWith('https://')) return true;
    if (t.startsWith('/')) return true;
    // Common relative API/img paths.
    if (t.startsWith('api/')) return true;
    if (t.startsWith('api/img/')) return true;
    if (t.startsWith('/api/')) return true;
    return false;
  }

  static String _normalizeImageUrl(String raw, {String? sessionId}) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    if (t.startsWith('data:image')) return t;
    // Make relative URLs absolute and attach sessionId for protected /api/img paths.
    final absolute = _absolutizeIfRelative(t);
    return SecureImageUrl.withSessionId(absolute, sessionId: sessionId);
  }

  static String? _deepFindFirstUrl(dynamic node, {int depth = 0}) {
    if (node == null || depth > 4) return null;
    if (node is String) {
      final t = node.trim();
      if (_looksLikeUrl(t)) return t;
      return null;
    }
    if (node is Map) {
      final m = Map<String, dynamic>.from(node);
      // Prefer likely keys first.
      for (final k in const [
        'imageUrl',
        'image_url',
        'url',
        'photoUrl',
        'photo_url',
        'thumbnailUrl',
        'thumbUrl',
        'previewUrl',
      ]) {
        final v = m[k];
        if (v is String && _looksLikeUrl(v)) return v;
      }
      for (final v in m.values) {
        final found = _deepFindFirstUrl(v, depth: depth + 1);
        if (found != null) return found;
      }
      return null;
    }
    if (node is List) {
      for (final e in node) {
        final found = _deepFindFirstUrl(e, depth: depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  static String _paymentThumbUrlFromPayload(Map<String, dynamic> p) {
    // Try common keys first (we don't know exact backend shape yet).
    return _pickString(p, const [
      'thumbnailUrl',
      'thumbUrl',
      'imageUrl',
      'image_url',
      'generatedImageUrl',
      'generated_image_url',
      'photoUrl',
      'photo_url',
      'sessionImageUrl',
      'previewUrl',
    ]);
  }

  static String _paymentImageUrlForPrintFromPayload(Map<String, dynamic> p) {
    // Prefer explicit image URL keys (over thumbnails).
    return _pickString(p, const [
      'imageUrl',
      'image_url',
      'generatedImageUrl',
      'generated_image_url',
      'photoUrl',
      'photo_url',
    ]);
  }

  Future<String?> _resolveImageUrlForPrint(Map<String, dynamic> payment) async {
    final fromPaymentRaw = _paymentImageUrlForPrintFromPayload(payment).trim();
    final sid = _sessionId(payment).trim();
    if (fromPaymentRaw.isNotEmpty) {
      return _normalizeImageUrl(fromPaymentRaw, sessionId: sid.isEmpty ? null : sid);
    }

    if (sid.isEmpty) return null;
    final raw = await _publicApi.fetchSession(sid);
    if (!mounted || raw == null) return null;

    // Prefer generated image URL when present (handle multiple shapes/keys).
    final generated = raw['generatedImages'] ?? raw['generated_images'] ?? raw['images'];
    if (generated is List && generated.isNotEmpty) {
      final first = generated.first;
      if (first is Map) {
        final m = Map<String, dynamic>.from(first);
        final u = (m['imageUrl'] ??
                m['image_url'] ??
                m['url'] ??
                m['photoUrl'] ??
                m['photo_url'] ??
                '')
            .toString()
            .trim();
        if (u.isNotEmpty) return _normalizeImageUrl(u, sessionId: sid);
      }
      if (first is String) {
        final u = first.trim();
        if (u.isNotEmpty) return _normalizeImageUrl(u, sessionId: sid);
      }
    }

    // Last resort: search the session payload for *any* URL-like string.
    final any = _deepFindFirstUrl(raw);
    if (any != null) return _normalizeImageUrl(any, sessionId: sid);

    return null;
  }

  Future<void> _ensureSessionThumbLoaded(String sessionId) async {
    final sid = sessionId.trim();
    if (sid.isEmpty) return;
    if (_sessionThumbUrlCache.containsKey(sid)) return;
    if (_sessionThumbLoadInFlight.contains(sid)) return;
    _sessionThumbLoadInFlight.add(sid);
    try {
      final raw = await _publicApi.fetchSession(sid);
      if (!mounted || raw == null) return;

      // Prefer generated image URL when present.
      final generated = raw['generatedImages'] ?? raw['generated_images'] ?? raw['images'];
      if (generated is List && generated.isNotEmpty) {
        final first = generated.first;
        if (first is Map) {
          final m = Map<String, dynamic>.from(first);
          final u = (m['imageUrl'] ??
                  m['image_url'] ??
                  m['url'] ??
                  m['photoUrl'] ??
                  m['photo_url'] ??
                  '')
              .toString()
              .trim();
          if (u.isNotEmpty) {
            setState(() => _sessionThumbUrlCache[sid] = _normalizeImageUrl(u, sessionId: sid));
            return;
          }
        }
        if (first is String) {
          final u = first.trim();
          if (u.isNotEmpty) {
            setState(() => _sessionThumbUrlCache[sid] = _normalizeImageUrl(u, sessionId: sid));
            return;
          }
        }
      }

      // Fallback: base64 user image (if provided).
      final userImage = (raw['userImageUrl'] ?? raw['user_image_url'] ?? '')
          .toString()
          .trim();
      if (userImage.isNotEmpty) {
        // Store as a sentinel; renderer will decode.
        setState(() => _sessionThumbUrlCache[sid] = userImage);
      }
    } finally {
      _sessionThumbLoadInFlight.remove(sid);
    }
  }

  Widget _buildThumb(String sessionId, String payloadUrl) {
    final sid = sessionId.trim();
    final raw = payloadUrl.trim().isNotEmpty
        ? payloadUrl.trim()
        : (_sessionThumbUrlCache[sid] ?? '');
    final resolved = _normalizeImageUrl(raw, sessionId: sid.isEmpty ? null : sid);

    Widget placeholder() => Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black12),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.image, size: 22, color: Colors.black45),
        );

    if (resolved.isEmpty) {
      // Lazy load session-derived thumbnail.
      if (sid.isNotEmpty) {
        // Fire-and-forget; cache + setState will rebuild.
        _ensureSessionThumbLoaded(sid);
      }
      return placeholder();
    }

    // Base64 data URL or bare base64.
    if (resolved.startsWith('data:image')) {
      try {
        final uriData = UriData.parse(resolved);
        final bytes = uriData.contentAsBytes();
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            bytes,
            width: 54,
            height: 54,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder(),
          ),
        );
      } catch (_) {
        return placeholder();
      }
    }
    // Likely bare base64 (no scheme). Avoid decoding huge strings unless it
    // looks like base64 and is within a reasonable size.
    final looksLikeBase64 = !resolved.startsWith('http') &&
        !resolved.startsWith('/') &&
        resolved.length > 100 &&
        resolved.length < 200000;
    if (looksLikeBase64) {
      try {
        final bytes = base64Decode(resolved);
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            bytes,
            width: 54,
            height: 54,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder(),
          ),
        );
      } catch (_) {
        // Fall through to network attempt (might be some other token).
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        resolved,
        width: 54,
        height: 54,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder(),
      ),
    );
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.listPayments();
      if (!mounted) return;
      setState(() => _payments = list);
    } on ApiException catch (e) {
      if (!mounted) return;
      // If session expired, send back to login.
      if ((e.statusCode == 401) ||
          e.message.toLowerCase().contains('expired') ||
          e.message.toLowerCase().contains('log in')) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppConstants.kRouteStaffLogin,
          (r) => false,
        );
        return;
      }
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load payments: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(Map<String, dynamic> p) async {
    final id = _paymentId(p);
    if (id.isEmpty) {
      setState(() => _error = 'Missing paymentId in response');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.approvePayment(paymentId: id);
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Approve failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reject(Map<String, dynamic> p) async {
    final id = _paymentId(p);
    if (id.isEmpty) {
      setState(() => _error = 'Missing paymentId in response');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.rejectPayment(paymentId: id);
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Reject failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _printForSession(Map<String, dynamic> p) async {
    final sid = _sessionId(p);
    if (sid.isEmpty) {
      setState(() => _error = 'Missing sessionId in payment payload');
      return;
    }

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Create print job?'),
            content: Text('Session: $sid'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Print'),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !ok) return;

    setState(() {
      _loading = true;
      _error = null;
      _progressMessage = 'Preparing image...';
    });
    try {
      // Capture printer settings before async gaps.
      final settings = context.read<AppSettingsManager>().settings;
      final host = (settings?.printerHost?.trim().isNotEmpty ?? false)
          ? settings!.printerHost!.trim()
          : AppConstants.kDefaultPrinterHost;
      final port = (settings?.printerPort != null &&
              settings!.printerPort! > 0 &&
              settings.printerPort! <= 65535)
          ? settings.printerPort!
          : 80;

      // Resolve a network URL for the generated image (server-hosted), then
      // print via the same kiosk path: download -> network printer API.
      final imageUrl = await _resolveImageUrlForPrint(p);
      if (imageUrl == null || imageUrl.isEmpty) {
        throw PrintException(
          'Cannot print: image URL not found for this session.',
        );
      }

      // Download to a temp file (or use XFile(url) on web).
      final file = await _publicApi.downloadImageToTemp(
        imageUrl,
        onProgress: (m) {
          if (!mounted) return;
          setState(() => _progressMessage = m);
        },
      );

      setState(() => _progressMessage = 'Sending print job...');
      await _printService.printImageToNetworkPrinter(
        file,
        printerHost: host,
        printerPort: port,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Print job sent')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } on PrintException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Print failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.logout();
    } catch (_) {
      // Ignore logout errors; local session is cleared in the service.
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppConstants.kRouteStaffLogin,
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final pending =
        _payments.where((p) => _paymentStatus(p) == 'PENDING').toList();
    final history =
        _payments.where((p) => _paymentStatus(p) != 'PENDING').toList();
    return Scaffold(
      backgroundColor: appColors.backgroundColor,
      appBar: AppBar(
        title: const Text('Staff payments'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _loading ? null : _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: TabBar(
                      tabs: [
                        Tab(text: 'Pending (${pending.length})'),
                        Tab(text: 'History (${history.length})'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildPaymentsList(appColors, pending, showDecisionButtons: true),
                        _buildPaymentsList(appColors, history, showDecisionButtons: false),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Material(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _error = null),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_loading)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.05),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        if (_progressMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              _progressMessage,
                              textAlign: TextAlign.center,
                            ),
                          ),
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

  Widget _buildPaymentsList(
    AppColors appColors,
    List<Map<String, dynamic>> list, {
    required bool showDecisionButtons,
  }) {
    if (list.isEmpty && !_loading && _error == null) {
      return const Center(child: Text('No payments'));
    }
    if (list.isEmpty) {
      return const SizedBox.shrink();
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final p = list[i];
          final id = _paymentId(p);
          final status = _paymentStatus(p);
          final sid = _sessionId(p);
          final amount = _pickString(p, const ['amount', 'total', 'price']);
          final thumb = _paymentThumbUrlFromPayload(p);

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildThumb(sid, thumb),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    id.isEmpty ? '(no id)' : id,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: status == 'APPROVED'
                                        ? Colors.green.withValues(alpha: 0.12)
                                        : status == 'FAILED' || status == 'REJECTED'
                                            ? Colors.red.withValues(alpha: 0.12)
                                            : Colors.orange.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    status.isEmpty ? 'UNKNOWN' : status,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (amount.isNotEmpty)
                              Text(
                                'Amount: $amount',
                                style: TextStyle(color: appColors.textColor),
                              ),
                            if (sid.isNotEmpty)
                              Text(
                                'Session: $sid',
                                style: TextStyle(color: appColors.textColor),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (showDecisionButtons)
                        ElevatedButton(
                          onPressed: _loading ? null : () => _approve(p),
                          child: const Text('Approve'),
                        ),
                      if (showDecisionButtons)
                        OutlinedButton(
                          onPressed: _loading ? null : () => _reject(p),
                          child: const Text('Reject'),
                        ),
                      OutlinedButton.icon(
                        onPressed: (_loading || sid.isEmpty)
                            ? null
                            : () => _printForSession(p),
                        icon: const Icon(Icons.print),
                        label: const Text('Print'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

