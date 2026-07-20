import 'package:dio/dio.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/models/payment_initiate_result.dart';
import 'package:photobooth/models/preprocess_image_result.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/models/kiosk_frame_model.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/utils/exceptions.dart';

/// Minimal [ApiService] override for ViewModel unit tests (no network).
class FakeApiService extends ApiService {
  FakeApiService({
    this.kioskFrames = const [],
    this.validateKioskCodeResult = true,
    this.framesThrow = false,
    this.patchThrows = false,
    this.sessionResponse = const {'sessionId': 'sess-1'},
    this.initiatePaymentResult,
    this.fetchPaymentStatusResult,
    this.fetchSessionResult,
    this.initiatePaymentThrows = false,
  }) : super(
          dio: Dio(
            BaseOptions(
              baseUrl: AppConstants.kBaseUrl,
              validateStatus: (_) => true,
            ),
          ),
        );

  final List<KioskFrameModel> kioskFrames;
  final bool validateKioskCodeResult;
  final bool framesThrow;
  final bool patchThrows;
  final Map<String, dynamic> sessionResponse;
  final PaymentInitiateResult? initiatePaymentResult;
  final Map<String, dynamic>? fetchPaymentStatusResult;
  final Map<String, dynamic>? fetchSessionResult;
  final bool initiatePaymentThrows;

  int validateKioskCodeCalls = 0;
  int getKioskFramesCalls = 0;
  int initiatePaymentCalls = 0;
  int fetchPaymentStatusCalls = 0;
  int fetchSessionCalls = 0;

  @override
  Future<bool> validateKioskCode(String kioskCode) async {
    validateKioskCodeCalls++;
    return validateKioskCodeResult;
  }

  @override
  Future<List<KioskFrameModel>> getKioskFrames() async {
    getKioskFramesCalls++;
    if (framesThrow) throw ApiException('frames failed');
    return kioskFrames;
  }

  @override
  Future<List<ThemeModel>> getThemes() async => const [];

  @override
  Future<AppSettingsModel> getAppSettings() async =>
      AppSettingsModel(parallelImageCount: 1);

  @override
  Future<Map<String, dynamic>> fetchGenerationRun(String runId) async =>
      {'id': runId};

  @override
  Future<Map<String, dynamic>> updateSession({
    required String sessionId,
    String? userImageUrl,
    String? selectedThemeId,
    bool includeSelectedFrameId = false,
    String? selectedFrameId,
    int? personCount,
    Map<String, dynamic>? framingMetadata,
  }) async {
    if (patchThrows) throw ApiException('patch failed');
    return sessionResponse;
  }

  @override
  Future<PaymentInitiateResult> initiatePayment({
    required String sessionId,
    required int amount,
    String type = 'INITIAL',
    String? customerPhone,
    required String fcmToken,
  }) async {
    initiatePaymentCalls++;
    if (initiatePaymentThrows) {
      throw ApiException('initiate failed');
    }
    return initiatePaymentResult ??
        PaymentInitiateResult(
          id: 'pay-1',
          status: 'PENDING',
          qrImageUrl: 'https://rzp.io/i/testqr',
        );
  }

  @override
  Future<Map<String, dynamic>?> fetchPaymentStatus(
    String paymentId, {
    String? sessionId,
  }) async {
    fetchPaymentStatusCalls++;
    return fetchPaymentStatusResult;
  }

  @override
  Future<Map<String, dynamic>?> fetchSession(String sessionId) async {
    fetchSessionCalls++;
    return fetchSessionResult ?? sessionResponse;
  }

  @override
  Future<PreprocessImageResult> preprocessImage({
    required String sessionId,
    int? clientFaceCount,
  }) async {
    return const PreprocessImageResult(success: true, personCount: 2);
  }
}
