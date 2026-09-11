import 'event_pipeline_settings.dart';
import 'event_frame.dart';
import 'printer_consumables.dart';

/// How a readiness row reads at a glance.
enum ReadinessTone {
  /// Ready. Nothing to do.
  ok,

  /// Works, but not the way the event was configured. Worth a look now,
  /// because it will be worse later.
  warn,

  /// Something the event needs is not there. Blocks the action it gates.
  blocked,
}

/// Which readiness row this is, so the UI can key off it without matching text.
enum ReadinessKind { queue, sync, camera, printer, frames, ai, storage }

/// One line of the hub's readiness block.
class ReadinessRow {
  const ReadinessRow({
    required this.kind,
    required this.label,
    required this.tone,
    required this.detail,
    this.explanation,
  });

  final ReadinessKind kind;

  /// Left column, e.g. `Camera`.
  final String label;

  final ReadinessTone tone;

  /// Right column — the short state, e.g. `Canon EOS R · PTP`.
  final String detail;

  /// What to do about it, shown when the operator taps an amber or red row.
  ///
  /// Null on a green row: there is nothing to explain, and making every row
  /// tappable teaches an operator that tapping does nothing.
  final String? explanation;

  bool get isActionable => explanation != null && tone != ReadinessTone.ok;
}

/// Everything the readiness block is derived from.
///
/// One input object rather than eight parameters, per the repo's `*Input`
/// convention for wide signatures.
class EventReadinessInput {
  const EventReadinessInput({
    required this.settings,
    required this.hasSyncedOnce,
    this.syncIsFresh = false,
    this.syncedAtMs,
    this.syncError,
    this.cameraName,
    this.printer,
    this.frames,
    this.freeBytes,
    this.online = true,
    this.queuePaused = false,
    this.inFlight = 0,
  });

  final EventPipelineSettings settings;

  /// Whether this device has ever had settings for this event.
  final bool hasSyncedOnce;

  /// Whether they came from ZenAI in this session rather than the cache.
  final bool syncIsFresh;

  final int? syncedAtMs;
  final String? syncError;

  /// Model of the attached camera, or null when nothing is on the bus.
  final String? cameraName;

  final PrinterConsumables? printer;
  final FrameCacheStatus? frames;

  /// Free space where derivatives are written, or null when unreadable.
  final int? freeBytes;

  /// Whether the device can currently reach ZenAI. Only matters to AI, which
  /// is the one step that cannot run locally.
  final bool online;

  /// Whether the operator has held every stage.
  final bool queuePaused;

  /// How many photos are mid-chain right now.
  final int inFlight;
}

/// The whole readiness block plus the gates it drives.
class EventReadinessReport {
  const EventReadinessReport({
    required this.rows,
    required this.canImport,
    required this.canCapture,
    this.importBlockedReason,
    this.captureBlockedReason,
  });

  final List<ReadinessRow> rows;

  final bool canImport;
  final bool canCapture;

  /// Shown **on** the disabled button rather than as a silent grey-out, so an
  /// operator is never left guessing why a tap did nothing (spec §3A).
  final String? importBlockedReason;
  final String? captureBlockedReason;

  bool get isReady => rows.every((r) => r.tone == ReadinessTone.ok);

  bool get hasBlocker => rows.any((r) => r.tone == ReadinessTone.blocked);

  /// The banner over the block: what an operator reads first.
  String get headline {
    if (hasBlocker) return 'NOT READY';
    if (!isReady) return 'READY — WITH WARNINGS';
    return 'READY TO RUN';
  }
}

/// Turns the state of the device into the hub's readiness block.
///
/// Events go wrong in one specific way: something was not ready, and nobody
/// found out until a hundred photos in. Each of these is trivially detectable
/// before it matters and invisible afterwards, which is why they belong on the
/// landing screen (spec §4).
///
/// Pure and synchronous on purpose — every input is gathered by the view model,
/// so the rules themselves are testable without a device, a printer or a card.
abstract final class EventReadiness {
  /// Below this, derivatives will not last the event.
  static const int lowStorageBytes = 4 * 1024 * 1024 * 1024;

  /// Below this, importing would fill the disk mid-run.
  static const int blockedStorageBytes = 1024 * 1024 * 1024;

  static const String waitingForSettings = 'Waiting for event settings';

  static EventReadinessReport evaluate(EventReadinessInput input) {
    final rows = <ReadinessRow>[
      // First, because mid-event the operator's first question is whether work
      // is moving at all — and a paused queue looks identical to a stalled one
      // until something says so (spec §7).
      _queue(input),
      _sync(input),
      _camera(input),
      _printer(input),
      _frames(input),
      _ai(input),
      _storage(input),
    ];

    final storageBlocked = _isStorageBlocked(input.freeBytes);
    final cameraReady = (input.cameraName?.trim().isNotEmpty ?? false);

    // Order matters: the sync gate is named first because it is the one the
    // operator can act on immediately, and it is the reason in almost every
    // case at the start of an event.
    String? blocked;
    if (!input.hasSyncedOnce) {
      blocked = waitingForSettings;
    } else if (storageBlocked) {
      blocked = 'Not enough free space';
    }

    return EventReadinessReport(
      rows: rows,
      canImport: blocked == null,
      canCapture: blocked == null && cameraReady,
      importBlockedReason: blocked,
      captureBlockedReason: blocked ?? (cameraReady ? null : 'No camera connected'),
    );
  }

  static bool _isStorageBlocked(int? freeBytes) =>
      freeBytes != null && freeBytes < blockedStorageBytes;

  static ReadinessRow _queue(EventReadinessInput input) {
    if (input.queuePaused) {
      return const ReadinessRow(
        kind: ReadinessKind.queue,
        label: 'Queue',
        tone: ReadinessTone.warn,
        detail: 'Paused',
        explanation: 'You paused the queue, so nothing is being processed. '
            'Photos already imported are safe and keep their place. Resume it '
            'from the queue screen when you are ready.',
      );
    }
    if (input.inFlight > 0) {
      return ReadinessRow(
        kind: ReadinessKind.queue,
        label: 'Queue',
        tone: ReadinessTone.ok,
        detail: 'Processing · ${input.inFlight} in flight',
      );
    }
    return const ReadinessRow(
      kind: ReadinessKind.queue,
      label: 'Queue',
      tone: ReadinessTone.ok,
      detail: 'Idle — nothing waiting',
    );
  }

  static ReadinessRow _sync(EventReadinessInput input) {
    if (!input.hasSyncedOnce) {
      return ReadinessRow(
        kind: ReadinessKind.sync,
        label: 'Settings',
        tone: ReadinessTone.blocked,
        detail: 'Not synced',
        explanation: input.syncError ??
            'This device has never had settings for this event. Import and '
                'Capture stay off until it does — a photo with no chain frozen '
                'onto it would sit unprocessed. Tap to retry.',
      );
    }
    if (input.syncIsFresh) {
      return ReadinessRow(
        kind: ReadinessKind.sync,
        label: 'Settings',
        tone: ReadinessTone.ok,
        detail: 'Synced ${_clock(input.syncedAtMs)}',
      );
    }
    return ReadinessRow(
      kind: ReadinessKind.sync,
      label: 'Settings',
      tone: ReadinessTone.warn,
      detail: 'Using settings from ${_day(input.syncedAtMs)}',
      explanation: input.syncError ??
          'Could not reach ZenAI, so the event is running on the settings this '
              'device already had. Tap to sync again.',
    );
  }

  static ReadinessRow _camera(EventReadinessInput input) {
    final name = input.cameraName?.trim() ?? '';
    if (name.isEmpty) {
      return const ReadinessRow(
        kind: ReadinessKind.camera,
        label: 'Camera',
        tone: ReadinessTone.blocked,
        detail: 'Not connected',
        explanation: 'No camera on the USB bus, so Capture is off. Card import '
            'still works. Check the cable, and that the camera is on and not '
            'asleep.',
      );
    }
    return ReadinessRow(
      kind: ReadinessKind.camera,
      label: 'Camera',
      tone: ReadinessTone.ok,
      detail: name,
    );
  }

  static ReadinessRow _printer(EventReadinessInput input) {
    final printer = input.printer;
    if (printer == null || printer.readiness == PrinterReadiness.offline) {
      return const ReadinessRow(
        kind: ReadinessKind.printer,
        label: 'Printer',
        tone: ReadinessTone.blocked,
        detail: 'Not connected',
        explanation: 'Nothing will print until a printer is reachable. Photos '
            'still import and frame, and their prints queue up for when it is.',
      );
    }
    if (printer.readiness == PrinterReadiness.needsPermission) {
      return const ReadinessRow(
        kind: ReadinessKind.printer,
        label: 'Printer',
        tone: ReadinessTone.blocked,
        detail: 'Needs USB permission',
        explanation: 'The printer is plugged in, but this device has not been '
            'given permission to use it. Tap Allow below, then Allow again on '
            "Android's dialog. A reinstall clears that permission, so this is "
            'expected on a fresh install.',
      );
    }
    if (printer.shouldPause) {
      return ReadinessRow(
        kind: ReadinessKind.printer,
        label: 'Printer',
        tone: ReadinessTone.blocked,
        detail: printer.reason,
        explanation: 'The print queue is held rather than retried, so a media '
            'change does not mark every queued photo failed. It resumes on its '
            'own once the printer is ready.',
      );
    }
    return ReadinessRow(
      kind: ReadinessKind.printer,
      label: 'Printer',
      tone: ReadinessTone.ok,
      detail: '${printer.name ?? 'Connected'} · ${input.settings.printSize}',
    );
  }

  static ReadinessRow _frames(EventReadinessInput input) {
    if (!input.settings.frameEnabled) {
      return const ReadinessRow(
        kind: ReadinessKind.frames,
        label: 'Frames',
        tone: ReadinessTone.ok,
        detail: 'off for this event',
      );
    }
    final frames = input.frames;
    if (frames == null) {
      return const ReadinessRow(
        kind: ReadinessKind.frames,
        label: 'Frames',
        tone: ReadinessTone.warn,
        detail: 'Not checked yet',
        explanation: 'Frame artwork has not been checked. Tap to sync, which '
            'downloads it.',
      );
    }
    // This is the row that most needs explaining: it is silent until the event
    // goes offline, and then every single item defers.
    if (!frames.selectedIsCached) {
      return ReadinessRow(
        kind: ReadinessKind.frames,
        label: 'Frames',
        tone: ReadinessTone.blocked,
        detail: frames.isEmpty ? 'None cached' : 'Event frame missing',
        explanation: 'Framing is on but the artwork this event uses is not on '
            'the device, so framing cannot run once the link is gone. Sync '
            'while there is still signal.',
      );
    }
    if (!frames.allCached) {
      return ReadinessRow(
        kind: ReadinessKind.frames,
        label: 'Frames',
        tone: ReadinessTone.warn,
        detail: '${frames.cached} of ${frames.total} cached',
        explanation: 'The frame this event uses is on the device, so framing '
            'will run. Others in the catalogue are not.',
      );
    }
    return ReadinessRow(
      kind: ReadinessKind.frames,
      label: 'Frames',
      tone: ReadinessTone.ok,
      detail: '${frames.cached} cached',
    );
  }

  static ReadinessRow _ai(EventReadinessInput input) {
    final settings = input.settings;
    if (!settings.aiEnabled) {
      return const ReadinessRow(
        kind: ReadinessKind.ai,
        label: 'AI',
        tone: ReadinessTone.ok,
        detail: 'off for this event',
      );
    }
    if (!settings.canRunAi) {
      return const ReadinessRow(
        kind: ReadinessKind.ai,
        label: 'AI',
        tone: ReadinessTone.warn,
        detail: 'No theme set',
        explanation: 'AI is on for this event but no theme is chosen, so the '
            'step is skipped and photos go through unstyled. Set the theme on '
            'ZenAI and sync again.',
      );
    }
    if (!input.online) {
      return ReadinessRow(
        kind: ReadinessKind.ai,
        label: 'AI',
        tone: ReadinessTone.blocked,
        detail: 'Offline · theme ${settings.themeId}',
        explanation: 'AI is the one step that cannot run on the device. Jobs '
            'wait in the queue and run when the link comes back; nothing is '
            'lost while they wait.',
      );
    }
    return ReadinessRow(
      kind: ReadinessKind.ai,
      label: 'AI',
      tone: ReadinessTone.ok,
      detail: 'on · theme ${settings.themeId}',
    );
  }

  static ReadinessRow _storage(EventReadinessInput input) {
    final free = input.freeBytes;
    if (free == null) {
      return const ReadinessRow(
        kind: ReadinessKind.storage,
        label: 'Storage',
        tone: ReadinessTone.warn,
        detail: 'Unknown',
        explanation: 'Free space could not be read, so the import cannot warn '
            'before the disk fills.',
      );
    }
    final label = formatBytes(free);
    if (free < blockedStorageBytes) {
      return ReadinessRow(
        kind: ReadinessKind.storage,
        label: 'Storage',
        tone: ReadinessTone.blocked,
        detail: '$label free',
        explanation: 'Import is blocked below 1 GB. A 3,000-frame event is '
            'roughly 4 GB of derivatives, so clear finished events before '
            'starting this one.',
      );
    }
    if (free < lowStorageBytes) {
      return ReadinessRow(
        kind: ReadinessKind.storage,
        label: 'Storage',
        tone: ReadinessTone.warn,
        detail: '$label free',
        explanation: 'Under 4 GB. Enough to start, not enough for a full event '
            'at roughly 4 GB of derivatives per 3,000 frames.',
      );
    }
    return ReadinessRow(
      kind: ReadinessKind.storage,
      label: 'Storage',
      tone: ReadinessTone.ok,
      detail: '$label free',
    );
  }

  /// Whole GB below a terabyte — an operator is deciding whether to clear space,
  /// not auditing a disk.
  static String formatBytes(int bytes) {
    const gb = 1024 * 1024 * 1024;
    if (bytes >= gb) return '${(bytes / gb).round()} GB';
    const mb = 1024 * 1024;
    return '${(bytes / mb).round()} MB';
  }

  /// `09:12`, matching the hub mock.
  static String _clock(int? ms) {
    if (ms == null) return 'just now';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${_two(t.hour)}:${_two(t.minute)}';
  }

  /// `8 Sep` — a cached-settings row is about which *day*, not which minute.
  static String _day(int? ms) {
    if (ms == null) return 'an earlier session';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${t.day} ${_months[t.month - 1]}';
  }

  static String _two(int v) => v < 10 ? '0$v' : '$v';

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}
