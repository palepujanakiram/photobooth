import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/transformation_step_display.dart';
import '../../views/widgets/leading_with_alice.dart';
import 'transformation_details_viewmodel.dart';

/// Full-screen forensics for one generation run (`GET /api/generation-runs/:runId`).
class TransformationDetailsScreen extends StatelessWidget {
  const TransformationDetailsScreen({
    super.key,
    required this.runId,
  });

  final String runId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final vm = TransformationDetailsViewModel(runId: runId);
        vm.load();
        return vm;
      },
      child: const _TransformationDetailsBody(),
    );
  }
}

class _TransformationDetailsBody extends StatelessWidget {
  const _TransformationDetailsBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TransformationDetailsViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transformation details'),
        actions: const [AppBarAliceAction()],
      ),
      body: vm.isLoading
          ? const Center(child: CircularProgressIndicator())
          : vm.errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      vm.errorMessage!,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _RunBody(payload: vm.payload!),
    );
  }
}

class _RunBody extends StatelessWidget {
  const _RunBody({required this.payload});

  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    final run = payload['run'];
    final stepsRaw = payload['steps'];
    if (run is! Map<String, dynamic>) {
      return const Center(child: Text('Invalid response: missing run'));
    }
    final steps = stepsRaw is List
        ? stepsRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    final meta = run['metadata'] is Map
        ? Map<String, dynamic>.from(run['metadata'] as Map)
        : <String, dynamic>{};
    final applied = meta['appliedSettings'] is Map
        ? Map<String, dynamic>.from(meta['appliedSettings'] as Map)
        : <String, dynamic>{};

    Map<String, dynamic>? aiStep;
    for (final s in steps) {
      final stage = s['stage']?.toString() ?? '';
      if (stage == 'ai_generation' || stage == 'ai') {
        aiStep = s;
        break;
      }
    }

    String? finalPrompt;
    if (aiStep != null) {
      final out = aiStep['outputData'];
      final m = aiStep['metadata'];
      if (out is Map && out['finalPrompt'] != null) {
        finalPrompt = out['finalPrompt'].toString();
      } else if (m is Map && m['finalPrompt'] != null) {
        finalPrompt = m['finalPrompt'].toString();
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _headerCard(context, run),
        const SizedBox(height: 12),
        _jsonCard(context, 'Applied settings', applied),
        if (finalPrompt != null && finalPrompt.isNotEmpty) ...[
          const SizedBox(height: 12),
          _promptCard(context, finalPrompt),
        ],
        const SizedBox(height: 8),
        const Text(
          'Steps',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ...steps.map((s) => _stepTile(context, s)),
      ],
    );
  }

  Widget _headerCard(BuildContext context, Map<String, dynamic> run) {
    final status = run['status']?.toString() ?? '';
    final theme = run['themeName']?.toString() ?? run['themeId']?.toString();
    final duration = run['durationMs'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Run',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Status: $status'),
            if (theme != null && theme.isNotEmpty) Text('Theme: $theme'),
            if (duration != null) Text('Duration: $duration ms'),
          ],
        ),
      ),
    );
  }

  Widget _promptCard(BuildContext context, String prompt) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Final prompt',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SelectableText(
              prompt,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _jsonCard(BuildContext context, String title, Map<String, dynamic> data) {
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }
    final text = const JsonEncoder.withIndent(' ').convert(data);
    return Card(
      child: ExpansionTile(
        title: Text(title),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepTile(BuildContext context, Map<String, dynamic> s) {
    final stage = s['stage']?.toString() ?? 'unknown';
    final label = transformationStepDisplayLabel(stage);
    final status = s['status']?.toString() ?? '';
    final ms = s['durationMs'];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(transformationStepIcon(stage)),
        title: Text(label),
        subtitle: Text(
          '$status${ms != null ? ' · $ms ms' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          if (s['inputData'] != null)
            _jsonBlock(context, 'Input', s['inputData']),
          if (s['outputData'] != null)
            _jsonBlock(context, 'Output', s['outputData']),
          if (s['metadata'] != null)
            _jsonBlock(context, 'Metadata', s['metadata']),
        ],
      ),
    );
  }

  Widget _jsonBlock(BuildContext context, String label, dynamic data) {
    if (data is! Map && data is! List) {
      return ListTile(title: Text('$label: $data'));
    }
    final Object encodable = data is Map
        ? Map<String, dynamic>.from(data)
        : data as List<dynamic>;
    final text = const JsonEncoder.withIndent(' ').convert(encodable);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
