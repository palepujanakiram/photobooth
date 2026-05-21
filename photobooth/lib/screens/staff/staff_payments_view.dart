import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/staff_api_service.dart';
import '../../services/api_service.dart';
import '../../services/app_settings_manager.dart';
import '../../services/print_service.dart';
import '../../utils/constants.dart';
import '../../utils/exceptions.dart';
import 'staff_payment_card.dart';
import 'staff_payments_payload_utils.dart';
import 'staff_payments_thumb_helpers.dart';
import 'staff_payments_view_helpers.dart';
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

  static String _paymentId(Map<String, dynamic> p) =>
      StaffPaymentsPayloadUtils.pickString(
        p,
        const ['id', 'paymentId', 'payment_id'],
      );

  static String _paymentStatus(Map<String, dynamic> p) =>
      StaffPaymentsPayloadUtils.pickString(
        p,
        const ['status', 'paymentStatus', 'payment_status'],
      ).toUpperCase();

  static String _sessionId(Map<String, dynamic> p) {
    final direct = StaffPaymentsPayloadUtils.pickString(
      p,
      const ['sessionId', 'session_id'],
    );
    if (direct.isNotEmpty) return direct;

    final sessionObj = p['session'];
    if (sessionObj is Map) {
      final m = Map<String, dynamic>.from(sessionObj);
      final embedded = StaffPaymentsPayloadUtils.pickString(
        m,
        const ['id', 'sessionId', 'session_id'],
      );
      if (embedded.isNotEmpty) return embedded;
    }

    final any = StaffPaymentsPayloadUtils.deepFindFirstValueForKeys(
      p,
      const ['sessionId', 'session_id', 'sessionID', 'session'],
    );
    return any?.trim() ?? '';
  }

  static String _paymentThumbUrlFromPayload(Map<String, dynamic> p) {
    return StaffPaymentsPayloadUtils.pickString(p, const [
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
    return StaffPaymentsPayloadUtils.pickString(p, const [
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
      return StaffPaymentsPayloadUtils.normalizeImageUrl(
        fromPaymentRaw,
        sessionId: sid.isEmpty ? null : sid,
      );
    }

    if (sid.isEmpty) return null;
    final raw = await _publicApi.fetchSession(sid);
    if (!mounted || raw == null) return null;
    return StaffPaymentsPayloadUtils.resolveSessionImageUrl(
      raw,
      sessionId: sid,
    );
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

      final imageUrl = StaffPaymentsPayloadUtils.resolveSessionImageUrl(
        raw,
        sessionId: sid,
      );
      if (imageUrl != null) {
        setState(() => _sessionThumbUrlCache[sid] = imageUrl);
        return;
      }

      final userImage =
          StaffPaymentsPayloadUtils.userImageFieldFromSession(raw);
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
    final resolved = staffPaymentThumbResolvedUrl(
      sessionId: sid,
      payloadUrl: payloadUrl,
      sessionThumbUrlCache: _sessionThumbUrlCache,
    );

    if (resolved.isEmpty) {
      if (sid.isNotEmpty) _ensureSessionThumbLoaded(sid);
      return staffPaymentThumbPlaceholder();
    }

    return staffPaymentThumbImage(
      resolved: resolved,
      placeholder: staffPaymentThumbPlaceholder,
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
      final endpoint = staffPaymentsPrinterEndpoint(
        context.read<AppSettingsManager>().settings,
      );

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
        printerHost: endpoint.host,
        printerPort: endpoint.port,
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
          final sid = _sessionId(p);
          return StaffPaymentCard(
            appColors: appColors,
            paymentId: _paymentId(p),
            status: _paymentStatus(p),
            sessionId: sid,
            amount: StaffPaymentCard.amountFromPayload(p),
            thumb: _buildThumb(sid, _paymentThumbUrlFromPayload(p)),
            loading: _loading,
            showDecisionButtons: showDecisionButtons,
            onApprove: () => _approve(p),
            onReject: () => _reject(p),
            onPrint: () => _printForSession(p),
          );
        },
      ),
    );
  }
}

