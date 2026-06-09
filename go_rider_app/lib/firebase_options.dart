// Firebase configuration for Go Rider (com.godeli.go_rider)
// Project: godeli-fd48e
import "package:firebase_core/firebase_core.dart" show FirebaseOptions;
import "package:flutter/foundation.dart" show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError("Web not supported in Go Rider");
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError("Platform not supported");
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: "AIzaSyCHobf_56sLNTnxqP-J5naqni-bU0LWhq0",
    appId: "1:127745236552:android:d97b0551afbdf6d06c027d",
    messagingSenderId: "127745236552",
    projectId: "godeli-fd48e",
    storageBucket: "godeli-fd48e.firebasestorage.app",
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: "AIzaSyCHobf_56sLNTnxqP-J5naqni-bU0LWhq0",
    appId: "1:127745236552:ios:REPLACE_WITH_GORIDER_IOS_APP_ID",
    messagingSenderId: "127745236552",
    projectId: "godeli-fd48e",
    storageBucket: "godeli-fd48e.firebasestorage.app",
    iosBundleId: "com.godeli.goRider",
  );
}
