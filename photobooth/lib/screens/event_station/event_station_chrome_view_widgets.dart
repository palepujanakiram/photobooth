import 'package:flutter/material.dart';

import '../../models/event_info_model.dart';
import '../../screens/theme_selection/theme_model.dart';
import '../../services/api_service.dart';
import '../../services/event_manager.dart';
import '../../services/kiosk_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/event_station_chrome.dart';
import '../../utils/theme_image_urls.dart';
import '../../views/widgets/cached_network_image.dart';

Future<EventInfoModel?> fetchBoundEventLive(String code) async {
  final kiosk = await KioskManager().getKioskCode();
  return ApiService().fetchEventByCode(code, kioskCode: kiosk);
}

class EventStationChromeScope extends InheritedWidget {
  const EventStationChromeScope({
    super.key,
    required this.event,
    required super.child,
  });

  final EventInfoModel event;

  static EventInfoModel? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<EventStationChromeScope>()
        ?.event;
  }

  @override
  bool updateShouldNotify(EventStationChromeScope oldWidget) {
    return event.code != oldWidget.event.code ||
        event.name != oldWidget.event.name ||
        event.chrome.tagline != oldWidget.event.chrome.tagline ||
        event.chrome.skin.id != oldWidget.event.chrome.skin.id;
  }
}

class EventStationBoundShell extends StatelessWidget {
  const EventStationBoundShell({
    super.key,
    required this.child,
    this.eventManager,
    this.fetchBoundEvent,
  });

  final Widget child;
  final EventManager? eventManager;
  final Future<EventInfoModel?> Function(String code)? fetchBoundEvent;

  @override
  Widget build(BuildContext context) {
    final em = eventManager ?? EventManager();
    return FutureBuilder<EventInfoModel?>(
      future: em.hydrateBoundEvent(
        fetchLive: fetchBoundEvent ?? fetchBoundEventLive,
      ),
      builder: (context, snapshot) {
        return EventStationChromeFrame(event: snapshot.data, child: child);
      },
    );
  }
}

class EventStationChromeFrame extends StatelessWidget {
  const EventStationChromeFrame({
    super.key,
    required this.child,
    this.event,
  });

  final EventInfoModel? event;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bound = event;
    if (bound == null || !bound.isValid) return child;
    final wash = Color(
      eventChromeBannerFromArgb(bound.chrome.skin),
    ).withValues(alpha: 0.08);
    return EventStationChromeScope(
      event: bound,
      child: ColoredBox(
        color: wash,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: EventStationBrandingHeader(event: bound),
            ),
            Expanded(child: child),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: EventStationPoweredByFooter(),
            ),
          ],
        ),
      ),
    );
  }
}

class EventStationBrandingHeader extends StatelessWidget {
  const EventStationBrandingHeader({super.key, required this.event});

  final EventInfoModel event;

  @override
  Widget build(BuildContext context) {
    final skin = event.chrome.skin;
    final ink = Color(eventChromeInkArgb(skin));
    final tagline = eventChromeTaglineLabel(event);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            Color(eventChromeBannerFromArgb(skin)),
            Color(eventChromeBannerToArgb(skin)),
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventChromeTitle(event),
                  style: TextStyle(
                    color: ink,
                    fontSize: 28,
                    height: 1.1,
                    fontFamily: 'serif',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (tagline.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    tagline,
                    style: TextStyle(
                      color: ink.withValues(alpha: 0.92),
                      fontSize: 12,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          const _EventStationWordmark(height: 44),
        ],
      ),
    );
  }
}

class EventStationPoweredByFooter extends StatelessWidget {
  const EventStationPoweredByFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _EventStationWordmark(height: 18),
        const SizedBox(width: 8),
        Text(
          AppStrings.eventStationPoweredBy,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(width: 4),
        Text(
          AppStrings.eventStationPoweredByBrand,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(kEventLookSelectedBorder),
              ),
        ),
      ],
    );
  }
}

class _EventStationWordmark extends StatelessWidget {
  const _EventStationWordmark({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height < 24 ? 4 : 8),
      child: Image.asset(
        AppConstants.kBrandLogoAsset,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

class EventStationLookTile extends StatelessWidget {
  const EventStationLookTile({
    super.key,
    required this.theme,
    required this.skin,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final ThemeModel theme;
  final EventSkinChrome skin;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = Color(
      eventLookFillArgb(
        themeHex: theme.backgroundColor,
        skin: skin,
        index: index,
      ),
    );
    final sample = theme.sampleImageUrl?.trim() ?? '';
    final imageUrl =
        sample.isEmpty ? '' : resolveThemeSampleImageUrl(sample);
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(kEventLookSelectedBorder)
                  : Colors.transparent,
              width: selected ? 4 : 0,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl.isNotEmpty)
                CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x99000000)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    theme.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
