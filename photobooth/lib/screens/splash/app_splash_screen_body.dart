import 'package:flutter/cupertino.dart';

import '../../utils/constants.dart';
import '../../views/widgets/app_colors.dart';
import 'app_splash_copy_helpers.dart';
import 'bootstrap_route_args.dart';

/// Branded card + kiosk form region (Sonar S3776 extraction from [AppSplashScreen]).
class AppSplashScreenBody extends StatelessWidget {
  const AppSplashScreenBody({
    super.key,
    required this.args,
    required this.appColors,
    required this.formMaxWidth,
    required this.fade,
    required this.scale,
    required this.bootstrapDone,
    required this.showForm,
    required this.showManageSummary,
    required this.storedCode,
    required this.busy,
    required this.error,
    required this.needsEntry,
    required this.onManageEdit,
    required this.onDisconnect,
    required this.buildCodeOrScanRow,
    required this.onSubmitCode,
    required this.onStaffLogin,
  });

  final SplashRouteArgs args;
  final AppColors appColors;
  final double formMaxWidth;
  final Animation<double> fade;
  final Animation<double> scale;
  final bool bootstrapDone;
  final bool showForm;
  final bool showManageSummary;
  final String? storedCode;
  final bool busy;
  final String? error;
  final bool needsEntry;
  final VoidCallback onManageEdit;
  final VoidCallback onDisconnect;
  final Widget Function(bool showManageSummary) buildCodeOrScanRow;
  final VoidCallback onSubmitCode;
  final VoidCallback onStaffLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: formMaxWidth),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: appColors.backgroundColor.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: appColors.dividerColor.withValues(alpha: 0.45),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: fade,
                      child: ScaleTransition(
                        scale: scale,
                        child: _AppSplashBrandingHeader(
                          appColors: appColors,
                          manageKiosk: args.manageKiosk,
                          needsEntry: needsEntry,
                        ),
                      ),
                    ),
                    if (bootstrapDone) ...[
                      const SizedBox(height: 26),
                      if (showManageSummary)
                        _AppSplashManageSummary(
                          appColors: appColors,
                          storedCode: storedCode!,
                          busy: busy,
                          onManageEdit: onManageEdit,
                          onDisconnect: onDisconnect,
                        ),
                      if (showForm)
                        _AppSplashKioskForm(
                          appColors: appColors,
                          showManageSummary: showManageSummary,
                          error: error,
                          busy: busy,
                          manageKiosk: args.manageKiosk,
                          buildCodeOrScanRow: buildCodeOrScanRow,
                          onSubmitCode: onSubmitCode,
                          onStaffLogin: onStaffLogin,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppSplashBrandingHeader extends StatelessWidget {
  const _AppSplashBrandingHeader({
    required this.appColors,
    required this.manageKiosk,
    required this.needsEntry,
  });

  final AppColors appColors;
  final bool manageKiosk;
  final bool needsEntry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 72,
          child: Image.asset(
            AppConstants.kBrandLogoAsset,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(
              CupertinoIcons.sparkles,
              size: 56,
              color: appColors.primaryColor,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          AppConstants.kBrandName,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: appColors.textColor,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          appSplashKioskSubtitle(
            manageKiosk: manageKiosk,
            needsEntry: needsEntry,
          ),
          style: TextStyle(
            fontSize: 15,
            color: appColors.secondaryTextColor,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _AppSplashManageSummary extends StatelessWidget {
  const _AppSplashManageSummary({
    required this.appColors,
    required this.storedCode,
    required this.busy,
    required this.onManageEdit,
    required this.onDisconnect,
  });

  final AppColors appColors;
  final String storedCode;
  final bool busy;
  final VoidCallback onManageEdit;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Linked to kiosk',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: appColors.secondaryTextColor,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          storedCode,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: appColors.textColor,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: CupertinoColors.systemBlue,
                borderRadius: BorderRadius.circular(12),
                onPressed: busy ? null : onManageEdit,
                child: const Text(
                  'Change code',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: CupertinoColors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: CupertinoColors.systemRed
                    .resolveFrom(context)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                onPressed: busy ? null : onDisconnect,
                child: Text(
                  'Disconnect',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: CupertinoColors.destructiveRed.resolveFrom(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AppSplashKioskForm extends StatelessWidget {
  const _AppSplashKioskForm({
    required this.appColors,
    required this.showManageSummary,
    required this.error,
    required this.busy,
    required this.manageKiosk,
    required this.buildCodeOrScanRow,
    required this.onSubmitCode,
    required this.onStaffLogin,
  });

  final AppColors appColors;
  final bool showManageSummary;
  final String? error;
  final bool busy;
  final bool manageKiosk;
  final Widget Function(bool showManageSummary) buildCodeOrScanRow;
  final VoidCallback onSubmitCode;
  final VoidCallback onStaffLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showManageSummary) const SizedBox(height: 20),
        Text(
          'Enter the code, or scan the operator’s QR with this booth',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: appColors.secondaryTextColor,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        buildCodeOrScanRow(showManageSummary),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(
            error!,
            style: const TextStyle(
              color: CupertinoColors.systemRed,
              fontSize: 14,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 18),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 16),
          color: CupertinoColors.systemBlue,
          borderRadius: BorderRadius.circular(12),
          onPressed: busy ? null : onSubmitCode,
          child: Text(
            manageKiosk ? 'Save & continue' : 'Continue',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: CupertinoColors.white,
            ),
          ),
        ),
        const SizedBox(height: 14),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 14),
          color: CupertinoColors.systemGrey
              .resolveFrom(context)
              .withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          onPressed: busy ? null : onStaffLogin,
          child: Text(
            'Staff login',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: appColors.textColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// Version label under splash content (Sonar S3776 extraction).
Widget appSplashVersionFooter(String versionFooter, AppColors appColors) {
  if (versionFooter.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
    child: Text(
      versionFooter,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12,
        height: 1.25,
        color: appColors.secondaryTextColor.withValues(alpha: 0.88),
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
