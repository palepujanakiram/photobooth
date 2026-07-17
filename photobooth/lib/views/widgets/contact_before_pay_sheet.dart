import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

/// Strips ASCII control chars (U+0000–U+001F, U+007F) and common zero-width /
/// bidi / line+paragraph separator marks from user-entered names. These
/// can break WhatsApp template variable rendering.
final RegExp _kNameSanitizer = RegExp(
  '[\u0000-\u001F\u007F\u200B-\u200F\u2028-\u2029\u202A-\u202E\uFEFF]',
);

class ContactBeforePayResult {
  const ContactBeforePayResult({
    required this.customerName,
    required this.customerPhone,
    required this.whatsappOptIn,
    required this.skipped,
  });

  final String customerName;
  final String customerPhone;
  final bool whatsappOptIn;
  final bool skipped;
}

/// Optional contact capture shown right before navigating to Pay & Collect.
///
/// Rules:
/// - If user taps **Skip**: `skipped=true`, empty phone, `whatsappOptIn=false`.
/// - If phone is empty: `whatsappOptIn=false` (even if checkbox checked).
/// - WhatsApp queue only when phone is non-empty AND checkbox checked.
Future<ContactBeforePayResult?> showContactBeforePaySheet(
  BuildContext context,
) async {
  return showModalBottomSheet<ContactBeforePayResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    // Opaque white sheet keeps web text sharp (avoids soft compositing
    // over a tinted / translucent Material surface).
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
  late final FocusNode _nameFocus;
  late final FocusNode _phoneFocus;
  bool _waOptIn = false;
  String? _phoneError;

  /// E.164: leading '+' followed by 10–15 digits.
  /// (Min 10 digits matches India mobile + country code; ITU max is 15.)
  static final RegExp _e164 = RegExp(r'^\+\d{10,15}$');

  static const String _defaultDialCode = '+91';

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

  /// Strips spaces, dashes, parentheses, and dots. Keeps a leading '+'.
  /// If user enters a local number without country code, defaults to [_defaultDialCode].
  static String _normalizePhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final compact = trimmed.replaceAll(RegExp(r'[\s\-().]'), '');
    if (compact.isEmpty) return '';

    // If user explicitly typed a country code, trust it (still validated as E.164 later).
    if (compact.startsWith('+')) return compact;

    // Keep digits only for local-format inputs.
    var digits = compact.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';

    // Common India input: leading 0 trunk prefix.
    if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }

    // If they typed 91XXXXXXXXXX (without '+'), normalize to +91.
    if (digits.length == 12 && digits.startsWith('91')) {
      return '+$digits';
    }

    // Default: if it looks like a local mobile number, treat as India.
    if (digits.length == 10) {
      return '$_defaultDialCode$digits';
    }

    // Fallback: don't guess for other lengths; validation will show an error.
    return digits;
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _nameFocus = FocusNode();
    _phoneFocus = FocusNode();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  void _popResult({required bool skipped}) {
    if (skipped) {
      Navigator.pop(
        context,
        const ContactBeforePayResult(
          customerName: '',
          customerPhone: '',
          whatsappOptIn: false,
          skipped: true,
        ),
      );
      return;
    }
    // Light name sanitization: strip control chars (newlines, tabs, DEL) and
    // common zero-width / bidi marks so they don't end up rendered in WhatsApp
    // template variables.
    final name = _nameCtrl.text
        .replaceAll(_kNameSanitizer, '')
        .trim();
    final p = _normalizePhone(_phoneCtrl.text);

    // Empty phone => proceed without WhatsApp (same behavior as before).
    if (p.isEmpty) {
      Navigator.pop(
        context,
        ContactBeforePayResult(
          customerName: name,
          customerPhone: '',
          whatsappOptIn: false,
          skipped: false,
        ),
      );
      return;
    }

    // Non-empty phone: must be valid E.164. Show inline error and don't pop.
    if (!_e164.hasMatch(p)) {
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
      ContactBeforePayResult(
        customerName: name,
        customerPhone: p,
        whatsappOptIn: _waOptIn,
        skipped: false,
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
      // Solid label color — alpha labels look soft on Flutter web.
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

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final viewInsets = mq.viewInsets;
    // Whole-pixel padding avoids sub-pixel compositing blur on Flutter web.
    final bottomPad =
        (16 + viewInsets.bottom + mq.padding.bottom).roundToDouble();
    final isLandscape = mq.orientation == Orientation.landscape;
    final hasPhone = _phoneCtrl.text.trim().isNotEmpty;

    final nameField = TextField(
      controller: _nameCtrl,
      focusNode: _nameFocus,
      textInputAction: TextInputAction.next,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: _titleColor,
      ),
      onSubmitted: (_) => _phoneFocus.requestFocus(),
      decoration: _fieldDecoration(label: 'Name (optional)'),
    );

    final phoneField = TextField(
      controller: _phoneCtrl,
      focusNode: _phoneFocus,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: _titleColor,
      ),
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
      onChanged: (_) {
        setState(() {
          if (_phoneCtrl.text.trim().isEmpty) {
            _waOptIn = false;
          }
          // Clear validation error as the user edits.
          if (_phoneError != null) {
            _phoneError = null;
          }
        });
      },
      decoration: _fieldDecoration(
        label: 'WhatsApp mobile (optional)',
        hint: '98xxxxxx00',
        errorText: _phoneError,
      ),
    );

    // Prefer Padding over AnimatedPadding: animated transforms leave
    // fractional offsets that soft-blur text on web after the keyboard closes.
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
            ] else ...[
              nameField,
              const SizedBox(height: 12),
              phoneField,
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
            const SizedBox(height: 8),
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
