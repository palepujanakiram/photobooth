import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../firebase_options.dart';
import 'fcm_payment_pending_store.dart';

/// Must be a top-level function. Registers with [FirebaseMessaging.onBackgroundMessage].
///
/// Runs while the app is backgrounded (Android enqueues [RemoteMessage] here).
/// Always logs to logcat with tag `fotozen.fcm` — filter in Android Studio / `adb logcat`.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  developer.log(
    'background handler messageId=${message.messageId} '
    'dataKeys=[${message.data.keys.join(',')}] '
    'hasNotification=${message.notification != null}',
    name: 'fotozen.fcm',
  );
  if (kDebugMode) {
    debugPrint(
      'FCM background isolate messageId=${message.messageId} data=${message.data}',
    );
  }
  await FcmPaymentPendingStore.persist(message);
}
