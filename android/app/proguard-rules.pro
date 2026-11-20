# ==============================================================================
# VAULT R8 / PROGUARD SECURITY & INTEGRITY RULES
# ==============================================================================

# 1. Flutter Core Keep Rules
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }

# 2. Keep Native JNI methods and callbacks
-keepclasseswithmembernames class * {
    native <methods>;
}

# 3. Android Keystore & Biometrics
-keep class androidx.biometric.** { *; }
-dontwarn androidx.biometric.**

# 4. SQLite / SQLCipher
-keep class io.flutter.plugins.sqflite.** { *; }
-dontwarn io.flutter.plugins.sqflite.**

# 5. Flutter Secure Storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# 6. Tesseract OCR & PDF
-keep class com.tesseract_ocr.** { *; }
-dontwarn com.tesseract_ocr.**
-keep class com.viewer.pdfx.** { *; }
-dontwarn com.viewer.pdfx.**

# 7. Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# 8. Flutter Deferred Components & Google Play Core Suppressions
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-dontwarn io.flutter.embedding.android.FlutterPlayStoreSplitApplication
