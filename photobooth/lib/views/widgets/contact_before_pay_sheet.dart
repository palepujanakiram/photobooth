import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

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
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  var waOptIn = false;

  return showModalBottomSheet<ContactBeforePayResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: 16 + MediaQuery.paddingOf(ctx).bottom,
        ),
        child: StatefulBuilder(
          builder: (ctx, setModalState) {
            final phone = phoneCtrl.text.trim();
            final effectiveWa = waOptIn && phone.isNotEmpty;

            return SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Get receipt on WhatsApp (optional)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Name (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        setModalState(() {
                          if (phoneCtrl.text.trim().isEmpty) {
                            waOptIn = false;
                          }
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'WhatsApp mobile (optional)',
                        hintText: '+9198xxxxxx00',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: waOptIn,
                      onChanged: phoneCtrl.text.trim().isEmpty
                          ? null
                          : (v) => setModalState(() => waOptIn = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Send receipt + digital copy on WhatsApp'),
                      subtitle: phoneCtrl.text.trim().isEmpty
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
                            onPressed: () => Navigator.pop(
                              ctx,
                              const ContactBeforePayResult(
                                customerName: '',
                                customerPhone: '',
                                whatsappOptIn: false,
                                skipped: true,
                              ),
                            ),
                            child: const Text('Skip'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(CupertinoIcons.arrow_right, size: 18),
                            onPressed: () {
                              final name = nameCtrl.text.trim();
                              final p = phoneCtrl.text.trim();
                              final wa = p.isNotEmpty && effectiveWa;
                              Navigator.pop(
                                ctx,
                                ContactBeforePayResult(
                                  customerName: name,
                                  customerPhone: p,
                                  whatsappOptIn: wa,
                                  skipped: false,
                                ),
                              );
                            },
                            label: const Text('Continue to pay'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}
