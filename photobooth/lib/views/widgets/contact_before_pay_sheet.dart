import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../models/customer_contact_capture.dart';
import '../../utils/app_strings.dart';
import '../../utils/contact_phone_helpers.dart';

/// Strips ASCII control chars and zero-width / bidi marks from names.
final RegExp _kNameSanitizer = RegExp(
  '[\u0000-\u001F\u007F\u200B-\u200F\u2028-\u2029\u202A-\u202E\uFEFF]',
);

/// Result of [showContactBeforePaySheet] (alias of [CustomerContactCapture]).
typedef ContactBeforePayResult = CustomerContactCapture;

/// Optional contact capture shown right before navigating to Pay & Collect.
///
/// Rules:
/// - If user taps **Skip**: `skipped=true`, empty phone, `whatsappOptIn=false`.
/// - If phone is empty: `whatsappOptIn=false` (even if checkbox checked).
/// - WhatsApp queue only when phone is non-empty AND checkbox checked.
/// - Marketing flags are independent of transactional WhatsApp opt-in.
Future<ContactBeforePayResult?> showContactBeforePaySheet(
  BuildContext context,
) async {
  return showModalBottomSheet<ContactBeforePayResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    elevation: 6,
    builder: (ctx) => Theme(
      data: Theme.of(ctx).copyWith(
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          modalBackgroundColor: Colors.white,
        ),
      ),
      child: const _ContactBeforePaySheetBody(),
    ),
  );
}

class _ContactBeforePaySheetBody extends StatefulWidget {
  const _ContactBeforePaySheetBody();

  @override
  State<_ContactBeforePaySheetBody> createState() =>
      _ContactBeforePaySheetBodyState();
}

class _ContactBeforePaySheetBodyState extends State<_ContactBeforePaySheetBody> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final FocusNode _nameFocus;
  late final FocusNode _phoneFocus;
  bool _waOptIn = false;
  bool _marketingWhatsapp = false;
  bool _marketingSms = false;
  bool _marketingEmail = false;
  String? _phoneError;

  static const Color _titleColor = Color(0xFF111827);
  static const Color _bodyColor = Color(0xFF374151);
  static const Color _mutedColor = Color(0xFF4B5563);

  static const TextStyle _titleStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: 0,
    color: _titleColor,
  );

  static const TextStyle _bodyStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
    letterSpacing: 0,
    color: _bodyColor,
  );

  static const TextStyle _checkboxTitleStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0,
    color: _titleColor,
  );

  static const TextStyle _checkboxSubtitleStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.35,
    letterSpacing: 0,
    color: _mutedColor,
  );

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _nameFocus = FocusNode();
    _phoneFocus = FocusNode();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  void _popResult({required bool skipped}) {
    if (skipped) {
      Navigator.pop(context, CustomerContactCapture.empty.copyWith(skipped: true));
      return;
    }
    final name = _nameCtrl.text.replaceAll(_kNameSanitizer, '').trim();
    final p = ContactPhoneHelpers.normalizePhone(_phoneCtrl.text);
    final email = _emailCtrl.text.trim();

    if (p.isEmpty) {
      Navigator.pop(
        context,
        CustomerContactCapture(
          customerName: name,
          customerPhone: '',
          whatsappOptIn: false,
          customerEmail: email,
          marketingEmailOptIn: _marketingEmail,
          marketingSmsOptIn: _marketingSms,
          marketingWhatsappOptIn: _marketingWhatsapp,
        ),
      );
      return;
    }

    if (!ContactPhoneHelpers.isValidE164(p)) {
      setState(() {
        _phoneError =
            'Enter mobile number (10 digits) or include country code, e.g. +9198xxxxxx00';
      });
      _phoneFocus.requestFocus();
      return;
    }

    setState(() => _phoneError = null);
    Navigator.pop(
      context,
      CustomerContactCapture(
        customerName: name,
        customerPhone: p,
        whatsappOptIn: _waOptIn,
        customerEmail: email,
        marketingEmailOptIn: _marketingEmail,
        marketingSmsOptIn: _marketingSms,
        marketingWhatsappOptIn: _marketingWhatsapp,
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      filled: true,
      fillColor: Colors.white,
      border: const OutlineInputBorder(),
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        color: _mutedColor,
      ),
      floatingLabelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        color: _titleColor,
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    FocusNode? focusNode,
    required String label,
    String? hint,
    String? errorText,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: _titleColor,
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: _fieldDecoration(
        label: label,
        hint: hint,
        errorText: errorText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final viewInsets = mq.viewInsets;
    final bottomPad =
        (16 + viewInsets.bottom + mq.padding.bottom).roundToDouble();
    final isLandscape = mq.orientation == Orientation.landscape;
    final hasPhone = _phoneCtrl.text.trim().isNotEmpty;

    final nameField = _textField(
      controller: _nameCtrl,
      focusNode: _nameFocus,
      label: 'Name (optional)',
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _phoneFocus.requestFocus(),
    );

    final phoneField = _textField(
      controller: _phoneCtrl,
      focusNode: _phoneFocus,
      label: 'WhatsApp mobile (optional)',
      hint: '98xxxxxx00',
      errorText: _phoneError,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      onChanged: (_) {
        setState(() {
          if (_phoneCtrl.text.trim().isEmpty) {
            _waOptIn = false;
          }
          if (_phoneError != null) {
            _phoneError = null;
          }
        });
      },
    );

    final emailField = _textField(
      controller: _emailCtrl,
      label: AppStrings.optionalEmailLabel,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: bottomPad,
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.opaque,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Get receipt on WhatsApp',
                    style: _titleStyle,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Optional — add your name and mobile to get the receipt and '
                    'digital copy after payment. You can still scan the QR either way.',
                    style: _bodyStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (isLandscape) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: nameField),
                  const SizedBox(width: 12),
                  Expanded(child: phoneField),
                ],
              ),
              const SizedBox(height: 12),
              emailField,
            ] else ...[
              nameField,
              const SizedBox(height: 12),
              phoneField,
              const SizedBox(height: 12),
              emailField,
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _waOptIn,
              onChanged: hasPhone
                  ? (v) => setState(() => _waOptIn = v ?? false)
                  : null,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Send on WhatsApp',
                style: _checkboxTitleStyle,
              ),
              subtitle: Text(
                hasPhone
                    ? 'Only after payment is approved.'
                    : 'Enter a mobile number to enable.',
                style: _checkboxSubtitleStyle,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    AppStrings.marketingConsentBlurb,
                    style: _checkboxSubtitleStyle,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _marketingWhatsapp,
                    onChanged: (v) =>
                        setState(() => _marketingWhatsapp = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      AppStrings.marketingWhatsappLabel,
                      style: _checkboxSubtitleStyle,
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _marketingSms,
                    onChanged: (v) =>
                        setState(() => _marketingSms = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      AppStrings.marketingSmsLabel,
                      style: _checkboxSubtitleStyle,
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _marketingEmail,
                    onChanged: (v) =>
                        setState(() => _marketingEmail = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      AppStrings.marketingEmailLabel,
                      style: _checkboxSubtitleStyle,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _popResult(skipped: true),
                    child: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(
                      CupertinoIcons.arrow_right,
                      size: 18,
                    ),
                    onPressed: () => _popResult(skipped: false),
                    label: const Text('Continue to pay'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
