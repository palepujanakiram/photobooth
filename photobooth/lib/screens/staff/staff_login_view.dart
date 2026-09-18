import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/staff_dashboard_models.dart';
import '../../services/staff_api_service.dart';
import '../../services/staff_session_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/exceptions.dart';
import '../../views/widgets/app_colors.dart';
import 'staff_dashboard_helpers.dart';
import 'staff_theme_shell.dart';

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

  /// Skip the form when a token is already stored. Dashboard bootstrap
  /// validates it (and sends stale tokens back here) so login does not
  /// wait on a duplicate `/api/staff/session` round trip.
  Future<void> _tryAutoContinue() async {
    final t = await _session.getToken();
    if (!mounted) return;
    if (t == null || t.isEmpty) return;
    Navigator.of(context)
        .pushReplacementNamed(AppConstants.kRouteStaffDashboard);
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
      final data = await _api.staffLookupWithCode(
        staffCode: staffCode,
        accountName: accountName,
      );
      StaffOpsSessionHold.store(StaffOpsSession.fromJson(data));
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
    return StaffThemeShell(
      child: Builder(
        builder: (context) {
          final appColors = AppColors.of(context);
          return Scaffold(
            backgroundColor: appColors.backgroundColor,
            appBar: AppBar(
              title: const Text('Staff login'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                tooltip: AppStrings.staffBackToStartTooltip,
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                    return;
                  }
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    AppConstants.kRouteSplash,
                    (r) => false,
                  );
                },
              ),
              actions: const [StaffThemeToggleButton()],
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
                        const Align(
                          alignment: Alignment.centerRight,
                          child: StaffThemeToggleButton(),
                        ),
                        const SizedBox(height: 8),
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
                            if (_error != null) {
                              setState(() => _error = null);
                            }
                            final up = v.toUpperCase();
                            if (up != v) {
                              _codeController.value =
                                  _codeController.value.copyWith(
                                text: up,
                                selection:
                                    TextSelection.collapsed(offset: up.length),
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
                            if (_error != null) {
                              setState(() => _error = null);
                            }
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
        },
      ),
    );
  }
}

