import 'package:flutter/material.dart';

import '../../models/staff_dashboard_models.dart';
import '../../utils/app_strings.dart';
import 'staff_dashboard_helpers.dart';
import 'staff_theme_colors.dart';

class StaffShiftBadge extends StatelessWidget {
  const StaffShiftBadge({super.key, required this.onShift});

  final bool onShift;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: onShift
            ? StaffThemeColors.success.withValues(alpha: 0.2)
            : StaffThemeColors.chipIdleBg(context),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: onShift
              ? StaffThemeColors.success.withValues(alpha: 0.6)
              : StaffThemeColors.chipIdleBorder(context),
        ),
      ),
      child: Text(
        onShift ? AppStrings.staffOnShift : AppStrings.staffOffShift,
        style: TextStyle(
          color: onShift ? StaffThemeColors.success : StaffThemeColors.muted(context),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class StaffDashboardErrorBanner extends StatelessWidget {
  const StaffDashboardErrorBanner({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.red.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.red)),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

class StaffDayPickerCard extends StatelessWidget {
  const StaffDayPickerCard({
    super.key,
    required this.selectedDate,
    required this.isToday,
    required this.onPickDate,
    required this.onToday,
    this.timezone,
  });

  final String selectedDate;
  final String? timezone;
  final bool isToday;
  final Future<void> Function(String isoDate) onPickDate;
  final Future<void> Function() onToday;

  @override
  Widget build(BuildContext context) {
    return _StaffCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.staffDayDetailsLabel,
            style: TextStyle(
              color: StaffThemeColors.muted(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final parts = selectedDate.split('-');
                  final initial = parts.length == 3
                      ? DateTime(
                          int.parse(parts[0]),
                          int.parse(parts[1]),
                          int.parse(parts[2]),
                        )
                      : DateTime.now();
                  final todayParts =
                      StaffDashboardHelpers.todayLocalDate().split('-');
                  final maxDate = DateTime(
                    int.parse(todayParts[0]),
                    int.parse(todayParts[1]),
                    int.parse(todayParts[2]),
                  );
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initial.isAfter(maxDate) ? maxDate : initial,
                    firstDate: DateTime(2024),
                    lastDate: maxDate,
                  );
                  if (picked == null) return;
                  final y = picked.year.toString().padLeft(4, '0');
                  final m = picked.month.toString().padLeft(2, '0');
                  final d = picked.day.toString().padLeft(2, '0');
                  await onPickDate('$y-$m-$d');
                },
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(selectedDate),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: isToday ? null : () => onToday(),
                child: const Text(AppStrings.staffTodayButton),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            [
              AppStrings.staffShowingDay(
                StaffDashboardHelpers.formatDayLabel(selectedDate),
              ),
              if ((timezone ?? '').trim().isNotEmpty) timezone!.trim(),
            ].where((e) => e.isNotEmpty).join(' · '),
            style: TextStyle(
              color: StaffThemeColors.mutedSoft(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class StaffDayKpiGrid extends StatelessWidget {
  const StaffDayKpiGrid({super.key, required this.summary});

  final StaffDaySummary? summary;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: [
        _KpiTile(
          label: AppStrings.staffKpiSessions,
          value: summary == null ? '—' : '${summary!.sessions}',
          hint: AppStrings.staffKpiSessionsHint,
        ),
        _KpiTile(
          label: AppStrings.staffKpiPrints,
          value: summary == null ? '—' : '${summary!.prints}',
          hint: AppStrings.staffKpiPrintsHint,
        ),
        _KpiTile(
          label: AppStrings.staffKpiPayments,
          value: summary == null ? '—' : '${summary!.payments.totalCount}',
          hint: AppStrings.staffKpiPaymentsHint,
        ),
        _KpiTile(
          label: AppStrings.staffKpiRevenue,
          value: summary == null
              ? '—'
              : StaffDashboardHelpers.formatInr(summary!.payments.totalAmount),
          hint: AppStrings.staffKpiRevenueHint,
        ),
      ],
    );
  }
}

class StaffModeSplitRow extends StatelessWidget {
  const StaffModeSplitRow({super.key, required this.payments});

  final StaffDayPaymentsSummary? payments;

  @override
  Widget build(BuildContext context) {
    final upi = payments?.upi ?? const StaffModeBucket(count: 0, amount: 0);
    final cash = payments?.cash ?? const StaffModeBucket(count: 0, amount: 0);
    final comp =
        payments?.complimentary ?? const StaffModeBucket(count: 0, amount: 0);
    return Row(
      children: [
        Expanded(
          child: _ModeTile(
            label: AppStrings.staffModeUpi,
            amount: upi.amount,
            count: upi.count,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ModeTile(
            label: AppStrings.staffModeCash,
            amount: cash.amount,
            count: cash.count,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ModeTile(
            label: AppStrings.staffModeComplimentary,
            amount: comp.amount,
            count: comp.count,
          ),
        ),
      ],
    );
  }
}

class StaffShiftRegisterStatusRow extends StatelessWidget {
  const StaffShiftRegisterStatusRow({super.key, required this.session});

  final StaffOpsSession? session;

  @override
  Widget build(BuildContext context) {
    final checkedIn = session?.isCheckedIn == true;
    final open = session?.hasOpenRegister == true;
    final elapsed = session?.activeAttendance?.checkInTime;
    final openedAt = session?.openRegister?.openedAt;
    return Row(
      children: [
        Expanded(
          child: _StaffCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.staffStatusLabel,
                  style: TextStyle(color: StaffThemeColors.muted(context)),
                ),
                const SizedBox(height: 6),
                Text(
                  checkedIn
                      ? AppStrings.staffCheckedIn
                      : AppStrings.staffOffShift,
                  style: TextStyle(
                    color: checkedIn
                        ? StaffThemeColors.success
                        : StaffThemeColors.muted(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (checkedIn && elapsed != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.staffElapsedLine(
                      StaffDashboardHelpers.formatElapsed(elapsed),
                    ),
                    style: TextStyle(
                      color: StaffThemeColors.muted(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StaffCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.staffRegisterLabel,
                  style: TextStyle(color: StaffThemeColors.muted(context)),
                ),
                const SizedBox(height: 6),
                Text(
                  open
                      ? AppStrings.staffRegisterOpen
                      : AppStrings.staffRegisterClosed,
                  style: TextStyle(
                    color: open ? StaffThemeColors.info : StaffThemeColors.muted(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (open && openedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.staffRegisterSince(
                      TimeOfDay.fromDateTime(openedAt.toLocal()).format(context),
                    ),
                    style: TextStyle(
                      color: StaffThemeColors.muted(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class StaffAttendanceCard extends StatelessWidget {
  const StaffAttendanceCard({
    super.key,
    required this.session,
    required this.busy,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  final StaffOpsSession? session;
  final bool busy;
  final Future<void> Function() onCheckIn;
  final Future<void> Function() onCheckOut;

  @override
  Widget build(BuildContext context) {
    final checkedIn = session?.isCheckedIn == true;
    final hasRegister = session?.hasOpenRegister == true;
    return _StaffCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.staffAttendanceTitle,
            style: TextStyle(
              color: StaffThemeColors.title(context),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.staffAttendanceSubtitle,
            style: TextStyle(color: StaffThemeColors.muted(context)),
          ),
          const SizedBox(height: 12),
          if (!checkedIn)
            FilledButton.icon(
              onPressed: busy ? null : () => onCheckIn(),
              icon: const Icon(Icons.login),
              label: Text(
                busy
                    ? AppStrings.staffCheckingIn
                    : AppStrings.staffCheckIn,
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: busy || hasRegister ? null : () => onCheckOut(),
              icon: const Icon(Icons.logout),
              label: Text(
                busy
                    ? AppStrings.staffCheckingOut
                    : AppStrings.staffCheckOut,
              ),
            ),
          if (checkedIn && hasRegister) ...[
            const SizedBox(height: 8),
            const Text(
              AppStrings.staffCloseRegisterBeforeCheckout,
              style: TextStyle(color: StaffThemeColors.warning, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class StaffRegisterCard extends StatelessWidget {
  const StaffRegisterCard({
    super.key,
    required this.session,
    required this.busy,
    required this.onOpen,
    required this.onClose,
  });

  final StaffOpsSession? session;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final checkedIn = session?.isCheckedIn == true;
    final open = session?.hasOpenRegister == true;
    final hasKiosk = session?.staff.hasKiosk == true;
    final canOpen = checkedIn && hasKiosk && !busy;
    return _StaffCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.staffCashRegisterTitle,
            style: TextStyle(
              color: StaffThemeColors.title(context),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.staffCashRegisterSubtitle,
            style: TextStyle(color: StaffThemeColors.muted(context)),
          ),
          const SizedBox(height: 12),
          if (!open)
            FilledButton.icon(
              onPressed: canOpen ? onOpen : null,
              icon: const Icon(Icons.point_of_sale),
              label: const Text(AppStrings.staffOpenRegister),
            )
          else
            FilledButton.icon(
              onPressed: busy ? null : onClose,
              icon: const Icon(Icons.lock),
              label: const Text(AppStrings.staffCloseRegister),
            ),
          if (!checkedIn) ...[
            const SizedBox(height: 8),
            Text(
              AppStrings.staffCheckInBeforeRegister,
              style: TextStyle(
                color: StaffThemeColors.muted(context),
                fontSize: 12,
              ),
            ),
          ] else if (!hasKiosk && !open) ...[
            const SizedBox(height: 8),
            const Text(
              AppStrings.staffNoKioskForRegister,
              style: TextStyle(
                color: StaffThemeColors.warning,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class StaffPerformanceCard extends StatelessWidget {
  const StaffPerformanceCard({super.key, required this.stats});

  final StaffPerformanceStats stats;

  @override
  Widget build(BuildContext context) {
    return _StaffCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.staffPerformanceTitle,
            style: TextStyle(
              color: StaffThemeColors.title(context),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _PerfChip(
                label: AppStrings.staffPerfReceipts,
                value: '${stats.totalReceipts}',
              ),
              _PerfChip(
                label: AppStrings.staffPerfPrints,
                value: '${stats.totalPrints}',
              ),
              _PerfChip(
                label: AppStrings.staffPerfRevenue,
                value: StaffDashboardHelpers.formatInr(stats.totalRevenue),
              ),
              _PerfChip(
                label: AppStrings.staffPerfHours,
                value: stats.totalHours.toStringAsFixed(1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: StaffThemeColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StaffThemeColors.cardBorder(context)),
      ),
      child: child,
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.hint,
  });

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return _StaffCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: StaffThemeColors.muted(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: StaffThemeColors.title(context),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            style: TextStyle(
              color: StaffThemeColors.mutedSoft(context),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.label,
    required this.amount,
    required this.count,
  });

  final String label;
  final int amount;
  final int count;

  @override
  Widget build(BuildContext context) {
    return _StaffCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: StaffThemeColors.muted(context)),
          ),
          const SizedBox(height: 6),
          Text(
            StaffDashboardHelpers.formatInr(amount),
            style: TextStyle(
              color: StaffThemeColors.title(context),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            AppStrings.staffPaymentCount(count),
            style: TextStyle(
              color: StaffThemeColors.mutedSoft(context),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _PerfChip extends StatelessWidget {
  const _PerfChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: StaffThemeColors.mutedSoft(context),
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: StaffThemeColors.title(context),
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}
