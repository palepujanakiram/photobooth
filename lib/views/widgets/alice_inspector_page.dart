import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_alice/core/alice_core.dart';
import 'package:flutter_alice/ui/page/alice_calls_list_screen.dart';

/// Wrapper for the Alice HTTP inspector that provides Material localizations,
/// SafeArea, and back navigation. Used when opening the inspector from any screen.
class AliceInspectorPage extends StatelessWidget {
  const AliceInspectorPage({super.key, required this.core});
  final AliceCore core;

  @override
  Widget build(BuildContext context) {
    return Localizations(
      locale: const Locale('en'),
      delegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.grey.shade200,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(CupertinoIcons.back),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Back',
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'HTTP Inspector',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ClipRect(
                child: Navigator(
                  initialRoute: '/',
                  onGenerateRoute: (RouteSettings settings) {
                    return MaterialPageRoute<void>(
                      builder: (_) => AliceCallsListScreen(core),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
