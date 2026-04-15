import 'package:flutter/widgets.dart';

/// Centers [child] and constrains it to [maxWidth] while still expanding
/// to available width on small screens.
class CenteredMaxWidth extends StatelessWidget {
  const CenteredMaxWidth({
    super.key,
    required this.child,
    this.maxWidth = 360,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

