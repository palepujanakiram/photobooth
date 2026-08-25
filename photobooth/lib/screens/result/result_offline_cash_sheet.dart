import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/app_strings.dart';
import 'result_viewmodel.dart';

/// Modal on Pay: booth PIN → local cash settle → print (guest stays on Pay).
Future<void> showOfflineCashConfirmSheet({
  required BuildContext context,
  required ResultViewModel viewModel,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1A1F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: _OfflineCashConfirmBody(viewModel: viewModel),
      );
    },
  );
}

class _OfflineCashConfirmBody extends StatefulWidget {
  const _OfflineCashConfirmBody({required this.viewModel});

  final ResultViewModel viewModel;

  @override
  State<_OfflineCashConfirmBody> createState() =>
      _OfflineCashConfirmBodyState();
}

class _OfflineCashConfirmBodyState extends State<_OfflineCashConfirmBody> {
  final _pinController = TextEditingController();
  bool _busy = false;
  String? _localError;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _localError = null;
    });
    final ok = await widget.viewModel.confirmOfflineCashReceived(
      pin: _pinController.text,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _localError =
          widget.viewModel.errorMessage ?? AppStrings.offlineCashConfirmFailed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              AppStrings.offlineCashConfirmSheetTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.offlineCashConfirmSheetBody,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '₹${widget.viewModel.chargeAmount}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                labelText: AppStrings.offlineCashConfirmPinLabel,
                labelStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white70),
                ),
              ),
              onSubmitted: (_) => unawaited(_submit()),
            ),
            if (_localError != null) ...[
              const SizedBox(height: 10),
              Text(
                _localError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orange.shade200, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _busy ? null : () => unawaited(_submit()),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(AppStrings.offlineCashConfirmSubmit),
            ),
          ],
        ),
      ),
    );
  }
}
