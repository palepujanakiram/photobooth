import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/customer_data_deletion.dart';
import '../../services/session_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../widgets/app_snackbar.dart';

/// Confirms, deletes customer photos on the server, wipes local session, and
/// returns to Terms.
Future<bool> confirmAndDeleteMyPhotos(
  BuildContext context, {
  CustomerDataDeletion? deletion,
}) async {
  final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(AppStrings.deleteMyPhotosDialogTitle),
            content: const Text(AppStrings.deleteMyPhotosDialogBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text(AppStrings.deleteMyPhotosCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text(
                  AppStrings.deleteMyPhotosConfirm,
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          );
        },
      ) ??
      false;

  if (!shouldDelete) return false;

  try {
    await (deletion ??
            CustomerDataDeletion.standard(
              apiService: ApiService(),
              sessionManager: SessionManager(),
            ))
        .deleteMyPhotos();
    if (!context.mounted) return true;
    await Navigator.pushNamedAndRemoveUntil(
      context,
      AppConstants.kRouteTerms,
      (route) => false,
    );
    return true;
  } catch (e) {
    if (context.mounted) {
      AppSnackBar.showError(context, deleteMyPhotosErrorMessage(e));
    }
    return false;
  }
}

/// Destructive customer action — full-width button or compact text link.
class DeleteMyPhotosButton extends StatelessWidget {
  const DeleteMyPhotosButton({
    super.key,
    this.compact = false,
    this.onBeforeDelete,
    this.deletion,
  });

  final bool compact;
  final Future<void> Function()? onBeforeDelete;
  final CustomerDataDeletion? deletion;

  Future<void> _onPressed(BuildContext context) async {
    await onBeforeDelete?.call();
    if (!context.mounted) return;
    await confirmAndDeleteMyPhotos(context, deletion: deletion);
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Center(
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            onPressed: () => _onPressed(context),
            child: const Text(
              AppStrings.deleteMyPhotosLabel,
              style: TextStyle(
                fontSize: 14,
                color: CupertinoColors.destructiveRed,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red.shade300,
            side: BorderSide(color: Colors.red.withValues(alpha: 0.45)),
            minimumSize: const Size(double.infinity, 48),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () => _onPressed(context),
          icon: const Icon(CupertinoIcons.delete, size: 18),
          label: const Text(
            AppStrings.deleteMyPhotosLabel,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
