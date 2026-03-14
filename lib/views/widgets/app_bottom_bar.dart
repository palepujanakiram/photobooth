import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_alice/alice.dart';
import 'alice_inspector_page.dart';
import 'bottom_safe_area.dart';

/// Custom bottom bar that occupies the reserved bottom space and hosts debug
/// actions (e.g. Alice HTTP Inspector). Shown on all screens when [Alice] is
/// provided (debug only). Reuses the space we otherwise reserve for system nav.
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<Alice?>(
      builder: (context, alice, _) {
        if (alice == null) return const SizedBox.shrink();

        final totalHeight = appBottomBarTotalHeight(context);
        final core = alice.getDioInterceptor().aliceCore;

        final safeBottom = safeBottomInset(context);
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: totalHeight,
            width: double.infinity,
            color: Colors.black,
            padding: EdgeInsets.only(bottom: safeBottom),
            alignment: Alignment.bottomCenter,
            child: SizedBox(
                height: kAppBottomBarContentHeight,
                width: double.infinity,
                child: Row(
                  children: [
                    _DebugBarButton(
                      icon: CupertinoIcons.ant,
                      onTap: () {
                        Navigator.of(context, rootNavigator: true).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => AliceInspectorPage(core: core),
                          ),
                        );
                      },
                    ),
                    // Add more debug actions here later
                  ],
                ),
            ),
          ),
        );
      },
    );
  }
}

class _DebugBarButton extends StatelessWidget {
  const _DebugBarButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}
