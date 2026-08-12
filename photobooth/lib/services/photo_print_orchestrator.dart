import '../utils/app_strings.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';

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
