// Generated manually from android/app/google-services.json and
// ios/Runner/GoogleService-Info.plist (same project as FlutterFire would emit).

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for native mobile builds only. Web uses [isFirebaseConfigured].
class DefaultFirebaseOptions {
  static bool get isFirebaseConfigured => !kIsWeb;

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyACfUiMDrqanaSACyznQmoAZqu-_Jp8t9M',
    appId: '1:957532952151:android:f8a8844f87ba55fd563512',
    messagingSenderId: '957532952151',
    projectId: 'fotozenai-e615b',
    storageBucket: 'fotozenai-e615b.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCrpcK7LKYri3gfEURaOf3u0mUoouNVvXo',
    appId: '1:957084044258:ios:1c7bc1f482b161ca4787bb',
    messagingSenderId: '957084044258',
    projectId: 'aiphotobooth-3b5e2',
    storageBucket: 'aiphotobooth-3b5e2.firebasestorage.app',
    iosBundleId: 'com.srisarani.fotozenai',
  );
}
