import 'package:uuid/uuid.dart';

import '../models/payment_mode.dart';
import 'local_kiosk_models.dart';
import 'local_kiosk_store.dart';
import 'local_receipt_pdf.dart';
import 'local_session_skeleton.dart';

const _sessionIdRequired = 'sessionId is required';

class LocalReceiptIssue {
  const LocalReceiptIssue({
    required this.id,
    required this.receiptNumber,
    required this.json,
    this.pdfPath,
  });

  final String id;
  final String receiptNumber;
  final Map<String, dynamic> json;
  final String? pdfPath;
}

/// Cash / print / receipt writes on the kiosk ledger. Invoice numbers are
/// allocated here so Fly ingest can insert them without a second counter.
class LocalKioskSettlement {
  LocalKioskSettlement({
    required LocalKioskStore store,
    String Function()? newId,
    DateTime Function()? now,
  })  : _store = store,
        _newId = newId ?? _uuidV4,
        _now = now ?? DateTime.now;

  final LocalKioskStore _store;
  final String Function() _newId;
  final DateTime Function() _now;

  static String _uuidV4() => const Uuid().v4();

  Future<void> recordApprovedPayment({
    required String paymentId,
    required String sessionId,
    required int amount,
    required String paymentMode,
  }) async {
    final id = paymentId.trim();
    final sid = sessionId.trim();
    if (id.isEmpty || sid.isEmpty) {
      throw ArgumentError('paymentId and sessionId are required');
    }
    final mode = _requireMode(paymentMode);
    final rupees = amount < 0 ? 0 : amount;
    await _store.upsertPayment(
      id: id,
      sessionId: sid,
      payload: <String, dynamic>{
        'id': id,
        'sessionId': sid,
        'amount': rupees,
        'status': 'APPROVED',
        'paymentMode': mode,
      },
    );
    final session = await _store.getSession(sid) ?? <String, dynamic>{'id': sid};
    await _store.upsertSession(
      LocalSessionWrite(
        id: sid,
        payload: <String, dynamic>{...session, 'paymentStatus': 'APPROVED'},
        paymentStatus: 'APPROVED',
      ),
    );
  }

  Future<String> recordPrintJob({
    required String sessionId,
    required String imageUrl,
    String? printSize,
    int copies = 1,
  }) async {
    final sid = sessionId.trim();
    if (sid.isEmpty) {
      throw ArgumentError(_sessionIdRequired);
    }
    final id = _newId();
    await _store.upsertPrintJob(
      id: id,
      sessionId: sid,
      payload: <String, dynamic>{
        'id': id,
        'sessionId': sid,
        'imageUrl': imageUrl,
        'printSize': printSize ?? 's4x6',
        'copies': copies < 1 ? 1 : copies,
        'status': 'COMPLETED',
      },
    );
    return id;
  }

  Future<LocalReceiptIssue> issueReceipt({
    required String sessionId,
    String? kioskCode,
    required int amount,
    String? paymentMode,
  }) async {
    final sid = sessionId.trim();
    if (sid.isEmpty) {
      throw ArgumentError(_sessionIdRequired);
    }
    final existing = await _store.findReceiptForSession(sid);
    if (existing != null) {
      return _issueFromRow(existing);
    }
    final mode = await _modeForSession(sid, paymentMode);
    final rupees = amount < 0 ? 0 : amount;
    final issuedAt = _now();
    final number = await _store.allocateInvoiceNumber(
      kioskCode: kioskCode ?? '',
      at: issuedAt,
    );
    final id = _newId();
    final json = <String, dynamic>{
      'id': id,
      'sessionId': sid,
      'receiptNumber': number,
      'amount': rupees,
      'currency': 'INR',
      'paymentMode': mode,
      'issuedAt': issuedAt.toIso8601String(),
    };
    await _store.upsertReceipt(
      id: id,
      sessionId: sid,
      receiptNumber: number,
      payload: json,
    );
    final pdf = await buildLocalReceiptPdf(
      receiptNumber: number,
      amount: rupees,
      paymentMode: mode,
      kioskCode: kioskCode ?? '',
      issuedAt: issuedAt,
    );
    final file = await _store.saveReceiptPdf(id, pdf);
    if (file != null) {
      json['pdfPath'] = file.path;
      await _store.upsertReceipt(
        id: id,
        sessionId: sid,
        receiptNumber: number,
        payload: json,
      );
    }
    return LocalReceiptIssue(
      id: id,
      receiptNumber: number,
      json: json,
      pdfPath: file?.path,
    );
  }

  Future<LocalReceiptIssue> _issueFromRow(LocalEntityRow row) async {
    final number = row.receiptNumber ??
        (row.payload['receiptNumber'] as String? ?? '');
    return LocalReceiptIssue(
      id: row.id,
      receiptNumber: number,
      json: Map<String, dynamic>.from(row.payload),
      pdfPath: row.payload['pdfPath'] as String?,
    );
  }

  Future<String> _modeForSession(String sessionId, String? paymentMode) async {
    if (paymentMode != null && paymentMode.trim().isNotEmpty) {
      return _requireMode(paymentMode);
    }
    final payments = await _store.paymentsForSession(sessionId);
    for (final row in payments.reversed) {
      final raw = row.payload['paymentMode']?.toString();
      final parsed = PaymentMode.tryParse(raw);
      if (parsed != null) return parsed.apiValue;
    }
    return PaymentMode.cash.apiValue;
  }

  String _requireMode(String paymentMode) {
    final parsed = PaymentMode.tryParse(paymentMode);
    if (parsed == null) {
      throw ArgumentError('paymentMode is required');
    }
    return parsed.apiValue;
  }
}

/// Fly first; cash/complimentary still settle on the kiosk when WAN is down.
Future<bool> settleApprovedPayment({
  required Future<void> Function() approveOnFly,
  required LocalKioskStore store,
  required String paymentId,
  required String sessionId,
  required String paymentMode,
  required int amount,
}) async {
  try {
    await approveOnFly();
  } catch (e) {
    final mode = PaymentMode.tryParse(paymentMode);
    final canOffline = mode == PaymentMode.cash ||
        mode == PaymentMode.complimentary;
    if (!canOffline || !isWanDownSessionError(e)) {
      rethrow;
    }
    await LocalKioskSettlement(store: store).recordApprovedPayment(
      paymentId: paymentId,
      sessionId: sessionId,
      amount: amount,
      paymentMode: paymentMode,
    );
    return true;
  }
  await LocalKioskSettlement(store: store).recordApprovedPayment(
    paymentId: paymentId,
    sessionId: sessionId,
    amount: amount,
    paymentMode: paymentMode,
  );
  return false;
}
