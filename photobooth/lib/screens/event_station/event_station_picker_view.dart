import 'package:flutter/material.dart';

import '../../models/event_info_model.dart';
import '../../services/event_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/event_station_role.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_scaffold.dart';
import '../splash/bootstrap_route_args.dart';

class EventStationPickerScreen extends StatelessWidget {
  const EventStationPickerScreen({super.key, EventManager? eventManager})
      : _eventManager = eventManager;

  final EventManager? _eventManager;

  Future<void> _pick(BuildContext context, String role, String route) async {
    await (_eventManager ?? EventManager()).setStationRole(role);
    if (!context.mounted) return;
    await Navigator.of(context).pushReplacementNamed(route);
  }

  /// Leave station mode without re-entering the splash→station auto-route loop.
  void _leaveToKioskSettings(BuildContext context) {
    Navigator.of(context).pushReplacementNamed(
      AppConstants.kRouteSplash,
      arguments: const SplashRouteArgs(manageKiosk: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _leaveToKioskSettings(context);
      },
      child: AppScaffold(
        title: AppStrings.eventStationTitle,
        showBackButton: true,
        onBackPressed: () => _leaveToKioskSettings(context),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FutureBuilder<EventInfoModel?>(
            future: (_eventManager ?? EventManager()).readBoundEvent(),
            builder: (context, snapshot) {
              final event = snapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (event != null) ...[
                    _EventSkinBanner(event: event),
                    const SizedBox(height: 16),
                  ],
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
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EventSkinBanner extends StatelessWidget {
  const _EventSkinBanner({required this.event});

  final EventInfoModel event;

  @override
  Widget build(BuildContext context) {
    final skin = event.chrome.skin;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            _colorFromHex(skin.bannerFrom, 0xE3A65C),
            _colorFromHex(skin.bannerTo, 0x6E5391),
          ],
        ),
      ),
      child: Text(
        event.name?.trim().isNotEmpty == true
            ? event.name!
            : event.code,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _colorFromHex(skin.ink, 0xFFFFFF),
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

Color _colorFromHex(String hex, int fallback) {
  final n = parseRgbHex(hex);
  return Color(0xFF000000 | (n ?? fallback));
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
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
