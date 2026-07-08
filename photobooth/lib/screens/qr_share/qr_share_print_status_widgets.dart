import 'package:flutter/material.dart';

import '../../utils/app_strings.dart';
import '../../utils/print_progress_helpers.dart';

/// Print status card on the QR share screen (mock: progress bar + page count).
class QrSharePrintStatusCard extends StatelessWidget {
  const QrSharePrintStatusCard({
    super.key,
    required this.progress,
  });

  final PrintProgressSnapshot progress;

  @override
  Widget build(BuildContext context) {
    if (progress.phase == PrintProgressPhase.idle ||
        progress.phase == PrintProgressPhase.skipped) {
      return const SizedBox.shrink();
    }

    final isComplete = progress.isComplete;
    final isFailed = progress.isFailed;
    final title = isComplete
        ? AppStrings.printProgressTitleComplete
        : isFailed
            ? AppStrings.printProgressTitleFailed
            : AppStrings.printProgressTitleActive;
    final subtitle = isComplete
        ? AppStrings.printProgressSubtitleComplete
        : isFailed
            ? (progress.errorMessage ?? AppStrings.printProgressSubtitleFailed)
            : AppStrings.printProgressSubtitleActive;
    final percent = progress.percent.clamp(0, 100);
    final pageLabel = printProgressPageLabel(progress);
    final footerRight = printProgressFooterRightLabel(progress);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isComplete
                    ? Icons.check_circle_outline
                    : isFailed
                        ? Icons.error_outline
                        : Icons.print_outlined,
                color: isFailed
                    ? Colors.red.shade300
                    : Colors.white.withValues(alpha: 0.9),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: Colors.white.withValues(alpha: 0.12)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: percent / 100,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF22D3EE),
                            Color(0xFFFBBF24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (pageLabel.isNotEmpty || footerRight.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (pageLabel.isNotEmpty)
                  Text(
                    pageLabel,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 12,
                    ),
                  ),
                const Spacer(),
                if (footerRight.isNotEmpty)
                  Text(
                    footerRight,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
