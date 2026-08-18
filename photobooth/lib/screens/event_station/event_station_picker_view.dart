import 'package:flutter/material.dart';

import '../../services/event_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/event_station_role.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_scaffold.dart';

class EventStationPickerScreen extends StatelessWidget {
  const EventStationPickerScreen({super.key, EventManager? eventManager})
      : _eventManager = eventManager;

  final EventManager? _eventManager;

  Future<void> _pick(BuildContext context, String role, String route) async {
    await (_eventManager ?? EventManager()).setStationRole(role);
    if (!context.mounted) return;
    await Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppScaffold(
      title: AppStrings.eventStationTitle,
      showBackButton: true,
      onBackPressed: () {
        Navigator.of(context).pushReplacementNamed(AppConstants.kRouteSplash);
      },
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StationChoice(
              title: AppStrings.eventStationCapture,
              subtitle: AppStrings.eventStationCaptureHint,
              onTap: () => _pick(
                context,
                EventStationRole.capture,
                AppConstants.kRouteEventCaptureStation,
              ),
            ),
            const SizedBox(height: 16),
            _StationChoice(
              title: AppStrings.eventStationTheme,
              subtitle: AppStrings.eventStationThemeHint,
              onTap: () => _pick(
                context,
                EventStationRole.theme,
                AppConstants.kRouteEventThemeStation,
              ),
            ),
            const SizedBox(height: 16),
            _StationChoice(
              title: AppStrings.eventStationPrint,
              subtitle: AppStrings.eventStationPrintHint,
              onTap: () => _pick(
                context,
                EventStationRole.print,
                AppConstants.kRouteEventPrintStation,
              ),
            ),
            const Spacer(),
            Text(
              'Printer, camera, and copies come from this kiosk.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.secondaryTextColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationChoice extends StatelessWidget {
  const _StationChoice({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
