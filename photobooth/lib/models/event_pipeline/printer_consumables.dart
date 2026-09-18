/// What the queue should do about a printer status code.
enum PrinterReadiness {
  /// Idle, printing, or status unreadable over a live USB link — go ahead.
  ready,

  /// Transient and self-clearing: cooling, standby. Retry with backoff.
  busy,

  /// Needs a human — ribbon, paper, jam, cover. **Pause the kind.**
  ///
  /// Pausing rather than retrying is the whole point: eight attempts against an
  /// empty printer would mark every queued photo failed, turning a two-minute
  /// media change into a wrecked event.
  needsAttention,

  /// The printer is fine; this job's data is not. Fail the one job.
  badJob,

  /// No printer reachable at all.
  offline,

  /// A printer **is** on the USB bus, but the app has not opened it.
  ///
  /// Distinct from [offline] because the two need opposite responses: offline
  /// means go and find a cable, this means tap Allow on a dialog. Reporting it
  /// as "not connected" sends an operator hunting for a hardware fault that is
  /// not there — which is exactly what happened after a reinstall, since
  /// uninstalling revokes the USB permission grant.
  needsPermission,
}

/// A decoded DNP status reading.
///
/// The codes come from `DnpUsbPrinter.printerStatusMessage` and are already
/// surfaced by the existing `getPrinterStatus` channel method — this classifies
/// them into a queue action rather than re-deriving them.
class PrinterConsumables {
  const PrinterConsumables({
    required this.code,
    required this.readiness,
    this.label,
    this.name,
  });

  final int code;
  final PrinterReadiness readiness;
  final String? label;
  final String? name;

  static const PrinterConsumables unknown = PrinterConsumables(
    code: -1,
    readiness: PrinterReadiness.ready,
    label: 'Connected — status unreadable',
  );

  static const PrinterConsumables offline = PrinterConsumables(
    code: -2,
    readiness: PrinterReadiness.offline,
    label: 'No printer connected',
  );

  /// Present on USB, not yet opened by this install.
  static const PrinterConsumables needsPermission = PrinterConsumables(
    code: -3,
    readiness: PrinterReadiness.needsPermission,
    label: 'Printer found — needs USB permission',
  );

  bool get canPrint => readiness == PrinterReadiness.ready;
  bool get shouldPause => readiness == PrinterReadiness.needsAttention;

  /// Operator-facing reason, e.g. "Ribbon end — replace ribbon".
  String get reason => label ?? 'Printer error ($code)';

  // Codes DnpUsbPrinter decodes. Named so the intent is readable at the call site.
  static const int coverOpen = 1000;
  static const int scrapBoxMissing = 1010;
  static const int paperEnd = 1100;
  static const int ribbonEnd = 1200;
  static const int paperJam = 1300;
  static const int ribbonError = 1400;
  static const int sizeMismatch = 1500;
  static const int printDataError = 1600;

  /// Faults a person has to clear before any job can run.
  static const Set<int> attentionCodes = <int>{
    coverOpen,
    scrapBoxMissing,
    paperEnd,
    ribbonEnd,
    paperJam,
    ribbonError,
    sizeMismatch,
  };

  static PrinterReadiness classify(int code) {
    // -1 means the USB link is up but the status query failed, which some TV
    // hosts do routinely. DnpUsbPrinter treats that as printable, so do we.
    if (code == -1 || code == 0 || code == 1) return PrinterReadiness.ready;
    if (code == 500 || code == 510 || code == 900) return PrinterReadiness.busy;
    if (attentionCodes.contains(code)) return PrinterReadiness.needsAttention;
    // A data error is this job's fault, not the printer's. Pausing the whole
    // queue for one malformed image would stall the event behind one photo.
    if (code == printDataError) return PrinterReadiness.badJob;
    // Anything unrecognised in the error range needs a look before more paper
    // is spent on it.
    if (code >= 1000) return PrinterReadiness.needsAttention;
    return PrinterReadiness.ready;
  }

  static PrinterConsumables fromStatusMap(Map<Object?, Object?>? map) {
    if (map == null) return offline;
    final code = _int(map['status']) ?? -1;
    return PrinterConsumables(
      code: code,
      readiness: classify(code),
      label: map['statusLabel'] as String?,
      name: map['name'] as String?,
    );
  }

  static int? _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }
}
