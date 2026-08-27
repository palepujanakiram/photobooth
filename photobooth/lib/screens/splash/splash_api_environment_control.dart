import 'package:flutter/cupertino.dart';

import '../../services/api_environment_store.dart';
import '../../utils/api_environment.dart';
import '../../utils/app_strings.dart';
import '../../views/widgets/app_colors.dart';

/// Stage / Live API host control for splash kiosk management.
class SplashApiEnvironmentControl extends StatelessWidget {
  const SplashApiEnvironmentControl({
    super.key,
    required this.appColors,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final AppColors appColors;
  final ApiEnvironment selected;
  final bool enabled;
  final ValueChanged<ApiEnvironment> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStrings.apiEnvironmentHeading,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: appColors.secondaryTextColor,
          ),
        ),
        const SizedBox(height: 8),
        CupertinoSlidingSegmentedControl<ApiEnvironment>(
          groupValue: selected,
          children: const {
            ApiEnvironment.stage: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(AppStrings.apiEnvironmentStage),
            ),
            ApiEnvironment.live: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(AppStrings.apiEnvironmentLive),
            ),
          },
          onValueChanged: (value) {
            if (!enabled || value == null) return;
            onChanged(value);
          },
        ),
        const SizedBox(height: 6),
        Text(
          selected.hostHint,
          style: TextStyle(
            fontSize: 12,
            color: appColors.secondaryTextColor,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Current selection for the control (prefs override or branch default).
ApiEnvironment splashApiEnvironmentSelection() => ApiEnvironmentStore.current;
