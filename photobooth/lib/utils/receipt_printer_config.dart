import '../models/app_settings_model.dart';

/// True when admin enabled the thermal receipt printer (USB/Wi-Fi auto-connect).
bool isReceiptPrinterEnabled(AppSettingsModel? settings) {
  return settings?.receiptPrinterEnabled == true;
}
