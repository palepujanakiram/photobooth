import 'dart:convert';
import 'dart:typed_data';

import 'local_receipt_slip.dart';

const _esc = 0x1b;
const _gs = 0x1d;
const _lf = 0x0a;

/// ESC/POS builder matching ZenAI `buildReceiptEscPosFromPdfInput`.
Uint8List buildLocalReceiptEscPos(LocalReceiptSlipInput input) {
  final textLines = buildLocalReceiptSlipLines(input);
  final merchantHeaderLineCount =
      wrapMerchantNameLines(input.merchant.merchantName).length;
  final chunks = <Uint8List>[_cmd([_esc, 0x40])];
  final preview = <String>[];

  for (var i = 0; i < textLines.length; i++) {
    final text = textLines[i];
    final isMerchantHeader = i < merchantHeaderLineCount;
    final isCenter = _isCenteredSlipLine(text, isMerchantHeader);
    final isTotal = text.startsWith('TOTAL');

    if (text == kLocalReceiptSlipQrPlaceholder) {
      preview.add('[QR CODE]');
      final share = input.shareUrl?.trim() ?? '';
      if (share.isNotEmpty) {
        chunks.add(_cmd([_esc, 0x61, 1]));
        chunks.add(buildLocalEscPosQrCode(share));
        chunks.add(_cmd([_lf]));
        chunks.add(_cmd([_esc, 0x61, 0]));
      }
      continue;
    }

    preview.add(text);
    if (isCenter) chunks.add(_cmd([_esc, 0x61, 1]));
    if (isMerchantHeader || isTotal) chunks.add(_cmd([_esc, 0x45, 1]));
    chunks.add(_line(text));
    if (isMerchantHeader || isTotal) chunks.add(_cmd([_esc, 0x45, 0]));
    if (isCenter) chunks.add(_cmd([_esc, 0x61, 0]));
  }

  chunks.add(
    Uint8List.fromList([
      ..._cmd([_esc, 0x64, 4]),
      ..._cmd([_gs, 0x56, 0x00]),
    ]),
  );
  return _concat(chunks);
}

/// ESC/POS QR via GS ( k (Epson / Posiflex-compatible).
Uint8List buildLocalEscPosQrCode(String data, {int moduleSize = 4}) {
  final payload = Uint8List.fromList(utf8.encode(data));
  final storeLen = payload.length + 3;
  final pL = storeLen & 0xff;
  final pH = (storeLen >> 8) & 0xff;
  final size = moduleSize.clamp(1, 16);

  return _concat([
    _cmd([_gs, 0x28, 0x6b, 4, 0, 49, 65, 50, 0]),
    _cmd([_gs, 0x28, 0x6b, 3, 0, 49, 67, size]),
    _cmd([_gs, 0x28, 0x6b, 3, 0, 49, 69, 48]),
    _concat([
      _cmd([_gs, 0x28, 0x6b, pL, pH, 49, 80, 48]),
      payload,
    ]),
    _cmd([_gs, 0x28, 0x6b, 3, 0, 49, 81, 48]),
  ]);
}

bool _isCenteredSlipLine(String text, bool isMerchantHeader) {
  return isMerchantHeader ||
      text == 'Thank you! Tag us @fotozenai' ||
      text == 'fotozenai.com' ||
      text == 'Scan to download your photo' ||
      text.startsWith('Valid for ') ||
      text == 'Computer-generated invoice.' ||
      text == 'No signature required.' ||
      text == kLocalReceiptSlipQrPlaceholder ||
      RegExp(r'^-+$').hasMatch(text);
}

Uint8List _cmd(List<int> bytes) => Uint8List.fromList(bytes);

Uint8List _line(String text) {
  final safe = text
      .replaceAll('\u20B9', 'Rs.')
      .replaceAll(RegExp(r'[^\x09\x0a\x0d\x20-\x7e]'), '?');
  return _concat([
    Uint8List.fromList(ascii.encode(safe)),
    _cmd([_lf]),
  ]);
}

Uint8List _concat(List<Uint8List> parts) {
  final len = parts.fold<int>(0, (a, b) => a + b.length);
  final out = Uint8List(len);
  var offset = 0;
  for (final p in parts) {
    out.setRange(offset, offset + p.length, p);
    offset += p.length;
  }
  return out;
}

const ascii = AsciiCodec(allowInvalid: true);
