/// Kiosk print progress presentation (no hardware % — milestone + time estimate).
library;

/// Lifecycle phases for a silent LAN print run.
enum PrintProgressPhase {
  idle,
  preparing,
  sending,
  finishing,
  complete,
  failed,
  skipped,
}

/// Immutable snapshot for QR-share print status UI.
class PrintProgressSnapshot {
  const PrintProgressSnapshot({
    this.phase = PrintProgressPhase.idle,
    this.currentPage = 0,
    this.totalPages = 0,
    this.percent = 0,
    this.errorMessage,
  });

  final PrintProgressPhase phase;
  final int currentPage;
  final int totalPages;
  final int percent;
  final String? errorMessage;

  bool get isActive =>
      phase == PrintProgressPhase.preparing ||
      phase == PrintProgressPhase.sending ||
      phase == PrintProgressPhase.finishing;

  bool get isComplete => phase == PrintProgressPhase.complete;

  bool get isFailed => phase == PrintProgressPhase.failed;

  PrintProgressSnapshot copyWith({
    PrintProgressPhase? phase,
    int? currentPage,
    int? totalPages,
    int? percent,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PrintProgressSnapshot(
      phase: phase ?? this.phase,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      percent: percent ?? this.percent,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Estimated physical print time per page after the HTTP POST succeeds.
const Duration kPrintFinishingEstimatePerPage = Duration(seconds: 20);

/// Minimum time to show the finishing animation so the bar does not flash.
const Duration kPrintFinishingMinimumDisplay = Duration(seconds: 4);

/// Percent slice owned by each page when [totalPages] > 0.
double pageSlicePercent(int totalPages) {
  if (totalPages <= 0) return 100;
  return 100 / totalPages;
}

/// Percent at the start of [pageIndex] (0-based) for [totalPages] images.
int pageStartPercent(int pageIndex, int totalPages) {
  if (totalPages <= 0) return 0;
  final slice = pageSlicePercent(totalPages);
  return (pageIndex * slice).round().clamp(0, 100);
}

/// Milestone percent within a page slice.
int milestonePercent({
  required int pageIndex,
  required int totalPages,
  required double fractionWithinPage,
}) {
  if (totalPages <= 0) return 0;
  final slice = pageSlicePercent(totalPages);
  final start = pageIndex * slice;
  final value = start + slice * fractionWithinPage.clamp(0.0, 1.0);
  return value.round().clamp(0, 100);
}

/// Preparing milestone — start of page slice + small bump.
int preparingPercent(int pageIndex, int totalPages) {
  return milestonePercent(
    pageIndex: pageIndex,
    totalPages: totalPages,
    fractionWithinPage: 0.08,
  );
}

/// Sending milestone — mid slice while HTTP POST is in flight.
int sendingPercent(int pageIndex, int totalPages) {
  return milestonePercent(
    pageIndex: pageIndex,
    totalPages: totalPages,
    fractionWithinPage: 0.38,
  );
}

/// Finishing percent from elapsed time after POST (caps below 100 until all pages done).
int finishingPercent({
  required int pageIndex,
  required int totalPages,
  required Duration elapsed,
  Duration estimatePerPage = kPrintFinishingEstimatePerPage,
}) {
  if (totalPages <= 0) return 0;
  final slice = pageSlicePercent(totalPages);
  final start = pageIndex * slice;
  final t = elapsed.inMilliseconds / estimatePerPage.inMilliseconds;
  final fraction = (0.42 + t * 0.53).clamp(0.42, 0.95);
  final value = start + slice * fraction;
  return value.round().clamp(0, 99);
}

/// Final percent when every page has finished.
int allPagesCompletePercent(int totalPages) => 100;

/// Footer label on the right side of the progress card.
String printProgressFooterRightLabel(PrintProgressSnapshot snapshot) {
  if (snapshot.isFailed) return 'Failed';
  if (snapshot.isComplete) return 'Done';
  if (snapshot.isActive) return 'Printing…';
  return '';
}

/// "Page X of Y" line; empty when no pages yet.
String printProgressPageLabel(PrintProgressSnapshot snapshot) {
  if (snapshot.totalPages <= 0) return '';
  final page = snapshot.currentPage.clamp(1, snapshot.totalPages);
  return 'Page $page of ${snapshot.totalPages}';
}
