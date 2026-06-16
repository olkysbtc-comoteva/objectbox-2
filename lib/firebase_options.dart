import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('La plataforma Web no está configurada.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError('La plataforma iOS no está configurada.');
      default:
        throw UnsupportedError('Plataforma no soportada.');
    }
  }

  // REEMPLAZA ESTOS DATOS CON LOS DE TU CONSOLA DE FIREBASE (App de Android)
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBFartgDZ3MWVerv6TN-YA34Z7H7Wd0Lp4',
    appId: '1:201381433499:android:5924f06c102e5552ae763e',
    messagingSenderId: '201381433499',
    projectId: 'comoteva-messaging',
    storageBucket: 'comoteva-messaging.firebasestorage.app',
  );
}