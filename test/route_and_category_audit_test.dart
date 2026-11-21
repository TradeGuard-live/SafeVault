import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vault/core/constants/category_constants.dart';
import 'package:vault/core/routes/app_router.dart';
import 'package:vault/core/security/vault_session.dart';
import 'package:vault/features/ocr/data/smart_document_classifier.dart';
import 'package:vault/features/authentication/presentation/auth_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Router stability', () {
    test('appRouterProvider returns a stable GoRouter instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = container.read(appRouterProvider);
      final second = container.read(appRouterProvider);
      expect(identical(first, second), isTrue);
    });

    test('VaultSession notifications do not recreate the router', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final session = container.read(vaultSessionProvider);
      final before = container.read(appRouterProvider);
      session.notifyListeners();
      final after = container.read(appRouterProvider);
      expect(identical(before, after), isTrue);
    });
  });

  group('Category integrity', () {
    final validIds = CategoryConstants.defaultCategories.map((c) => c.id).toSet();

    test('classifier category ids belong to default categories', () {
      final samples = <String>[
        'INCOME TAX DEPARTMENT GOVT OF INDIA PERMANENT ACCOUNT NUMBER ABCDE1234F',
        'UNIQUE IDENTIFICATION AUTHORITY OF INDIA AADHAAR 1234 5678 9012',
        'MOTOR INSURANCE PACKAGE POLICY REGISTRATION NO MH12AB1234 INSURED VEHICLE',
        'UNION OF INDIA DRIVING LICENCE DL0420110012345',
        'FORM 23 CERTIFICATE OF REGISTRATION CHASSIS NO MA3EKA12S00123456 ENGINE NO K12MN1234567',
        'POLLUTION UNDER CONTROL CERTIFICATE PUCC',
        'PASSPORT REPUBLIC OF INDIA NATIONALITY INDIAN',
        'ELECTION COMMISSION VOTER IDENTITY',
        'BIRTH CERTIFICATE REGISTRAR OF BIRTH',
        'HDFC BANK STATEMENT OF ACCOUNT ACCOUNT NUMBER IFSC',
        'FORM 16 ASSESSMENT YEAR INCOME TAX RETURN',
        'UNIVERSITY STATEMENT OF MARKS MARK SHEET',
        'RENTAL AGREEMENT LEASE AGREEMENT',
        'LABORATORY REPORT PATHOLOGY DIAGNOSTIC REPORT',
      ];

      for (final sample in samples) {
        final result = SmartDocumentClassifier.classify(sample);
        expect(
          validIds.contains(result.categoryId),
          isTrue,
          reason: 'Invalid category id: ${result.categoryId}',
        );
        expect(result.categoryId, isNot('financial'));
      }
    });

    test('vehicle insurance wins over driving licence when both appear', () {
      const text = '''
      MOTOR INSURANCE PACKAGE POLICY
      INSURED VEHICLE REGISTRATION NO MH12AB1234
      DRIVER LICENCE NO DL0420110012345
      TRANSPORT DEPARTMENT
      ''';
      final result = SmartDocumentClassifier.classify(text);
      expect(result.documentType, 'Vehicle Insurance');
      expect(result.categoryId, 'vehicle_documents');
    });

    test('default categories contain financial_documents, not financial', () {
      expect(validIds.contains('financial_documents'), isTrue);
      expect(validIds.contains('financial'), isFalse);
    });
  });
}