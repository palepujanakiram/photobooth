import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_alice/alice.dart';
import 'alice_inspector_page.dart';

/// Right-side app bar action that opens the Alice HTTP Inspector when [Alice]
/// is provided (debug). Uses 60px right padding so the button stays tappable.
class AppBarAliceAction extends StatelessWidget {
  const AppBarAliceAction({super.key});

  static const double _rightPadding = 60.0;

  @override
  Widget build(BuildContext context) {
    return Consumer<Alice?>(
      builder: (context, alice, _) {
        if (alice == null) return const SizedBox.shrink();

        final core = alice.getDioInterceptor().aliceCore;
        final color = Theme.of(context).appBarTheme.iconTheme?.color ??
            Theme.of(context).appBarTheme.foregroundColor;
        return Padding(
          padding: const EdgeInsets.only(right: _rightPadding),
          child: IconButton(
            icon: Icon(CupertinoIcons.ant, size: 22, color: color),
            onPressed: () {
              Navigator.of(context, rootNavigator: true).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => AliceInspectorPage(core: core),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
