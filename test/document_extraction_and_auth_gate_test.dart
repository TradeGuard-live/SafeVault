import 'package:flutter_test/flutter_test.dart';
import 'package:vault/core/security/authentication_gate.dart';
import 'package:vault/core/security/vault_session.dart';
import 'package:vault/features/ocr/data/document_field_extractor.dart';
import 'package:vault/features/ocr/domain/document_extraction_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthenticationGate Tests', () {
    late VaultSession session;
    late AuthenticationGate gate;

    setUp(() {
      session = VaultSession();
      gate = AuthenticationGate(session);
    });

    test('Pending action is recorded and retrieved correctly', () {
      final action = PendingVaultAction(
        type: VaultActionType.revealBankDetails,
        targetId: 'bank_acc_101',
        targetName: 'HDFC Bank Account',
        returnRoute: '/bank-account/bank_acc_101',
      );

      gate.setPendingAction(action);
      expect(gate.pendingAction, isNotNull);
      expect(gate.pendingAction!.targetId, 'bank_acc_101');
      expect(gate.pendingAction!.returnRoute, '/bank-account/bank_acc_101');
      expect(gate.pendingAction!.isExpired, isFalse);
    });

    test('consumePendingAction matches targetId and executes action', () {
      final action = PendingVaultAction(
        type: VaultActionType.revealPassword,
        targetId: 'pwd_202',
        targetName: 'Email Password',
        returnRoute: '/password/pwd_202',
      );

      gate.setPendingAction(action);

      // Attempt with wrong target ID
      final wrongConsumed = gate.consumePendingAction('wrong_id');
      expect(wrongConsumed, isNull);
      expect(gate.pendingAction, isNotNull);

      // Attempt with correct target ID
      final consumed = gate.consumePendingAction('pwd_202');
      expect(consumed, isNotNull);
      expect(consumed!.type, VaultActionType.revealPassword);
      expect(consumed.isExecuted, isTrue);
      expect(gate.pendingAction, isNull);
    });

    test('consumePendingAction discards expired actions (> 5 minutes)', () {
      final oldAction = PendingVaultAction(
        type: VaultActionType.revealDocumentField,
        targetId: 'doc_303',
        createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
      );

      gate.setPendingAction(oldAction);
      expect(gate.pendingAction!.isExpired, isTrue);

      final consumed = gate.consumePendingAction('doc_303');
      expect(consumed, isNull);
      expect(gate.pendingAction, isNull);
    });

    test('clearPendingAction clears the pending state', () {
      final action = PendingVaultAction(
        type: VaultActionType.shareDocument,
        targetId: 'doc_404',
      );

      gate.setPendingAction(action);
      expect(gate.pendingAction, isNotNull);

      gate.clearPendingAction();
      expect(gate.pendingAction, isNull);
    });
  });

  group('DocumentFieldExtractor Comprehensive Schemas', () {
    test('1. Vehicle RC Book extracts 20+ fields accurately', () {
      const rcText = '''
        GOVERNMENT OF MAHARASHTRA
        TRANSPORT DEPARTMENT - FORM 23
        CERTIFICATE OF REGISTRATION
        REG. NO: MH12AB1234
        REG. DATE: 12/04/2021
        CHASSIS NO: MA3ERB12S00123456
        ENGINE NO: K12MN1234567
        REGISTERED OWNER: RAHUL RAMESH SHARMA
        S/O: RAMESH SHARMA
        ADDRESS: FLAT 402, SUNSHINE APARTMENTS, KOTHRUD, PUNE 411038
        CLASS OF VEHICLE: MOTOR CAR (LMV)
        MAKER: MARUTI SUZUKI INDIA LTD
        MODEL: SWIFT DZIRE VXI
        TYPE OF BODY: SALOON
        FUEL: PETROL
        COLOUR: ARCTIC WHITE
        SEATING CAPACITY: 5
        STANDING CAPACITY: 0
        MFG. DATE: 03/2021
        GVW: 1405 KG
        UNLADEN WT: 965 KG
        CUBIC CAPACITY: 1197 CC
        WHEELBASE: 2450 MM
        NO OF CYL: 4
        FITNESS UPTO: 11/04/2036
        TAX UPTO: LIFE TIME
        ISSUING AUTHORITY: RTO PUNE MH-12
        HYPOTHECATED TO: HDFC BANK LTD
      ''';

      final fields = DocumentFieldExtractor.extractFields(
        fullText: rcText,
        documentType: 'Vehicle RC Book',
      );

      final fieldMap = {for (var f in fields) f.fieldName: f.value};

      expect(fieldMap['Registration Number'], 'MH12AB1234');
      expect(fieldMap['Registration Date'], '12/04/2021');
      expect(fieldMap['Chassis Number'], contains('MA3ERB12S00123456'));
      expect(fieldMap['Engine Number'], contains('K12MN1234567'));
      expect(fieldMap['Fuel Type'], 'PETROL');
      expect(fieldMap['Seating Capacity'], '5');
      expect(fieldMap['Standing Capacity'], '0');
      expect(fieldMap['Manufactured Date'], '03/2021');
      expect(fieldMap['Gross Vehicle Weight (GVW)'], contains('1405'));
      expect(fieldMap['Unladen Weight'], contains('965'));
      expect(fieldMap['Cubic Capacity (CC)'], contains('1197'));
      expect(fieldMap['Wheelbase'], contains('2450'));
      expect(fieldMap['Number of Cylinders'], '4');
      expect(fieldMap['Fitness Upto'], '11/04/2036');
      expect(fieldMap['Tax Status / Upto'], contains('LIFE TIME'));
      expect(fieldMap['Financier / Hypothecation'], contains('HDFC BANK LTD'));
      expect(fields.length, greaterThanOrEqualTo(15));
    });

    test(
      '2. Driving Licence extracts DL number, validity, classes and authority',
      () {
        const dlText = '''
        UNION OF INDIA - DRIVING LICENCE
        LICENCE NO: MH1420180012345
        NAME: AMIT VIKRAM VERMA
        S/O: VIKRAM VERMA
        DOB: 15/08/1992
        BLOOD GROUP: B+
        ISSUE DATE: 10/01/2018
        VALIDITY NT: 14/08/2032
        MCWG LMV
        LICENSING AUTHORITY: RTO PCMC PUNE
      ''';

        final fields = DocumentFieldExtractor.extractFields(
          fullText: dlText,
          documentType: 'Driving Licence',
        );

        final fieldMap = {for (var f in fields) f.fieldName: f.value};

        expect(fieldMap['Licence Number'], 'MH1420180012345');
        expect(fieldMap['Date of Birth'], '15/08/1992');
        expect(fieldMap['Blood Group'], 'B+');
        expect(fieldMap['Issue Date'], '10/01/2018');
        expect(fieldMap['Validity (Non-Transport)'], '14/08/2032');
        expect(fieldMap['Authorised Vehicle Class'], contains('MCWG'));
        expect(fieldMap['Authorised Vehicle Class'], contains('LMV'));
      },
    );

    test('3. Aadhaar Card extracts masked number and personal details', () {
      const aadhaarText = '''
        GOVERNMENT OF INDIA
        ROHIT KUMAR
        DOB: 24/11/1995
        MALE
        C/O: SURESH KUMAR
        ADDRESS: 123 MG ROAD, BENGALURU, KARNATAKA
        560001
        9876 5432 1098
      ''';

      final fields = DocumentFieldExtractor.extractFields(
        fullText: aadhaarText,
        documentType: 'Aadhaar Card',
      );

      final fieldMap = {for (var f in fields) f.fieldName: f.value};

      expect(fieldMap['Aadhaar Number'], 'XXXX XXXX 1098');
      expect(fieldMap['Date of Birth'], '24/11/1995');
      expect(fieldMap['Gender'], 'MALE');
      expect(fieldMap['PIN Code'], '560001');
    });

    test('4. PAN Card extracts PAN, DOB and Names', () {
      const panText = '''
        INCOME TAX DEPARTMENT
        GOVT. OF INDIA
        PRIYA ANAND
        FATHER NAME: ANAND PRAKASH
        DOB: 05/03/1990
        ABCDE1234F
        PERMANENT ACCOUNT NUMBER CARD
      ''';

      final fields = DocumentFieldExtractor.extractFields(
        fullText: panText,
        documentType: 'PAN Card',
      );

      final fieldMap = {for (var f in fields) f.fieldName: f.value};

      expect(fieldMap['PAN Number'], 'ABCDE1234F');
      expect(fieldMap['Date of Birth'], '05/03/1990');
      expect(fieldMap['Father\'s Name'], contains('ANAND'));
    });

    test(
      '5. PUC Certificate extracts vehicle reg, dates and emission readings',
      () {
        const pucText = '''
        POLLUTION UNDER CONTROL CERTIFICATE
        PUCC NO: MH123456789
        VEHICLE REG NO: DL01AB9999
        DATE OF ISSUE: 01/10/2023
        VALID UPTO: 30/09/2024
        CARBON MONOXIDE (CO): 0.25
        HYDROCARBONS (HC): 120 PPM
        RESULT: PASS COMPLIANT
      ''';

        final fields = DocumentFieldExtractor.extractFields(
          fullText: pucText,
          documentType: 'PUC Certificate',
        );

        final fieldMap = {for (var f in fields) f.fieldName: f.value};

        expect(fieldMap['Certificate Number'], 'MH123456789');
        expect(fieldMap['Vehicle Registration Number'], 'DL01AB9999');
        expect(fieldMap['Date of Issue'], '01/10/2023');
        expect(fieldMap['Expiry Date'], '30/09/2024');
        expect(fieldMap['CO Emission Value (%)'], '0.25');
        expect(fieldMap['HC Emission Value (PPM)'], '120');
        expect(fieldMap['Compliance Status'], contains('Pass'));
      },
    );

    test('6. Vehicle Insurance extracts policy details, IDV and premium', () {
      const insText = '''
        ICICI LOMBARD GENERAL INSURANCE CO. LTD.
        PRIVATE CAR PACKAGE POLICY
        POLICY NUMBER: POL-9876543210
        INSURED NAME: VIKAS MEHTA
        VEHICLE REG NO: KA03MM4567
        POLICY START: 15/06/2023
        EXPIRY DATE: 14/06/2024
        IDV: 650,000
        TOTAL PREMIUM: 14,250.00
      ''';

      final fields = DocumentFieldExtractor.extractFields(
        fullText: insText,
        documentType: 'Vehicle Insurance',
      );

      final fieldMap = {for (var f in fields) f.fieldName: f.value};

      expect(fieldMap['Policy Number'], 'POL-9876543210');
      expect(fieldMap['Insurance Company'], 'ICICI LOMBARD');
      expect(fieldMap['Vehicle Registration Number'], 'KA03MM4567');
      expect(fieldMap['Policy Start Date'], '15/06/2023');
      expect(fieldMap['Policy Expiry Date'], '14/06/2024');
      expect(fieldMap['IDV (Insured Declared Value)'], '₹650,000');
      expect(fieldMap['Premium Amount'], '₹14,250.00');
    });

    test('7. Passport extracts passport number, nationality and dates', () {
      const passText = '''
        PASSPORT - REPUBLIC OF INDIA
        PASSPORT NO: Z1234567
        SURNAME: PATEL
        GIVEN NAMES: DEEPAK
        NATIONALITY: INDIAN
        SEX: M
        DOB: 12/12/1988
        DATE OF ISSUE: 01/01/2015
        DATE OF EXPIRY: 31/12/2024
        PLACE OF BIRTH: AHMEDABAD
      ''';

      final fields = DocumentFieldExtractor.extractFields(
        fullText: passText,
        documentType: 'Passport',
      );

      final fieldMap = {for (var f in fields) f.fieldName: f.value};

      expect(fieldMap['Passport Number'], 'Z1234567');
      expect(fieldMap['Surname'], 'PATEL');
      expect(fieldMap['Given Names'], 'DEEPAK');
      expect(fieldMap['Nationality'], 'INDIAN');
      expect(fieldMap['Sex'], 'Male');
      expect(fieldMap['Date of Birth'], '12/12/1988');
      expect(fieldMap['Date of Expiry'], '31/12/2024');
      expect(fieldMap['Place of Birth'], 'AHMEDABAD');
    });

    test(
      '8. Bank Document filters sensitive secrets (NO PIN, NO CVV, NO OTP)',
      () {
        const bankText = '''
        STATE BANK OF INDIA
        STATEMENT OF ACCOUNT
        ACCOUNT HOLDER: SNEHA KULKARNI
        ACCOUNT NUMBER: 123456789012
        IFSC: SBIN0001234
        BRANCH: MG ROAD PUNE
        MICR: 411002015
        SAVINGS ACCOUNT
        SECURITY TEST:
        ATM PIN: 1234
        CVV: 567
        CARD EXPIRY: 12/28
        OTP: 987654
      ''';

        final fields = DocumentFieldExtractor.extractFields(
          fullText: bankText,
          documentType: 'Bank Document',
        );

        final fieldMap = {for (var f in fields) f.fieldName: f.value};

        expect(fieldMap['Bank Name'], 'STATE BANK OF INDIA');
        expect(fieldMap['Account Number'], '123456789012');
        expect(fieldMap['IFSC Code'], 'SBIN0001234');
        expect(fieldMap['Branch Name'], 'MG ROAD PUNE');
        expect(fieldMap['Account Type'], 'Savings Account');

        // Crucial Security Verification: No sensitive secrets extracted!
        expect(fieldMap.containsKey('ATM PIN'), isFalse);
        expect(fieldMap.containsKey('CVV'), isFalse);
        expect(fieldMap.containsKey('OTP'), isFalse);
        expect(fieldMap.containsKey('Card Expiry'), isFalse);
      },
    );

    test(
      '9. Education Certificate extracts student, roll, degree and university',
      () {
        const eduText = '''
        CENTRAL BOARD OF SECONDARY EDUCATION
        STATEMENT OF MARKS
        NAME OF CANDIDATE: ARJUN KAPOOR
        ROLL NO: 12345678
        BACHELOR OF TECHNOLOGY
        YEAR OF PASSING: 2020
        CGPA: 8.75 CGPA
      ''';

        final fields = DocumentFieldExtractor.extractFields(
          fullText: eduText,
          documentType: 'Education Certificate',
        );

        final fieldMap = {for (var f in fields) f.fieldName: f.value};

        expect(fieldMap['Roll / Registration Number'], '12345678');
        expect(fieldMap['Degree / Course'], 'BACHELOR OF TECHNOLOGY');
        expect(
          fieldMap['Institution / University'],
          'CENTRAL BOARD OF SECONDARY EDUCATION',
        );
        expect(fieldMap['Passing Year'], '2020');
        expect(fieldMap['Grade / CGPA / Percentage'], '8.75 CGPA');
      },
    );

    test('10. Generic document extracts discovered key-value pairs', () {
      const genText = '''
        INVOICE RECEIPT
        DATE: 15/11/2023
        NUMBER: INV-2023-999
        Vendor Name : ACME Corporation
        Tax ID : TX-98765432
        Total Items : 5
      ''';

      final fields = DocumentFieldExtractor.extractFields(
        fullText: genText,
        documentType: 'General Document',
      );

      final fieldMap = {for (var f in fields) f.fieldName: f.value};

      expect(fieldMap['Document Date'], '15/11/2023');
      expect(fieldMap['Reference Number'], 'INV-2023-999');
      expect(fieldMap['Vendor Name'], 'ACME Corporation');
      expect(fieldMap['Tax Id'], 'TX-98765432');
    });

    test('11. Property / Rent Agreement extracts lease details accurately', () {
      const propText = '''
        RESIDENTIAL RENT AGREEMENT
        This agreement made on 01/06/2023 between:
        FIRST PARTY / LESSOR: SURESH CHANDRA AGRAWAL
        SECOND PARTY / LESSEE: AMIT VIKRAM VERMA
        PREMISES: FLAT NO 302, PALM HEIGHTS, SECTOR 62, NOIDA
        AGREEMENT DATE: 01/06/2023
        LEASE PERIOD: 11 MONTHS
        MONTHLY RENT: RS. 28,000
        SECURITY DEPOSIT: RS. 56,000
        REGISTRATION NO: REG/NOIDA/2023/8821
      ''';

      final fields = DocumentFieldExtractor.extractFields(
        fullText: propText,
        documentType: 'Rent Agreements',
      );

      final fieldMap = {for (var f in fields) f.fieldName: f.value};

      expect(fieldMap['Agreement Type'], 'Rent / Lease Agreement');
      expect(fieldMap['Lessor / Owner Name'], 'SURESH CHANDRA AGRAWAL');
      expect(fieldMap['Lessee / Tenant Name'], 'AMIT VIKRAM VERMA');
      expect(
        fieldMap['Property Address'],
        'FLAT NO 302, PALM HEIGHTS, SECTOR 62, NOIDA',
      );
      expect(fieldMap['Agreement Date'], '01/06/2023');
      expect(fieldMap['Lease Period'], '11 MONTHS');
      expect(fieldMap['Monthly Rent'], '28,000');
      expect(fieldMap['Security Deposit'], '56,000');
      expect(fieldMap['Registration / Document No'], 'REG/NOIDA/2023/8821');
    });

    test('12. Medical Report extracts diagnostic metadata accurately', () {
      const medText = '''
        METROPOLIS HEALTHCARE & DIAGNOSTICS LAB
        PATIENT NAME: SUNITA DESHMUKH
        AGE / GENDER: 45 YRS / FEMALE
        CONSULTANT: DR. RAJESH KULKARNI
        HOSPITAL: RUBY HALL CLINIC
        REPORT DATE: 18/09/2023
        INVESTIGATION: COMPLETE BLOOD COUNT (CBC)
        UHID: UHID-2023-88912
      ''';

      final fields = DocumentFieldExtractor.extractFields(
        fullText: medText,
        documentType: 'Medical Reports',
      );

      final fieldMap = {for (var f in fields) f.fieldName: f.value};

      expect(fieldMap['Patient Name'], 'SUNITA DESHMUKH');
      expect(fieldMap['Age / Gender'], '45 YRS / FEMALE');
      expect(fieldMap['Consulting Doctor'], 'RAJESH KULKARNI');
      expect(fieldMap['Hospital / Lab Name'], 'RUBY HALL CLINIC');
      expect(fieldMap['Report Date'], '18/09/2023');
      expect(
        fieldMap['Investigation / Test Name'],
        'COMPLETE BLOOD COUNT (CBC)',
      );
      expect(fieldMap['Patient UHID / Ref No'], 'UHID-2023-88912');
    });
  });

  group('ExtractedFieldModel Model Tests', () {
    test('ExtractedFieldModel serialization and selection flags', () {
      final now = DateTime.now();
      final model = ExtractedFieldModel(
        id: 'field_1',
        extractionId: 'ext_1',
        documentId: 'doc_1',
        fieldName: 'Chassis Number',
        encryptedValue: 'enc_chassis_123',
        plainValue: 'MA3ERB12S00123456',
        confidence: 0.95,
        confidenceCategory: 'High',
        isSelected: true,
        isVerified: false,
        createdAt: now,
        updatedAt: now,
      );

      expect(model.isRecommended, isTrue);

      final map = model.toMap();
      expect(map['is_selected'], 1);
      expect(map['is_verified'], 0);
      expect(map['document_id'], 'doc_1');

      final deserialized = ExtractedFieldModel.fromMap(
        map,
        'MA3ERB12S00123456',
      );
      expect(deserialized.isSelected, isTrue);
      expect(deserialized.isVerified, isFalse);
      expect(deserialized.plainValue, 'MA3ERB12S00123456');

      final toggled = deserialized.copyWith(isSelected: false);
      expect(toggled.isSelected, isFalse);
    });
  });
}
