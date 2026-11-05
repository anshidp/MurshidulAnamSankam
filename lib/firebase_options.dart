import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBcKFUCqqwZwR9M7uHr45tHh6t7Uj_vBz0',
    appId: '1:841471901412:web:ba1cfd20c5a66fbf36b6f1',
    messagingSenderId: '841471901412',
    projectId: 'murshidulanamsangam-cd186',
    authDomain: 'murshidulanamsangam-cd186.firebaseapp.com',
    storageBucket: 'murshidulanamsangam-cd186.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBCvzgVOA-8rylyhIckarugeVOiW7KjFCc',
    appId: '1:841471901412:android:85d8e039e63fe8a236b6f1',
    messagingSenderId: '841471901412',
    projectId: 'murshidulanamsangam-cd186',
    storageBucket: 'murshidulanamsangam-cd186.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'DUMMY_API_KEY',
    appId: 'DUMMY_APP_ID',
    messagingSenderId: 'DUMMY_SENDER_ID',
    projectId: 'DUMMY_PROJECT_ID',
    storageBucket: 'DUMMY_STORAGE_BUCKET',
    iosBundleId: 'DUMMY_BUNDLE_ID',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'DUMMY_API_KEY',
    appId: 'DUMMY_APP_ID',
    messagingSenderId: 'DUMMY_SENDER_ID',
    projectId: 'DUMMY_PROJECT_ID',
    storageBucket: 'DUMMY_STORAGE_BUCKET',
    iosBundleId: 'DUMMY_BUNDLE_ID',
  );
}
