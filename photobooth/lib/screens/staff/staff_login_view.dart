import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../services/staff_api_service.dart';
import '../../services/staff_session_manager.dart';
import '../../utils/constants.dart';
import '../../utils/exceptions.dart';
import '../../views/widgets/app_colors.dart';
import 'staff_auth_helpers.dart';

class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key});

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final _codeController = TextEditingController();
  final _accountController = TextEditingController();

  final _api = StaffApiService();
  final _session = StaffSessionManager();

  bool _busy = false;
  bool _autoContinueStarted = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  /// Only skip the login form when a stored token still validates with the API.
  /// A stale token previously bounced users back to the dashboard ("Unauthorized").
  Future<void> _tryAutoContinue() async {
    final t = await _session.getToken();
    if (!mounted) return;
    if (t == null || t.isEmpty) return;

    setState(() => _busy = true);
    try {
      await _api.fetchStaffOpsSession();
      if (!mounted) return;
      Navigator.of(context)
          .pushReplacementNamed(AppConstants.kRouteStaffDashboard);
    } on ApiException catch (e) {
      if (StaffAuthHelpers.isAuthFailure(e)) {
        await _session.clear();
      }
      // Stay on login so the user can sign in again.
    } catch (_) {
      // Network blip — leave the form visible.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_autoContinueStarted || _busy || _error != null) return;
    _autoContinueStarted = true;
    unawaited(_tryAutoContinue());
  }

  Future<void> _login() async {
    final staffCode = _codeController.text.trim().toUpperCase();
    final accountName = _accountController.text.trim().toLowerCase();
    if (staffCode.isEmpty || accountName.isEmpty) {
      setState(() => _error = 'Enter staff code and account name');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _api.staffLookupWithCode(
        staffCode: staffCode,
        accountName: accountName,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppConstants.kRouteStaffDashboard);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    return Scaffold(
      backgroundColor: appColors.backgroundColor,
      appBar: AppBar(
        title: const Text('Staff login'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Enter employee code',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: appColors.textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  CupertinoTextField(
                    controller: _codeController,
                    placeholder: 'Staff code (e.g. EMPMJPM5WEC)',
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    onChanged: (v) {
                      if (_error != null) setState(() => _error = null);
                      final up = v.toUpperCase();
                      if (up != v) {
                        _codeController.value = _codeController.value.copyWith(
                          text: up,
                          selection: TextSelection.collapsed(offset: up.length),
                          composing: TextRange.empty,
                        );
                      }
                    },
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    controller: _accountController,
                    placeholder: 'Account name (e.g. mumbai-central)',
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    onSubmitted: (_) => _login(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _login,
                      child: Text(_busy ? 'Signing in…' : 'Sign in'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

