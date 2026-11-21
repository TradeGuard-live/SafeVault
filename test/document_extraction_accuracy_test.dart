import 'package:flutter_test/flutter_test.dart';
import 'package:vault/features/ocr/data/document_field_extractor.dart';
import 'package:vault/features/ocr/data/ocr_extractor.dart';

void main() {
  group('OCR-tolerant document extraction', () {
    test('normalizes number-plate and Aadhaar separator variants', () {
      const text = '''
        UNIQUE IDENTIFICATION AUTHORITY OF INDIA
        ADDRESS: 10 PARK STREET, KOLKATA 700016
        1234-5678-9012
      ''';

      final aadhaarFields = DocumentFieldExtractor.extractFields(
        fullText: text,
        documentType: 'Aadhaar Card',
      );
      final aadhaar = aadhaarFields.firstWhere(
        (field) => field.fieldName == 'Aadhaar Number',
      );
      expect(aadhaar.value, 'XXXX XXXX 9012');

      const pucText = '''
        POLLUTION UNDER CONTROL CERTIFICATE
        VEHICLE REG NO: MH 12-AB 1234
      ''';
      final pucFields = DocumentFieldExtractor.extractFields(
        fullText: pucText,
        documentType: 'PUC Certificate',
      );
      final registration = pucFields.firstWhere(
        (field) => field.fieldName == 'Vehicle Registration Number',
      );
      expect(registration.value, 'MH12AB1234');
    });

    test('passport fields are emitted only when supported by source text', () {
      const sparsePassport = '''
        PASSPORT
        PASSPORT NO: X1234567
      ''';

      final sparseFields = DocumentFieldExtractor.extractFields(
        fullText: sparsePassport,
        documentType: 'Passport',
      );
      final sparseNames = sparseFields.map((field) => field.fieldName).toSet();
      expect(sparseNames, contains('Passport Number'));
      expect(sparseNames, isNot(contains('Passport Type')));
      expect(sparseNames, isNot(contains('Country Code')));
      expect(sparseNames, isNot(contains('Nationality')));

      const labelledPassport = '''
        TYPE: P COUNTRY CODE: IND
        NATIONALITY: INDIAN
        DATE OF BIRTH: 12 / 12 / 1988
        DATE OF ISSUE: 01/01/2015
        DATE OF EXPIRY: 31/12/2024
      ''';
      final labelledFields = DocumentFieldExtractor.extractFields(
        fullText: labelledPassport,
        documentType: 'Passport',
      );
      final fields = {
        for (final field in labelledFields) field.fieldName: field.value,
      };
      expect(fields['Passport Type'], 'P (Personal)');
      expect(fields['Country Code'], 'IND');
      expect(fields['Nationality'], 'INDIAN');
      expect(fields['Date of Birth'], '12/12/1988');
      expect(fields['Date of Issue'], '01/01/2015');
      expect(fields['Date of Expiry'], '31/12/2024');
    });

    test(
      'metadata extraction understands ISO dates and rejects invalid dates',
      () {
        const isoLicence = '''
        DRIVING LICENCE
        DL NO: MH 14 20180012345
        VALID UPTO: 2038-01-09
      ''';
        final isoResult = OcrExtractor.extract(isoLicence);
        expect(isoResult.suggestedNumber, 'MH1420180012345');
        expect(isoResult.suggestedExpiryDate, DateTime(2038, 1, 9));

        const invalidDateLicence = '''
        DRIVING LICENCE
        VALID UPTO: 31/02/2038
      ''';
        final invalidResult = OcrExtractor.extract(invalidDateLicence);
        expect(invalidResult.suggestedExpiryDate, isNull);
      },
    );

    test('metadata prefers a labelled issue date over a date of birth', () {
      const licence = '''
        DRIVING LICENCE
        DATE OF BIRTH: 15/08/1988
        DATE OF ISSUE: 10/01/2018
      ''';

      final result = OcrExtractor.extract(licence);
      expect(result.suggestedIssueDate, DateTime(2018, 1, 10));
    });
  });
}
