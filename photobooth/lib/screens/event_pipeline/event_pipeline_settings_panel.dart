import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/event_pipeline/event_pipeline_settings.dart';
import '../../services/event_manager.dart';
import '../../services/event_pipeline/event_pipeline_config.dart';
import '../../views/widgets/app_colors.dart';
import 'event_pipeline_settings_rows.dart';

/// Kiosk-settings section for the offline event pipeline.
///
/// Renders nothing unless an event is bound — the whole feature is event-scoped,
/// and an unbound kiosk has nothing to configure.
///
/// Each switch writes a **local override**; the value shown is the *resolved*
/// one (override → backend flag → default), so the operator always sees what
/// will actually happen rather than the override's tri-state. **Reset to event
/// defaults** clears every override and returns to inheriting.
class EventPipelineSettingsPanel extends StatefulWidget {
  const EventPipelineSettingsPanel({
    super.key,
    required this.appColors,
    this.enabled = true,
    this.config,
    this.eventManager,
  });

  final AppColors appColors;
  final bool enabled;
  final EventPipelineConfig? config;
  final EventManager? eventManager;

  @override
  State<EventPipelineSettingsPanel> createState() =>
      _EventPipelineSettingsPanelState();
}

class _EventPipelineSettingsPanelState
    extends State<EventPipelineSettingsPanel> {
  late final EventPipelineConfig _config = widget.config ?? EventPipelineConfig();
  late final EventManager _events = widget.eventManager ?? EventManager();

  bool _loading = true;
  bool _bound = false;
  bool _expanded = false;
  EventPipelineSettings? _settings;
  EventPipelineDefaults _defaults = const EventPipelineDefaults();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final bound = await _events.isEventBound();
    if (!bound) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _bound = false;
      });
      return;
    }
    final defaults = EventPipelineDefaults(
      photoMode: await _events.getPhotoModeOverride() ?? 'BOTH',
      frameCount: await _events.getFrameCount(),
    );
    final resolved = await _config.resolve(defaults: defaults);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _bound = true;
      _defaults = defaults;
      _settings = resolved;
      _expanded = _expanded || resolved.pipelineEnabled;
    });
  }

  Future<void> _apply(Future<void> Function() write) async {
    await write();
    final resolved = await _config.resolve(defaults: _defaults);
    if (!mounted) return;
    setState(() => _settings = resolved);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_bound) return const SizedBox.shrink();
    final settings = _settings;
    if (settings == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        decoration: BoxDecoration(
          color: widget.appColors.cardBackgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.appColors.dividerColor),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EventPipelineHeaderRow(
              appColors: widget.appColors,
              on: settings.pipelineEnabled,
              expanded: _expanded,
              onToggleExpanded: () => setState(() => _expanded = !_expanded),
            ),
            if (_expanded) ..._body(settings),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(EventPipelineSettings settings) {
    final on = settings.pipelineEnabled;
    return <Widget>[
      const SizedBox(height: 4),
      EventPipelineSwitchRow(
        appColors: widget.appColors,
        label: 'Use local pipeline',
        detail: 'Import from SD, queue locally, print without the server.',
        value: on,
        enabled: widget.enabled,
        onChanged: (v) => _apply(() => _config.setPipelineEnabledOverride(v)),
      ),
      if (on) ..._pipelineRows(settings),
      const SizedBox(height: 8),
      EventPipelineResetRow(
        appColors: widget.appColors,
        enabled: widget.enabled,
        onReset: () => _apply(_config.clearOverrides),
      ),
    ];
  }

  List<Widget> _pipelineRows(EventPipelineSettings settings) {
    return <Widget>[
      EventPipelineSwitchRow(
        appColors: widget.appColors,
        label: 'Event offline mode',
        detail: 'Runs with no internet. Separate from kiosk offline mode.',
        value: settings.offlineMode,
        enabled: widget.enabled,
        onChanged: (v) => _apply(() => _config.setOfflineModeOverride(v)),
      ),
      EventPipelineSwitchRow(
        appColors: widget.appColors,
        label: 'AI generation',
        detail: settings.canRunAi
            ? 'Theme ${settings.themeId}'
            : 'No event theme set — AI will be skipped.',
        value: settings.aiEnabled,
        enabled: widget.enabled,
        onChanged: (v) => _apply(() => _config.setAiEnabledOverride(v)),
      ),
      EventPipelineSwitchRow(
        appColors: widget.appColors,
        label: 'Apply frame',
        detail: settings.canRunFrame
            ? 'Frame ${settings.frameId}'
            : 'No event frame set — framing will be skipped.',
        value: settings.frameEnabled,
        enabled: widget.enabled,
        onChanged: (v) => _apply(() => _config.setFrameEnabledOverride(v)),
      ),
      EventPipelineSwitchRow(
        appColors: widget.appColors,
        label: 'Auto print',
        detail: 'Off means the operator releases each print.',
        value: settings.autoPrint,
        enabled: widget.enabled,
        onChanged: (v) => _apply(() => _config.setAutoPrintOverride(v)),
      ),
      EventPipelineCopiesRow(
        appColors: widget.appColors,
        copies: settings.defaultCopies,
        enabled: widget.enabled,
        onChanged: (n) => _apply(() => _config.setDefaultCopiesOverride(n)),
      ),
      EventPipelineChainPreview(
        appColors: widget.appColors,
        steps: settings.resolveSteps(),
        copies: settings.defaultCopies,
        printSize: settings.printSize,
      ),
    ];
  }
}
