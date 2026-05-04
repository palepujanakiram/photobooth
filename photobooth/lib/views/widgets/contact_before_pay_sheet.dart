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
    builder: (ctx) => const _ContactBeforePaySheetBody(),
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

  /// Strips spaces, dashes, parentheses, and dots. Keeps a leading '+'.
  static String _normalizePhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll(RegExp(r'[\s\-().]'), '');
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
            'Enter mobile in international format, e.g. +9198xxxxxx00';
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

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final viewInsets = mq.viewInsets;
    final bottomPad =
        16 + viewInsets.bottom + mq.padding.bottom;
    final isLandscape = mq.orientation == Orientation.landscape;

    final nameField = TextField(
      controller: _nameCtrl,
      focusNode: _nameFocus,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _phoneFocus.requestFocus(),
      decoration: const InputDecoration(
        labelText: 'Name (optional)',
        border: OutlineInputBorder(),
      ),
    );

    final phoneField = TextField(
      controller: _phoneCtrl,
      focusNode: _phoneFocus,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
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
      decoration: InputDecoration(
        labelText: 'WhatsApp mobile (optional)',
        hintText: '+9198xxxxxx00',
        border: const OutlineInputBorder(),
        errorText: _phoneError,
      ),
    );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Get receipt on WhatsApp (optional)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add your mobile number to receive your receipt and digital copy on WhatsApp. '
                    'You can still scan the QR code for a digital copy either way.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: Colors.black.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 10),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _waOptIn,
              onChanged: _phoneCtrl.text.trim().isEmpty
                  ? null
                  : (v) => setState(() => _waOptIn = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Send receipt + digital copy on WhatsApp',
              ),
              subtitle: _phoneCtrl.text.trim().isEmpty
                  ? const Text(
                      'Enter a mobile number to enable WhatsApp delivery.',
                      style: TextStyle(fontSize: 12),
                    )
                  : const Text(
                      'We will only message you if payment is approved.',
                      style: TextStyle(fontSize: 12),
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
