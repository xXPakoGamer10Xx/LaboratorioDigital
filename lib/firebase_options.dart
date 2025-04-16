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
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError('DefaultFirebaseOptions have not been configured for linux');
      default:
        throw UnsupportedError('DefaultFirebaseOptions are not supported for this platform.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA9OD_rP2WFc8oo7Jz9XzcXhAWuWazwHkI',
    appId: '1:557432249181:android:8e56162747f7444e4ae6b4',
    messagingSenderId: '557432249181',
    projectId: 'laboratoriodigital-982da',
    storageBucket: 'laboratoriodigital-982da.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBgYLkq0m-ceT_uRn9ozdWLNcq_03MYJF8',
    appId: '1:557432249181:ios:fd4d59c9bbf135e14ae6b4',
    messagingSenderId: '557432249181',
    projectId: 'laboratoriodigital-982da',
    storageBucket: 'laboratoriodigital-982da.firebasestorage.app',
    iosBundleId: 'com.example.laboratorioDigital',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBkwyf2zhfKVHzaEvkjdFlmTC_EQ69mzh4',
    appId: '1:557432249181:web:0f22d3e1dfd96b424ae6b4',
    messagingSenderId: '557432249181',
    projectId: 'laboratoriodigital-982da',
    authDomain: 'laboratoriodigital-982da.firebaseapp.com',
    storageBucket: 'laboratoriodigital-982da.firebasestorage.app',
    measurementId: 'G-FPESSHHV7V',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBgYLkq0m-ceT_uRn9ozdWLNcq_03MYJF8',
    appId: '1:557432249181:ios:fd4d59c9bbf135e14ae6b4',
    messagingSenderId: '557432249181',
    projectId: 'laboratoriodigital-982da',
    storageBucket: 'laboratoriodigital-982da.firebasestorage.app',
    iosBundleId: 'com.example.laboratorioDigital',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBkwyf2zhfKVHzaEvkjdFlmTC_EQ69mzh4',
    appId: '1:557432249181:web:aedb1e9976219ef94ae6b4',
    messagingSenderId: '557432249181',
    projectId: 'laboratoriodigital-982da',
    authDomain: 'laboratoriodigital-982da.firebaseapp.com',
    storageBucket: 'laboratoriodigital-982da.firebasestorage.app',
    measurementId: 'G-5Y13G26XH8',
  );

}