import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_alice/alice.dart';

import '../../services/alice_inspector.dart';
import '../../utils/app_runtime_config.dart';
import 'alice_inspector_page.dart';

final ValueNotifier<bool> _aliceInspectorOpen = ValueNotifier<bool>(false);

/// Floating Alice control over every screen (not in the AppBar). Hidden while
/// the inspector route is already open.
class AliceFabOverlay extends StatelessWidget {
  const AliceFabOverlay({super.key});

  static const double _edgeInset = 16;
  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppRuntimeConfig.instance,
        _aliceInspectorOpen,
      ]),
      builder: (context, _) {
        final alice = AliceInspector.instance;
        if (alice == null || _aliceInspectorOpen.value) {
          return const SizedBox.shrink();
        }
        final top = MediaQuery.paddingOf(context).top +
            kToolbarHeight +
            _edgeInset;
        return Positioned(
          top: top,
          right: _edgeInset,
          child: _AliceFab(alice: alice, size: _size),
        );
      },
    );
  }
}

class _AliceFab extends StatelessWidget {
  const _AliceFab({required this.alice, required this.size});

  final Alice alice;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      shadowColor: Colors.black54,
      color: const Color(0xE61C1C1E),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => unawaited(_openAliceInspector(alice)),
        child: SizedBox(
          width: size,
          height: size,
          child: const Icon(
            CupertinoIcons.ant,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

Future<void> _openAliceInspector(Alice alice) async {
  final nav = AliceInspector.navigatorKey?.currentState;
  if (nav == null || !nav.mounted) return;
  _aliceInspectorOpen.value = true;
  try {
    await nav.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AliceInspectorPage(
          core: alice.getDioInterceptor().aliceCore,
        ),
      ),
    );
  } finally {
    _aliceInspectorOpen.value = false;
  }
}
