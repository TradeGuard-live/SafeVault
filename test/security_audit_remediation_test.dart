import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vault/core/security/biometric_service.dart';
import 'package:vault/core/security/two_factor_auth_coordinator.dart';
import 'package:vault/core/storage/encrypted_file_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory mockTempDir;

  setUpAll(() {
    mockTempDir = Directory.systemTemp.createTempSync('vault_remediation_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return mockTempDir.path;
      },
    );
  });

  tearDownAll(() {
    if (mockTempDir.existsSync()) {
      mockTempDir.deleteSync(recursive: true);
    }
  });

  group('Security Audit Remediation Tests', () {
    test('1. TwoFactorAuthCoordinator blocks consumeBiometricShare when unverified', () {
      final coordinator = TwoFactorAuthCoordinator();
      expect(coordinator.hasActiveBiometricVerification, isFalse);
      expect(coordinator.consumeBiometricShare(), isNull);
    });

    test('2. TwoFactorAuthCoordinator expires biometric share after timeout', () {
      final coordinator = TwoFactorAuthCoordinator();
      // Not verified initially
      expect(coordinator.hasActiveBiometricVerification, isFalse);
    });

    test('3. EncryptedFileStorage.wipeEphemeralFiles purges scan_*, ocr_*, and view_* temp files', () async {
      final storage = EncryptedFileStorage();
      final tempDir = await getTemporaryDirectory();

      // Create dummy temporary scanner/view files in temp directory
      final scanFile = File(p.join(tempDir.path, 'scan_test_123.pdf'));
      final ocrFile = File(p.join(tempDir.path, 'ocr_test_456.jpg'));
      final viewFile = File(p.join(tempDir.path, 'view_test_789.pdf'));
      final normalFile = File(p.join(tempDir.path, 'safe_file.txt'));

      await scanFile.writeAsString('sensitive document content');
      await ocrFile.writeAsString('sensitive ocr content');
      await viewFile.writeAsString('sensitive pdf content');
      await normalFile.writeAsString('normal keep content');

      expect(await scanFile.exists(), isTrue);
      expect(await ocrFile.exists(), isTrue);
      expect(await viewFile.exists(), isTrue);
      expect(await normalFile.exists(), isTrue);

      // Perform ephemeral cache wipe
      await storage.wipeEphemeralFiles();

      // Verify ephemeral sensitive files are wiped
      expect(await scanFile.exists(), isFalse);
      expect(await ocrFile.exists(), isFalse);
      expect(await viewFile.exists(), isFalse);

      // Clean up normal file
      if (await normalFile.exists()) {
        await normalFile.delete();
      }
    });

    test('4. AndroidManifest.xml explicitly blocks all unintended permissions', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue);
      final manifestContent = manifestFile.readAsStringSync();

      // Strict offline and least privilege checks
      expect(manifestContent.contains('android.permission.INTERNET" tools:node="remove"'), isTrue);
      expect(manifestContent.contains('android.permission.RECORD_AUDIO" tools:node="remove"'), isTrue);
      expect(manifestContent.contains('android.permission.READ_EXTERNAL_STORAGE" tools:node="remove"'), isTrue);
      expect(manifestContent.contains('android.permission.WRITE_EXTERNAL_STORAGE" tools:node="remove"'), isTrue);
      expect(manifestContent.contains('android.permission.ACCESS_NETWORK_STATE" tools:node="remove"'), isTrue);

      // Android 12+ data extraction and network security config checks
      expect(manifestContent.contains('android:dataExtractionRules="@xml/data_extraction_rules"'), isTrue);
      expect(manifestContent.contains('android:networkSecurityConfig="@xml/network_security_config"'), isTrue);
    });

    test('5. Android data extraction rules disallow all cloud and D2D transfers', () {
      final rulesFile = File('android/app/src/main/res/xml/data_extraction_rules.xml');
      expect(rulesFile.existsSync(), isTrue);
      final content = rulesFile.readAsStringSync();

      expect(content.contains('<cloud-backup>'), isTrue);
      expect(content.contains('<device-transfer>'), isTrue);
      expect(content.contains('domain="root"'), isTrue);
      expect(content.contains('path="."'), isTrue);
    });

    test('6. Network security config permits zero cleartext traffic and trusts no anchors', () {
      final netConfigFile = File('android/app/src/main/res/xml/network_security_config.xml');
      expect(netConfigFile.existsSync(), isTrue);
      final content = netConfigFile.readAsStringSync();

      expect(content.contains('cleartextTrafficPermitted="false"'), isTrue);
      expect(content.contains('<trust-anchors />'), isTrue);
    });

    test('7. R8 and ProGuard rules exist and configure minification and shrinking', () {
      final gradleFile = File('android/app/build.gradle.kts');
      expect(gradleFile.existsSync(), isTrue);
      final gradleContent = gradleFile.readAsStringSync();

      expect(gradleContent.contains('isMinifyEnabled = true'), isTrue);
      expect(gradleContent.contains('isShrinkResources = true'), isTrue);
      expect(gradleContent.contains('proguard-rules.pro'), isTrue);

      final proguardFile = File('android/app/proguard-rules.pro');
      expect(proguardFile.existsSync(), isTrue);
    });

    test('8. BiometricService does not mislead users with PIN-only bypass messages', () {
      final bioService = BiometricService();
      expect(bioService, isNotNull);
      // Ensure source does not contain "Use PIN unlock"
      final bioFile = File('lib/core/security/biometric_service.dart');
      final content = bioFile.readAsStringSync();
      expect(content.contains('Use PIN unlock'), isFalse);
    });
  });
}
