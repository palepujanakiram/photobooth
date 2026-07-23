import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/staff_dashboard_models.dart';
import '../../services/staff_api_service.dart';
import '../../services/staff_session_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/exceptions.dart';
import '../../views/widgets/app_colors.dart';
import 'staff_auth_helpers.dart';
import 'staff_dashboard_helpers.dart';
import 'staff_dashboard_view_widgets.dart';
import 'staff_dashboard_viewmodel.dart';
import 'staff_payments_view.dart';
import 'staff_theme_colors.dart';
import 'staff_theme_shell.dart';

class _StaffApiGateway implements StaffDashboardGateway {
  _StaffApiGateway([StaffApiService? api]) : _api = api ?? StaffApiService();

  final StaffApiService _api;

  @override
  Future<StaffOpsSession> fetchStaffOpsSession() => _api.fetchStaffOpsSession();

  @override
  Future<StaffDaySummary> fetchDaySummary({required String date}) =>
      _api.fetchDaySummary(date: date);

  @override
  Future<StaffPerformanceStats?> fetchStaffStats(String staffId) =>
      _api.fetchStaffStats(staffId);

  @override
  Future<void> checkIn() => _api.checkIn();

  @override
  Future<void> checkOut() => _api.checkOut();

  @override
  Future<void> openRegister({required int openingFloat}) =>
      _api.openRegister(openingFloat: openingFloat);

  @override
  Future<void> closeRegister({
    required int closingFloat,
    required int actualAmount,
    String closingNotes = '',
  }) =>
      _api.closeRegister(
        closingFloat: closingFloat,
        actualAmount: actualAmount,
        closingNotes: closingNotes,
      );

  @override
  Future<void> logout() => _api.logout();
}

/// Staff ops dashboard — parity with web `/staff/dashboard`.
class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final StaffDashboardViewModel _vm;
  late final TabController _tabs;
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _vm = StaffDashboardViewModel(gateway: _StaffApiGateway());
    _tabs = TabController(length: 2, vsync: this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _vm.loadAll();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (StaffAuthHelpers.isAuthFailure(e)) {
        // Drop stale X-Staff-Token so login does not bounce straight back here.
        await StaffSessionManager().clear();
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppConstants.kRouteStaffLogin,
          (r) => false,
        );
        return;
      }
    } catch (_) {
      // Error surfaced via ViewModel.
    } finally {
      if (mounted) setState(() => _booting = false);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await _vm.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppConstants.kRouteStaffLogin,
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StaffThemeShell(
      child: Builder(
        builder: (context) {
          final appColors = AppColors.of(context);
          return ChangeNotifierProvider.value(
            value: _vm,
            child: Consumer<StaffDashboardViewModel>(
              builder: (context, vm, _) {
                final session = vm.session;
                return Scaffold(
                  backgroundColor: appColors.backgroundColor,
                  appBar: AppBar(
                    title: Text(
                      session?.staff.name.isNotEmpty == true
                          ? session!.staff.name
                          : AppStrings.staffDashboardTitle,
                    ),
                    actions: [
                      if (session != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Center(
                            child:
                                StaffShiftBadge(onShift: session.isCheckedIn),
                          ),
                        ),
                      const StaffThemeToggleButton(),
                      IconButton(
                        tooltip: AppStrings.staffRefreshTooltip,
                        onPressed: vm.loading || vm.actionBusy
                            ? null
                            : () => vm.refreshQuiet(),
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton(
                        tooltip: AppStrings.staffLogoutTooltip,
                        onPressed:
                            vm.loading || vm.actionBusy ? null : _logout,
                        icon: const Icon(Icons.logout),
                      ),
                    ],
                    bottom: TabBar(
                      controller: _tabs,
                      tabs: const [
                        Tab(text: AppStrings.staffTabOverview),
                        Tab(text: AppStrings.staffTabPayments),
                      ],
                    ),
                  ),
                  body: SafeArea(
                    child: _booting && session == null
                        ? const Center(child: CircularProgressIndicator())
                        : TabBarView(
                            controller: _tabs,
                            children: [
                              StaffDashboardOverviewTab(
                                onOpenRegister: () =>
                                    _showOpenRegisterDialog(context, vm),
                                onCloseRegister: () =>
                                    _showCloseRegisterDialog(context, vm),
                              ),
                              StaffPaymentsScreen(
                                embedded: true,
                                date: vm.selectedDate,
                                onAuthExpired: () {
                                  Navigator.of(context)
                                      .pushNamedAndRemoveUntil(
                                    AppConstants.kRouteStaffLogin,
                                    (r) => false,
                                  );
                                },
                              ),
                            ],
                          ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _showOpenRegisterDialog(
    BuildContext context,
    StaffDashboardViewModel vm,
  ) async {
    final controller = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.staffOpenRegisterTitle),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: AppStrings.staffOpeningFloatLabel,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(AppStrings.staffOpenRegisterConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final float = int.tryParse(controller.text.trim()) ?? 0;
    await vm.openRegister(openingFloat: float);
  }

  Future<void> _showCloseRegisterDialog(
    BuildContext context,
    StaffDashboardViewModel vm,
  ) async {
    final closing = TextEditingController(text: '0');
    final actual = TextEditingController(
      text: '${vm.session?.openRegister?.expectedAmount ?? 0}',
    );
    final notes = TextEditingController();
    final reg = vm.session?.openRegister;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.staffCloseRegisterTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (reg != null) ...[
                Text(
                  AppStrings.staffRegisterExpectedLine(
                    StaffDashboardHelpers.formatInr(reg.expectedAmount),
                  ),
                ),
                Text(
                  AppStrings.staffRegisterReceiptsLine(reg.receiptsGenerated),
                ),
                Text(AppStrings.staffRegisterPrintsLine(reg.photosPrinted)),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: closing,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: AppStrings.staffClosingFloatLabel,
                ),
              ),
              TextField(
                controller: actual,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: AppStrings.staffActualAmountLabel,
                ),
              ),
              TextField(
                controller: notes,
                decoration: const InputDecoration(
                  labelText: AppStrings.staffClosingNotesLabel,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(AppStrings.staffCloseRegisterConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await vm.closeRegister(
      closingFloat: int.tryParse(closing.text.trim()) ?? 0,
      actualAmount: int.tryParse(actual.text.trim()) ?? 0,
      closingNotes: notes.text.trim(),
    );
  }
}

/// Overview tab content (KPIs, shift, register, performance).
class StaffDashboardOverviewTab extends StatelessWidget {
  const StaffDashboardOverviewTab({
    super.key,
    required this.onOpenRegister,
    required this.onCloseRegister,
  });

  final VoidCallback onOpenRegister;
  final VoidCallback onCloseRegister;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StaffDashboardViewModel>();
    final session = vm.session;
    final summary = vm.daySummary;
    final stats = vm.stats;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: vm.refreshQuiet,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (vm.error != null) ...[
                StaffDashboardErrorBanner(
                  message: vm.error!,
                  onDismiss: vm.clearError,
                ),
                const SizedBox(height: 12),
              ],
              StaffDayPickerCard(
                selectedDate: vm.selectedDate,
                timezone: summary?.timezone,
                isToday: vm.isViewingToday,
                onPickDate: vm.setSelectedDate,
                onToday: vm.jumpToToday,
              ),
              const SizedBox(height: 12),
              StaffDayKpiGrid(summary: summary),
              const SizedBox(height: 12),
              StaffModeSplitRow(payments: summary?.payments),
              const SizedBox(height: 12),
              StaffShiftRegisterStatusRow(session: session),
              const SizedBox(height: 12),
              StaffAttendanceCard(
                session: session,
                busy: vm.actionBusy,
                onCheckIn: vm.checkIn,
                onCheckOut: vm.checkOut,
              ),
              const SizedBox(height: 12),
              StaffRegisterCard(
                session: session,
                busy: vm.actionBusy,
                onOpen: onOpenRegister,
                onClose: onCloseRegister,
              ),
              if (stats != null) ...[
                const SizedBox(height: 12),
                StaffPerformanceCard(stats: stats),
              ],
              if (session != null) ...[
                const SizedBox(height: 8),
                Text(
                  session.staff.staffCode,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: StaffThemeColors.mutedSoft(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (vm.loading || vm.actionBusy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x22000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}
