// File generated for CatchUP Firebase connection.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for CatchUP seafood inventory management.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDb0pdTU-_Q_QiDkYDVQMS_vfg4-WVt64k',
    appId: '1:333385693419:web:c62ef048a71140ba89e6ae',
    messagingSenderId: '333385693419',
    projectId: 'catchup-b311f',
    authDomain: 'catchup-b311f.firebaseapp.com',
    storageBucket: 'catchup-b311f.firebasestorage.app',
    measurementId: 'G-V6Z3R26K6V',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyApZ8cxOnQI6Ybi3KoxHWvx4Gi1zK8a3Fs',
    appId: '1:333385693419:android:642f04f8a57bdde689e6ae',
    messagingSenderId: '333385693419',
    projectId: 'catchup-b311f',
    storageBucket: 'catchup-b311f.firebasestorage.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDb0pdTU-_Q_QiDkYDVQMS_vfg4-WVt64k',
    appId: '1:333385693419:web:c09228b4441de84289e6ae',
    messagingSenderId: '333385693419',
    projectId: 'catchup-b311f',
    authDomain: 'catchup-b311f.firebaseapp.com',
    storageBucket: 'catchup-b311f.firebasestorage.app',
    measurementId: 'G-NFMNXWFPLN',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDb0pdTU-_Q_QiDkYDVQMS_vfg4-WVt64k',
    appId: '1:333385693419:web:c62ef048a71140ba89e6ae',
    messagingSenderId: '333385693419',
    projectId: 'catchup-b311f',
    authDomain: 'catchup-b311f.firebaseapp.com',
    storageBucket: 'catchup-b311f.firebasestorage.app',
  );

  static bool get isPlaceholder => false;
}
