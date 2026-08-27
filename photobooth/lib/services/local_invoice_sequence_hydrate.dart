import '../models/kiosk_info_model.dart';
import 'local_kiosk_store.dart';

/// Keep the on-device invoice counter at/above Fly's high-water for this booth.
Future<void> hydrateLocalInvoiceSequenceFromKiosk({
  required KioskInfoModel kiosk,
  LocalKioskStore? store,
}) async {
  final seq = kiosk.invoiceLastSeq;
  if (seq == null || seq < 1) return;
  final ledger = store ?? LocalKioskStore.instance;
  if (ledger == null) return;
  await ledger.ensureInvoiceSequenceAtLeast(
    kioskCode: kiosk.code,
    lastSeq: seq,
  );
}
