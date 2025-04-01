import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

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
        throw UnsupportedError('DefaultFirebaseOptions have not been configured for macos');
      case TargetPlatform.windows:
        throw UnsupportedError('DefaultFirebaseOptions have not been configured for windows');
      case TargetPlatform.linux:
        throw UnsupportedError('DefaultFirebaseOptions have not been configured for linux');
      default:
        throw UnsupportedError('DefaultFirebaseOptions are not supported for this platform.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA9OD_rP2WFc8oo7Jz9XzcXhAWuWazwHkI',
    appId: '1:557432249181:android:8f89075775b801024ae6b4',
    messagingSenderId: '557432249181',
    projectId: 'laboratoriodigital-982da',
    storageBucket: 'laboratoriodigital-982da.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'TU_API_KEY',
    appId: 'TU_APP_ID',
    messagingSenderId: 'TU_MESSAGING_SENDER_ID',
    projectId: 'laboratoriodigital-982da',
    storageBucket: 'laboratoriodigital-982da.appspot.com',
    iosBundleId: 'com.example.laboratoriodigital',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBkwyf2zhfKVHzaEvkjdFlmTC_EQ69mzh4',
    appId: '1:557432249181:web:8d3eee5e9ed5aa844ae6b4',
    messagingSenderId: '557432249181',
    projectId: 'laboratoriodigital-982da',
    authDomain: 'laboratoriodigital-982da.firebaseapp.com',
    storageBucket: 'laboratoriodigital-982da.firebasestorage.app',
    measurementId: 'G-GLW99CMKV3',
  );

}