import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/print_progress_helpers.dart';

void main() {
  group('PrintProgressSnapshot', () {
    test('copyWith and active flags', () {
      const base = PrintProgressSnapshot(
        phase: PrintProgressPhase.sending,
        currentPage: 1,
        totalPages: 2,
        percent: 25,
        errorMessage: 'x',
      );
      expect(base.isActive, isTrue);
      expect(base.isComplete, isFalse);
      expect(base.isFailed, isFalse);

      final cleared = base.copyWith(clearError: true, percent: 30);
      expect(cleared.errorMessage, isNull);
      expect(cleared.percent, 30);

      final updatedError = base.copyWith(errorMessage: 'retry');
      expect(updatedError.errorMessage, 'retry');
      expect(updatedError.percent, base.percent);

      final phaseOnly = base.copyWith(phase: PrintProgressPhase.finishing);
      expect(phaseOnly.phase, PrintProgressPhase.finishing);
      expect(phaseOnly.percent, base.percent);

      const complete = PrintProgressSnapshot(phase: PrintProgressPhase.complete);
      expect(complete.isComplete, isTrue);

      const failed = PrintProgressSnapshot(phase: PrintProgressPhase.failed);
      expect(failed.isFailed, isTrue);
    });
  });

  group('edge cases', () {
    test('zero total pages returns safe defaults', () {
      expect(pageSlicePercent(0), 100);
      expect(pageStartPercent(0, 0), 0);
      expect(
        milestonePercent(pageIndex: 0, totalPages: 0, fractionWithinPage: 0.5),
        0,
      );
      expect(
        finishingPercent(
          pageIndex: 0,
          totalPages: 0,
          elapsed: Duration.zero,
        ),
        0,
      );
    });
  });

  group('pageSlicePercent', () {
    test('returns 100 for single page', () {
      expect(pageSlicePercent(1), 100);
    });

    test('splits evenly for multiple pages', () {
      expect(pageSlicePercent(2), 50);
      expect(pageSlicePercent(4), 25);
    });
  });

  group('milestonePercent', () {
    test('page 1 of 1 preparing is below sending', () {
      final prep = preparingPercent(0, 1);
      final send = sendingPercent(0, 1);
      expect(prep, lessThan(send));
      expect(prep, greaterThan(0));
    });

    test('page 2 of 2 starts above page 1 sending', () {
      expect(
        pageStartPercent(1, 2),
        greaterThan(sendingPercent(0, 2)),
      );
    });
  });

  group('finishingPercent', () {
    test('increases with elapsed time within page slice', () {
      final early = finishingPercent(
        pageIndex: 0,
        totalPages: 1,
        elapsed: const Duration(seconds: 2),
      );
      final later = finishingPercent(
        pageIndex: 0,
        totalPages: 1,
        elapsed: const Duration(seconds: 15),
      );
      expect(later, greaterThan(early));
      expect(later, lessThan(100));
    });

    test('caps below 100 until all pages complete helper', () {
      expect(allPagesCompletePercent(1), 100);
      expect(
        finishingPercent(
          pageIndex: 0,
          totalPages: 1,
          elapsed: const Duration(seconds: 60),
        ),
        lessThan(100),
      );
    });
  });

  group('pageStartPercent', () {
    test('returns 0 for first page', () {
      expect(pageStartPercent(0, 2), 0);
      expect(pageStartPercent(0, 1), 0);
    });

    test('returns slice offset for later pages', () {
      expect(pageStartPercent(1, 2), 50);
    });
  });

  group('printProgressPageLabel', () {
    test('empty when no pages', () {
      expect(
        printProgressPageLabel(const PrintProgressSnapshot()),
        isEmpty,
      );
    });
  });

  group('shouldApplyPrintFailure', () {
    test('allows failure before HTTP POST completes', () {
      expect(
        shouldApplyPrintFailure(
          const PrintProgressSnapshot(phase: PrintProgressPhase.preparing),
        ),
        isTrue,
      );
      expect(
        shouldApplyPrintFailure(
          const PrintProgressSnapshot(phase: PrintProgressPhase.sending),
        ),
        isTrue,
      );
    });

    test('blocks failure after POST accepted or run complete', () {
      expect(
        shouldApplyPrintFailure(
          const PrintProgressSnapshot(phase: PrintProgressPhase.finishing),
        ),
        isFalse,
      );
      expect(
        shouldApplyPrintFailure(
          const PrintProgressSnapshot(phase: PrintProgressPhase.complete),
        ),
        isFalse,
      );
    });
  });

  group('labels', () {
    test('footer and page labels follow phase', () {
      const active = PrintProgressSnapshot(
        phase: PrintProgressPhase.sending,
        currentPage: 1,
        totalPages: 2,
        percent: 30,
      );
      expect(printProgressFooterRightLabel(active), 'Printing…');
      expect(printProgressPageLabel(active), 'Page 1 of 2');

      const done = PrintProgressSnapshot(
        phase: PrintProgressPhase.complete,
        currentPage: 2,
        totalPages: 2,
        percent: 100,
      );
      expect(printProgressFooterRightLabel(done), 'Done');

      const failed = PrintProgressSnapshot(
        phase: PrintProgressPhase.failed,
        currentPage: 1,
        totalPages: 1,
        percent: 40,
      );
      expect(printProgressFooterRightLabel(failed), 'Failed');

      expect(printProgressFooterRightLabel(const PrintProgressSnapshot()), '');
    });
  });
}
