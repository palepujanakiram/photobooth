import '../utils/app_strings.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';

/// Event / DNP kiosks must not talk to Selphy after DNP has the USB host.
///
/// `printImageSilent` used to always probe Canon Selphy (USB list, then Wi‑Fi)
/// even when DNP already printed. On Amlogic Mini PCs that ANRs the process
/// while the DNP interface is still claimed.
bool shouldAttemptSelphyPrint({
  required bool trySelphy,
  required bool dnpSucceeded,
}) {
  return trySelphy && !dnpSucceeded;
}

/// After always initiating DNP + Selphy, succeed if either printed.
void throwIfNoPhotoPrinterSucceeded({
  required bool dnpSucceeded,
  required bool selphySucceeded,
  Object? dnpError,
  Object? selphyError,
}) {
  if (dnpSucceeded || selphySucceeded) {
    return;
  }

  final dnpMsg = _messageOf(dnpError);
  final selphyMsg = _messageOf(selphyError);
  AppLogger.warning(
    'Photo print failed on DNP ($dnpMsg) and Selphy ($selphyMsg)',
  );
  throw PrintException(AppStrings.noPhotoPrinterConnected);
}

String _messageOf(Object? error) {
  if (error is PrintException) return error.message;
  if (error == null) return 'n/a';
  return error.toString();
}
