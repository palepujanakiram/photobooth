/// Structured fields extracted from fotozen-sidecar error messages / JSON bodies.
class SidecarErrorInfo {
  const SidecarErrorInfo({
    this.code,
    this.edsError,
    this.statusCode,
    this.message,
  });

  final String? code;
  final int? edsError;
  final int? statusCode;
  final String? message;

  String? get edsErrorHex =>
      edsError == null ? null : '0x${edsError!.toRadixString(16)}';

  Map<String, Object?> toDetail() => {
        if (code != null) 'code': code,
        if (edsError != null) 'edsError': edsError,
        if (edsErrorHex != null) 'edsErrorHex': edsErrorHex,
        if (statusCode != null) 'statusCode': statusCode,
        if (message != null) 'error': message,
      };
}

final _statusRe = RegExp(r'\((\d{3})\):');
final _edsHexRe = RegExp(r'edsError=0x([0-9a-fA-F]+)');
final _edsDecRe = RegExp(r'edsError=(\d+)');
final _codeJsonRe = RegExp(r'"code"\s*:\s*"([^"]+)"');
final _codeBareRe = RegExp(
  r'\b(NO_CAMERA|CAMERA_BUSY|EDSDK_OPEN_COOLDOWN|EDSDK_CAPTURE_COOLDOWN|'
  r'EDSDK_CMD_FAILED|EDSDK_TIMEOUT|EDSDK_WORKER_DOWN|EDSDK_INIT_FAILED)\b',
);

/// Parse sidecar [StateError] / HTTP body text into filterable fields for logs.
SidecarErrorInfo parseSidecarError(Object error) {
  final text = '$error';
  final statusMatch = _statusRe.firstMatch(text);
  final statusCode = statusMatch != null
      ? int.tryParse(statusMatch.group(1)!)
      : null;

  int? edsError;
  final hex = _edsHexRe.firstMatch(text);
  if (hex != null) {
    edsError = int.tryParse(hex.group(1)!, radix: 16);
  } else {
    final dec = _edsDecRe.firstMatch(text);
    if (dec != null) edsError = int.tryParse(dec.group(1)!);
  }

  String? code = _codeJsonRe.firstMatch(text)?.group(1);
  code ??= _codeBareRe.firstMatch(text)?.group(1);

  final preview = text.length > 240 ? text.substring(0, 240) : text;
  return SidecarErrorInfo(
    code: code,
    edsError: edsError,
    statusCode: statusCode,
    message: preview,
  );
}
