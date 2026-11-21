import 'package:intl/intl.dart';

class RawExtractedField {
  final String fieldName;
  final String value;
  final double confidence;
  final String confidenceCategory;
  final int sourcePage;
  final String? sourceSnippet;

  const RawExtractedField({
    required this.fieldName,
    required this.value,
    required this.confidence,
    required this.confidenceCategory,
    this.sourcePage = 1,
    this.sourceSnippet,
  });
}

class DocumentFieldExtractor {
  static List<RawExtractedField> extractFields({
    required String fullText,
    required String documentType,
    int pageCount = 1,
  }) {
    final fields = <RawExtractedField>[];
    final upper = fullText.toUpperCase();
    final lines = fullText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    switch (documentType) {
      case 'PAN Card':
        _extractPanFields(upper, lines, fields);
        break;
      case 'Aadhaar Card':
        _extractAadhaarFields(fullText, upper, lines, fields);
        break;
      case 'Driving Licence':
        _extractDrivingLicenceFields(upper, lines, fields);
        break;
      case 'Vehicle RC Book':
        _extractVehicleRcFields(upper, lines, fields);
        break;
      case 'PUC Certificate':
        _extractPucFields(upper, lines, fields);
        break;
      case 'Vehicle Insurance':
        _extractVehicleInsuranceFields(upper, lines, fields);
        break;
      case 'Passport':
        _extractPassportFields(upper, lines, fields);
        break;
      default:
        _extractGenericFields(upper, lines, fields);
        break;
    }

    return fields;
  }

  // =========================================================================
  // PAN CARD EXTRACTOR
  // =========================================================================
  static void _extractPanFields(String upper, List<String> lines, List<RawExtractedField> fields) {
    // 1. PAN Number
    final panMatch = RegExp(r'\b[A-Z]{5}[0-9]{4}[A-Z]\b').firstMatch(upper);
    if (panMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'PAN Number',
        value: panMatch.group(0)!,
        confidence: 0.98,
        confidenceCategory: 'High',
        sourceSnippet: panMatch.group(0),
      ));
    }

    // 2. Date of Birth
    final dobMatch = RegExp(r'\b(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})\b').firstMatch(upper);
    if (dobMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Date of Birth',
        value: dobMatch.group(1)!,
        confidence: 0.95,
        confidenceCategory: 'High',
        sourceSnippet: dobMatch.group(1),
      ));
    }

    // 3. Name & Father's Name
    // Usually lines after "INCOME TAX DEPARTMENT" or before Father's Name
    String? detectedName;
    String? fatherName;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toUpperCase();
      if (line.contains("FATHER") && i + 1 < lines.length) {
        fatherName = lines[i + 1];
        if (i > 0 && !lines[i - 1].contains("INCOME TAX") && !lines[i - 1].contains("GOVT")) {
          detectedName = lines[i - 1];
        }
      }
    }

    if (detectedName != null && detectedName.length > 2) {
      fields.add(RawExtractedField(
        fieldName: 'Full Name',
        value: detectedName,
        confidence: 0.85,
        confidenceCategory: 'Medium',
      ));
    } else {
      // Find candidate uppercase name line
      for (final line in lines) {
        if (RegExp(r'^[A-Z\s]{4,30}$').hasMatch(line) &&
            !line.contains('INCOME') &&
            !line.contains('TAX') &&
            !line.contains('INDIA') &&
            !line.contains('PERMANENT')) {
          fields.add(RawExtractedField(
            fieldName: 'Full Name',
            value: line,
            confidence: 0.70,
            confidenceCategory: 'Medium',
          ));
          break;
        }
      }
    }

    if (fatherName != null && fatherName.length > 2) {
      fields.add(RawExtractedField(
        fieldName: "Father's Name",
        value: fatherName,
        confidence: 0.82,
        confidenceCategory: 'Medium',
      ));
    }
  }

  // =========================================================================
  // AADHAAR CARD EXTRACTOR
  // =========================================================================
  static void _extractAadhaarFields(String rawText, String upper, List<String> lines, List<RawExtractedField> fields) {
    // 1. Aadhaar Number (Masked preference)
    final aadhaarMatch = RegExp(r'\b(\d{4}\s\d{4}\s\d{4})\b').firstMatch(rawText);
    if (aadhaarMatch != null) {
      final fullNumber = aadhaarMatch.group(1)!;
      final parts = fullNumber.split(' ');
      final masked = 'XXXX XXXX ${parts.last}';
      fields.add(RawExtractedField(
        fieldName: 'Aadhaar Number',
        value: masked,
        confidence: 0.98,
        confidenceCategory: 'High',
        sourceSnippet: fullNumber,
      ));
    }

    // 2. Date of Birth or Year of Birth
    final dobMatch = RegExp(r'(?:DOB|DATE OF BIRTH|BIRTH)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4}|\d{4})').firstMatch(upper);
    if (dobMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Date of Birth',
        value: dobMatch.group(1)!,
        confidence: 0.94,
        confidenceCategory: 'High',
        sourceSnippet: dobMatch.group(0),
      ));
    } else {
      final yobMatch = RegExp(r'(?:YEAR OF BIRTH|YOB)[\s:]*(\d{4})').firstMatch(upper);
      if (yobMatch != null) {
        fields.add(RawExtractedField(
          fieldName: 'Year of Birth',
          value: yobMatch.group(1)!,
          confidence: 0.90,
          confidenceCategory: 'High',
          sourceSnippet: yobMatch.group(0),
        ));
      }
    }

    // 3. Gender
    final genderMatch = RegExp(r'\b(MALE|FEMALE|TRANSGENDER|पुरुष|महिला)\b').firstMatch(upper);
    if (genderMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Gender',
        value: genderMatch.group(1)!,
        confidence: 0.92,
        confidenceCategory: 'High',
        sourceSnippet: genderMatch.group(1),
      ));
    }

    // 4. Address detection
    final addressIndex = lines.indexWhere((l) => l.toUpperCase().contains('ADDRESS') || l.toUpperCase().contains('पता'));
    if (addressIndex != -1 && addressIndex + 1 < lines.length) {
      final addressSnippet = lines.skip(addressIndex).take(3).join(', ');
      fields.add(RawExtractedField(
        fieldName: 'Address',
        value: addressSnippet.replaceFirst(RegExp(r'^(Address|पता)[\s:]*', caseSensitive: false), ''),
        confidence: 0.80,
        confidenceCategory: 'Medium',
      ));
    }
  }

  // =========================================================================
  // DRIVING LICENCE EXTRACTOR
  // =========================================================================
  static void _extractDrivingLicenceFields(String upper, List<String> lines, List<RawExtractedField> fields) {
    // 1. Licence Number
    final dlMatch = RegExp(r'\b([A-Z]{2}[0-9]{2}[\s-]?[0-9]{11})\b').firstMatch(upper);
    if (dlMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Licence Number',
        value: dlMatch.group(1)!,
        confidence: 0.96,
        confidenceCategory: 'High',
        sourceSnippet: dlMatch.group(1),
      ));
    }

    // 2. Dates (DOB, Issue Date, Expiry Date)
    final dateMatches = RegExp(r'\b(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})\b').allMatches(upper).toList();
    if (dateMatches.isNotEmpty) {
      fields.add(RawExtractedField(
        fieldName: 'Date of Birth',
        value: dateMatches[0].group(1)!,
        confidence: 0.85,
        confidenceCategory: 'Medium',
      ));
      if (dateMatches.length >= 2) {
        fields.add(RawExtractedField(
          fieldName: 'Issue Date',
          value: dateMatches[1].group(1)!,
          confidence: 0.80,
          confidenceCategory: 'Medium',
        ));
      }
      if (dateMatches.length >= 3) {
        fields.add(RawExtractedField(
          fieldName: 'Expiry Date',
          value: dateMatches.last.group(1)!,
          confidence: 0.85,
          confidenceCategory: 'High',
        ));
      }
    }

    // 3. Vehicle Classes
    final classes = <String>[];
    if (upper.contains('MCWG') || upper.contains('M/CYL')) classes.add('MCWG (Motorcycle)');
    if (upper.contains('LMV')) classes.add('LMV (Light Motor Vehicle)');
    if (upper.contains('TRANS') || upper.contains('HMV')) classes.add('Transport / Commercial');
    if (classes.isNotEmpty) {
      fields.add(RawExtractedField(
        fieldName: 'Authorised Vehicle Class',
        value: classes.join(', '),
        confidence: 0.90,
        confidenceCategory: 'High',
      ));
    }

    // 4. Issuing Authority
    fields.add(const RawExtractedField(
      fieldName: 'Issuing Authority',
      value: 'Licensing Authority / Transport Department',
      confidence: 0.85,
      confidenceCategory: 'High',
    ));
  }

  // =========================================================================
  // VEHICLE RC BOOK EXTRACTOR
  // =========================================================================
  static void _extractVehicleRcFields(String upper, List<String> lines, List<RawExtractedField> fields) {
    // 1. Registration Number
    final regMatch = RegExp(r'\b([A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{4})\b').firstMatch(upper);
    if (regMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Registration Number',
        value: regMatch.group(1)!,
        confidence: 0.96,
        confidenceCategory: 'High',
        sourceSnippet: regMatch.group(1),
      ));
    }

    // 2. Chassis Number
    final chassisMatch = RegExp(r'(?:CHASSIS|CH\.NO)[\s:]*([A-HJ-NPR-Z0-9]{10,20})').firstMatch(upper);
    if (chassisMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Chassis Number',
        value: chassisMatch.group(1)!,
        confidence: 0.90,
        confidenceCategory: 'High',
      ));
    }

    // 3. Engine Number
    final engineMatch = RegExp(r'(?:ENGINE|ENG\.NO)[\s:]*([A-Z0-9]{6,16})').firstMatch(upper);
    if (engineMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Engine Number',
        value: engineMatch.group(1)!,
        confidence: 0.90,
        confidenceCategory: 'High',
      ));
    }

    // 4. Fuel Type
    final fuelMatch = RegExp(r'\b(PETROL|DIESEL|CNG|ELECTRIC|HYBRID|LPG)\b').firstMatch(upper);
    if (fuelMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Fuel Type',
        value: fuelMatch.group(1)!,
        confidence: 0.92,
        confidenceCategory: 'High',
      ));
    }

    // 5. Registration Date
    final regDateMatch = RegExp(r'(?:REG\.?\s*DATE|DATE OF REG)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})').firstMatch(upper);
    if (regDateMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Registration Date',
        value: regDateMatch.group(1)!,
        confidence: 0.90,
        confidenceCategory: 'High',
      ));
    }
  }

  // =========================================================================
  // PUC CERTIFICATE EXTRACTOR
  // =========================================================================
  static void _extractPucFields(String upper, List<String> lines, List<RawExtractedField> fields) {
    // 1. Vehicle Registration Number
    final regMatch = RegExp(r'\b([A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{4})\b').firstMatch(upper);
    if (regMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Vehicle Registration Number',
        value: regMatch.group(1)!,
        confidence: 0.95,
        confidenceCategory: 'High',
      ));
    }

    // 2. Certificate Number
    final certMatch = RegExp(r'(?:CERTIFICATE NO|PUCC NO)[\s:]*([A-Z0-9]+)').firstMatch(upper);
    if (certMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Certificate Number',
        value: certMatch.group(1)!,
        confidence: 0.90,
        confidenceCategory: 'High',
      ));
    }

    // 3. Validity / Expiry Date
    final valMatch = RegExp(r'(?:VALID UPTO|VALID TILL|EXPIRY DATE)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})').firstMatch(upper);
    if (valMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Validity Date',
        value: valMatch.group(1)!,
        confidence: 0.94,
        confidenceCategory: 'High',
      ));
    }
  }

  // =========================================================================
  // VEHICLE INSURANCE EXTRACTOR
  // =========================================================================
  static void _extractVehicleInsuranceFields(String upper, List<String> lines, List<RawExtractedField> fields) {
    // 1. Policy Number
    final policyMatch = RegExp(r'(?:POLICY NO|POLICY NUMBER)[\s:]*([A-Z0-9\/-]{8,25})').firstMatch(upper);
    if (policyMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Policy Number',
        value: policyMatch.group(1)!,
        confidence: 0.92,
        confidenceCategory: 'High',
      ));
    }

    // 2. Vehicle Registration Number
    final regMatch = RegExp(r'\b([A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{4})\b').firstMatch(upper);
    if (regMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Vehicle Registration Number',
        value: regMatch.group(1)!,
        confidence: 0.94,
        confidenceCategory: 'High',
      ));
    }

    // 3. Expiry Date
    final expiryMatch = RegExp(r'(?:EXPIRY DATE|TO MIDNIGHT OF)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})').firstMatch(upper);
    if (expiryMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Policy Expiry Date',
        value: expiryMatch.group(1)!,
        confidence: 0.92,
        confidenceCategory: 'High',
      ));
    }
  }

  // =========================================================================
  // PASSPORT EXTRACTOR
  // =========================================================================
  static void _extractPassportFields(String upper, List<String> lines, List<RawExtractedField> fields) {
    // 1. Passport Number
    final passMatch = RegExp(r'\b([A-Z][0-9]{7,8})\b').firstMatch(upper);
    if (passMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Passport Number',
        value: passMatch.group(1)!,
        confidence: 0.98,
        confidenceCategory: 'High',
        sourceSnippet: passMatch.group(1),
      ));
    }

    // 2. Nationality
    if (upper.contains('INDIAN') || upper.contains('REPUBLIC OF INDIA')) {
      fields.add(const RawExtractedField(
        fieldName: 'Nationality',
        value: 'INDIAN',
        confidence: 0.95,
        confidenceCategory: 'High',
      ));
    }

    // 3. Dates
    final dates = RegExp(r'\b(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})\b').allMatches(upper).toList();
    if (dates.isNotEmpty) {
      fields.add(RawExtractedField(
        fieldName: 'Date of Birth',
        value: dates[0].group(1)!,
        confidence: 0.85,
        confidenceCategory: 'Medium',
      ));
      if (dates.length >= 2) {
        fields.add(RawExtractedField(
          fieldName: 'Issue Date',
          value: dates[1].group(1)!,
          confidence: 0.85,
          confidenceCategory: 'Medium',
        ));
      }
      if (dates.length >= 3) {
        fields.add(RawExtractedField(
          fieldName: 'Expiry Date',
          value: dates.last.group(1)!,
          confidence: 0.90,
          confidenceCategory: 'High',
        ));
      }
    }
  }

  // =========================================================================
  // GENERIC EXTRACTOR
  // =========================================================================
  static void _extractGenericFields(String upper, List<String> lines, List<RawExtractedField> fields) {
    final dates = RegExp(r'\b(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})\b').allMatches(upper).toList();
    for (int i = 0; i < dates.length && i < 3; i++) {
      fields.add(RawExtractedField(
        fieldName: i == 0 ? 'Document Date' : 'Reference Date $i',
        value: dates[i].group(1)!,
        confidence: 0.70,
        confidenceCategory: 'Medium',
      ));
    }

    // Check for alphanumeric reference numbers
    final refMatch = RegExp(r'(?:NO|NUMBER|REF|ID)[\s.:#]*([A-Z0-9-]{6,20})').firstMatch(upper);
    if (refMatch != null) {
      fields.add(RawExtractedField(
        fieldName: 'Reference Number',
        value: refMatch.group(1)!,
        confidence: 0.75,
        confidenceCategory: 'Medium',
      ));
    }
  }
}

