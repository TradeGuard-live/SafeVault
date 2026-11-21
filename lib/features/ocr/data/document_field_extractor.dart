import 'package:intl/intl.dart';

class RawExtractedField {
  final String fieldName;
  final String value;
  final double confidence;
  final String confidenceCategory;
  final int sourcePage;
  final String? sourceSnippet;
  final bool isSelected;
  final bool isRecommended;

  const RawExtractedField({
    required this.fieldName,
    required this.value,
    required this.confidence,
    required this.confidenceCategory,
    this.sourcePage = 1,
    this.sourceSnippet,
    this.isSelected = true,
    bool? isRecommended,
  }) : isRecommended = isRecommended ?? (confidence >= 0.8);

  RawExtractedField copyWith({
    String? fieldName,
    String? value,
    double? confidence,
    String? confidenceCategory,
    int? sourcePage,
    String? sourceSnippet,
    bool? isSelected,
    bool? isRecommended,
  }) {
    return RawExtractedField(
      fieldName: fieldName ?? this.fieldName,
      value: value ?? this.value,
      confidence: confidence ?? this.confidence,
      confidenceCategory: confidenceCategory ?? this.confidenceCategory,
      sourcePage: sourcePage ?? this.sourcePage,
      sourceSnippet: sourceSnippet ?? this.sourceSnippet,
      isSelected: isSelected ?? this.isSelected,
      isRecommended: isRecommended ?? this.isRecommended,
    );
  }
}

class DocumentFieldExtractor {
  static List<RawExtractedField> extractFields({
    required String fullText,
    required String documentType,
    int pageCount = 1,
  }) {
    final fields = <RawExtractedField>[];
    // OCR commonly inserts non-breaking spaces, typographic dashes and uneven
    // whitespace. Normalising those layout artefacts lets the extractors be
    // tolerant without changing the actual document values.
    final normalizedText = _normalizeOcrText(fullText);
    final upper = normalizedText.toUpperCase();
    final lines = normalizedText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    switch (documentType) {
      case 'Vehicle RC Book':
        _extractVehicleRcFields(normalizedText, upper, lines, fields);
        break;
      case 'Driving Licence':
        _extractDrivingLicenceFields(normalizedText, upper, lines, fields);
        break;
      case 'Aadhaar Card':
        _extractAadhaarFields(normalizedText, upper, lines, fields);
        break;
      case 'PAN Card':
        _extractPanFields(normalizedText, upper, lines, fields);
        break;
      case 'PUC Certificate':
        _extractPucFields(normalizedText, upper, lines, fields);
        break;
      case 'Vehicle Insurance':
      case 'Vehicle Insurance Policy':
        _extractVehicleInsuranceFields(normalizedText, upper, lines, fields);
        break;
      case 'Passport':
        _extractPassportFields(normalizedText, upper, lines, fields);
        break;
      case 'Bank Document':
      case 'Bank Statement':
      case 'Bank Passbook':
      case 'Cheque':
        _extractBankDocumentFields(normalizedText, upper, lines, fields);
        break;
      case 'Academic Certificate':
      case 'Degree Certificate':
      case 'Mark Sheet':
      case 'Education Certificate':
      case 'School Certificates':
      case 'College Certificates':
      case 'Degree Certificates':
      case 'Mark Sheets':
        _extractEducationCertificateFields(
          normalizedText,
          upper,
          lines,
          fields,
        );
        break;
      case 'Property Documents':
      case 'Property Document':
      case 'Rent Agreements':
      case 'Rent Agreement':
      case 'Ownership Documents':
      case 'Ownership Document':
        _extractPropertyFields(normalizedText, upper, lines, fields);
        break;
      case 'Medical Reports':
      case 'Medical Report':
      case 'Medical Document':
      case 'Health Insurance':
      case 'Vaccination Certificates':
        _extractMedicalFields(normalizedText, upper, lines, fields);
        break;
      default:
        _extractGenericFields(normalizedText, upper, lines, fields);
        break;
    }

    return _deduplicateFields(fields);
  }

  // =========================================================================
  // 1. VEHICLE RC BOOK (25+ FIELDS)
  // =========================================================================
  static void _extractVehicleRcFields(
    String fullText,
    String upper,
    List<String> lines,
    List<RawExtractedField> fields,
  ) {
    // 1. Registration Number
    final registrationNumber = _findVehicleRegistration(upper);
    if (registrationNumber != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Registration Number',
          value: registrationNumber,
          confidence: 0.98,
          confidenceCategory: 'High',
          sourceSnippet: registrationNumber,
        ),
      );
    }

    // 2. Registration Date
    final regDateMatch = RegExp(
      r'(?:REGISTRATION\s*DATE|REG\.?\s*DATE|DATE OF REG|DT OF REG)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})',
    ).firstMatch(upper);
    if (regDateMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Registration Date',
          value: regDateMatch.group(1)!,
          confidence: 0.95,
          confidenceCategory: 'High',
          sourceSnippet: regDateMatch.group(0),
        ),
      );
    }

    // 3. Chassis Number
    final chassisMatch = RegExp(
      r'(?:CHASSIS\s*NUMBER|CHASSIS(?:\s*NO)?|CH\.NO|VIN)[\s:]*([A-HJ-NPR-Z0-9]{10,21})',
    ).firstMatch(upper);
    if (chassisMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Chassis Number',
          value: chassisMatch.group(1)!,
          confidence: 0.96,
          confidenceCategory: 'High',
          sourceSnippet: chassisMatch.group(0),
        ),
      );
    }

    // 4. Engine Number
    final engineMatch = RegExp(
      r'(?:ENGINE\s*NUMBER|ENGINE(?:\s*NO)?|ENG\.NO|MOTOR NO)[\s:]*([A-Z0-9]{6,18})',
    ).firstMatch(upper);
    if (engineMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Engine Number',
          value: engineMatch.group(1)!,
          confidence: 0.95,
          confidenceCategory: 'High',
          sourceSnippet: engineMatch.group(0),
        ),
      );
    }

    // 5. Owner Name
    String? ownerName;
    final ownerSameLine = RegExp(
      r'(?:REGISTERED OWNER|OWNER NAME|NAME OF OWNER)[\s:]*([A-Za-z ]{3,35})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (ownerSameLine != null && _isValidName(ownerSameLine.group(1)!)) {
      ownerName = _cleanName(ownerSameLine.group(1)!);
    } else {
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].toUpperCase();
        if ((line.contains('OWNER NAME') ||
                line.contains('NAME OF OWNER') ||
                line.contains('REG OWNER') ||
                line.contains('REGISTERED OWNER')) &&
            i + 1 < lines.length) {
          final candidate = _cleanName(lines[i + 1]);
          if (_isValidName(candidate)) {
            ownerName = candidate;
            break;
          }
        }
      }
    }
    if (ownerName != null && ownerName.isNotEmpty) {
      fields.add(
        RawExtractedField(
          fieldName: 'Owner Name',
          value: ownerName,
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 6. Father / Husband Name
    final relationMatch = RegExp(
      r'(?:S/O|D/O|W/O|FATHER(?:\x27S)?\s*NAME)[\s:]*([A-Za-z ]{3,35})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (relationMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: "Father's / Husband's Name",
          value: _cleanName(relationMatch.group(1)!),
          confidence: 0.85,
          confidenceCategory: 'High',
        ),
      );
    }

    // 7. Present / Permanent Address
    final addrIdx = lines.indexWhere(
      (l) =>
          l.toUpperCase().contains('ADDRESS') ||
          l.toUpperCase().contains('RESIDENCE'),
    );
    if (addrIdx != -1 && addrIdx + 1 < lines.length) {
      final addr = lines.skip(addrIdx + 1).take(2).join(', ');
      fields.add(
        RawExtractedField(
          fieldName: 'Address',
          value: addr,
          confidence: 0.78,
          confidenceCategory: 'Medium',
        ),
      );
    }

    // 8. Vehicle Class
    final classMatch = RegExp(
      r'(?:VEHICLE CLASS|CLASS OF VEHICLE|VCH CLASS)[\s:]*([A-Z0-9 \(\)\/-]{3,25})',
    ).firstMatch(upper);
    if (classMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Vehicle Class',
          value: classMatch.group(1)!.trim(),
          confidence: 0.92,
          confidenceCategory: 'High',
        ),
      );
    } else {
      if (upper.contains('MOTOR CAR') || upper.contains('LMV')) {
        fields.add(
          const RawExtractedField(
            fieldName: 'Vehicle Class',
            value: 'LMV (Light Motor Vehicle / Motor Car)',
            confidence: 0.85,
            confidenceCategory: 'High',
          ),
        );
      } else if (upper.contains('MOTOR CYCLE') || upper.contains('MCWG')) {
        fields.add(
          const RawExtractedField(
            fieldName: 'Vehicle Class',
            value: 'MCWG (Motor Cycle with Gear)',
            confidence: 0.85,
            confidenceCategory: 'High',
          ),
        );
      }
    }

    // 9. Maker / Manufacturer
    final makerMatch = RegExp(
      r'(?:MAKER|MANUFACTURER|MFG|VEHICLE MANUFACTURER)[\s:]*([A-Za-z0-9 \.\-]{3,30})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (makerMatch != null) {
      final makerVal = makerMatch.group(1)!.trim();
      fields.add(
        RawExtractedField(
          fieldName: 'Maker / Manufacturer',
          value: makerVal,
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
      fields.add(
        RawExtractedField(
          fieldName: 'Vehicle Manufacturer',
          value: makerVal,
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 10. Model Name
    final modelMatch = RegExp(
      r'(?:MODEL\s*NAME|MODEL|COMMERCIAL NAME|VEHICLE MODEL)[\s:]*([A-Za-z0-9 \.\-\+]{2,30})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (modelMatch != null) {
      final modelVal = modelMatch.group(1)!.trim();
      fields.add(
        RawExtractedField(
          fieldName: 'Model Name',
          value: modelVal,
          confidence: 0.86,
          confidenceCategory: 'High',
        ),
      );
      fields.add(
        RawExtractedField(
          fieldName: 'Vehicle Model',
          value: modelVal,
          confidence: 0.86,
          confidenceCategory: 'High',
        ),
      );
    }

    // 11. Vehicle Category / Type
    final catMatch = RegExp(
      r'(?:VEHICLE CATEGORY|TYPE OF VEHICLE)[\s:]*([A-Z0-9\-]+)',
    ).firstMatch(upper);
    if (catMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Vehicle Category',
          value: catMatch.group(1)!,
          confidence: 0.85,
          confidenceCategory: 'High',
        ),
      );
    }

    // 12. Body Type
    final bodyMatch = RegExp(r'(?:BODY TYPE|TYPE OF BODY)[\s:]*([A-Z ]{3,20})')
        .firstMatch(upper);
    if (bodyMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Body Type',
          value: bodyMatch.group(1)!.trim(),
          confidence: 0.84,
          confidenceCategory: 'High',
        ),
      );
    }

    // 13. Fuel Type
    final fuelMatch = RegExp(
      r'\b(PETROL|DIESEL|CNG|ELECTRIC|HYBRID|LPG|BATTERY)\b',
    ).firstMatch(upper);
    if (fuelMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Fuel Type',
          value: fuelMatch.group(1)!,
          confidence: 0.95,
          confidenceCategory: 'High',
        ),
      );
    }

    // 14. Color
    final colorMatch = RegExp(
      r'(?:COLOUR|COLOR)[\s:]*([A-Za-z ]{3,20})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (colorMatch != null) {
      final colorVal = colorMatch.group(1)!.trim();
      fields.add(
        RawExtractedField(
          fieldName: 'Color',
          value: colorVal,
          confidence: 0.85,
          confidenceCategory: 'High',
        ),
      );
      fields.add(
        RawExtractedField(
          fieldName: 'Colour',
          value: colorVal,
          confidence: 0.85,
          confidenceCategory: 'High',
        ),
      );
    }

    // 15. Seating Capacity
    final seatMatch = RegExp(r'(?:SEATING CAPACITY|SEAT CAP)[\s:]*([0-9]{1,3})')
        .firstMatch(upper);
    if (seatMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Seating Capacity',
          value: seatMatch.group(1)!,
          confidence: 0.90,
          confidenceCategory: 'High',
        ),
      );
    }

    // 16. Standing Capacity
    final standMatch = RegExp(
      r'(?:STANDING CAPACITY|STAND CAP)[\s:]*([0-9]{1,3})',
    ).firstMatch(upper);
    if (standMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Standing Capacity',
          value: standMatch.group(1)!,
          confidence: 0.85,
          confidenceCategory: 'High',
        ),
      );
    }

    // 17. Manufactured Date / Month-Year
    final mfgMatch = RegExp(
      r'(?:MFG(?:\.|\s*DATE|\.\s*DATE)?|YEAR OF MFG|MANUFACTURED)[\s:]*([0-9]{2}[\/\.-][0-9]{4}|[0-9]{4})',
    ).firstMatch(upper);
    if (mfgMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Manufactured Date',
          value: mfgMatch.group(1)!,
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 18. Gross Vehicle Weight (GVW)
    final gvwMatch = RegExp(
      r'(?:GROSS VEHICLE WT|GVW|G\.V\.W)[\s:]*([0-9]{3,6}(?:\s*KG)?)',
    ).firstMatch(upper);
    if (gvwMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Gross Vehicle Weight (GVW)',
          value: gvwMatch.group(1)!,
          confidence: 0.89,
          confidenceCategory: 'High',
        ),
      );
    }

    // 19. Unladen Weight
    final unladenMatch = RegExp(
      r'(?:UNLADEN WT|ULW|U\.L\.W)[\s:]*([0-9]{3,6}(?:\s*KG)?)',
    ).firstMatch(upper);
    if (unladenMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Unladen Weight',
          value: unladenMatch.group(1)!,
          confidence: 0.89,
          confidenceCategory: 'High',
        ),
      );
    }

    // 20. Cubic Capacity (CC) / Engine Capacity
    final ccMatch = RegExp(
      r'(?:CUBIC CAPACITY|C\.C|CC|DISPLACEMENT)[\s:]*([0-9]{3,5}(?:\s*CC)?)',
    ).firstMatch(upper);
    if (ccMatch != null) {
      final ccVal = ccMatch.group(1)!;
      fields.add(
        RawExtractedField(
          fieldName: 'Cubic Capacity (CC)',
          value: ccVal,
          confidence: 0.90,
          confidenceCategory: 'High',
        ),
      );
      fields.add(
        RawExtractedField(
          fieldName: 'Cubic Capacity',
          value: ccVal,
          confidence: 0.90,
          confidenceCategory: 'High',
        ),
      );
    }

    // 21. Wheelbase
    final wbMatch = RegExp(
      r'(?:WHEEL\s*BASE|WHEELBASE)[\s:]*([0-9]{3,5}(?:\s*MM)?)',
    ).firstMatch(upper);
    if (wbMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Wheelbase',
          value: wbMatch.group(1)!,
          confidence: 0.85,
          confidenceCategory: 'High',
        ),
      );
    }

    // 22. Number of Cylinders
    final cylMatch = RegExp(r'(?:CYLINDERS?|NO OF CYL)[\s:]*([0-9]{1,2})')
        .firstMatch(upper);
    if (cylMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Number of Cylinders',
          value: cylMatch.group(1)!,
          confidence: 0.85,
          confidenceCategory: 'High',
        ),
      );
    }

    // 23. Fitness Upto / Validity Date
    final fitMatch = RegExp(
      r'(?:FITNESS UPTO|FITNESS VALID|REG\.?\s*UPTO)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})',
    ).firstMatch(upper);
    if (fitMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Fitness Upto',
          value: fitMatch.group(1)!,
          confidence: 0.94,
          confidenceCategory: 'High',
          sourceSnippet: fitMatch.group(0),
        ),
      );
    }

    // 24. Insurance Details
    final insMatch = RegExp(
      r'(?:INSURANCE|POLICY)[\s:]*([A-Za-z0-9 \/\-]{4,35})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (insMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Insurance Details',
          value: insMatch.group(1)!.trim(),
          confidence: 0.82,
          confidenceCategory: 'Medium',
        ),
      );
    }

    // 25. Tax Upto
    final taxMatch = RegExp(
      r'(?:TAX UPTO|TAX VALID|ROAD TAX)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4}|LIFE\s*TIME|L\.T\.T\.)',
    ).firstMatch(upper);
    if (taxMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Tax Status / Upto',
          value: taxMatch.group(1)!,
          confidence: 0.90,
          confidenceCategory: 'High',
        ),
      );
    }

    // 26. Issuing Authority / RTO
    final rtoMatch = RegExp(
      r'(?:REGISTERING AUTHORITY|ISSUING AUTHORITY|RTO)[\s:]*([A-Za-z0-9 \(\)\.\-]{3,35})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (rtoMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Issuing Authority / RTO',
          value: rtoMatch.group(1)!.trim(),
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 27. Hypothecation / Financier
    final hypoMatch = RegExp(
      r'(?:HYPOTHECATED TO|FINANCIER|HPA)[\s:]*([A-Za-z0-9 \.\-]{3,40})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (hypoMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Financier / Hypothecation',
          value: hypoMatch.group(1)!.trim(),
          confidence: 0.85,
          confidenceCategory: 'High',
        ),
      );
    }

    // 28. PUC Upto / Validity
    final pucMatch = RegExp(
      r'(?:PUC UPTO|PUC VALID|PUCC UPTO|POLLUTION UPTO)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})',
    ).firstMatch(upper);
    if (pucMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'PUC Validity',
          value: pucMatch.group(1)!,
          confidence: 0.91,
          confidenceCategory: 'High',
          sourceSnippet: pucMatch.group(0),
        ),
      );
    }
  }

  // =========================================================================
  // 2. DRIVING LICENCE
  // =========================================================================
  static void _extractDrivingLicenceFields(
    String fullText,
    String upper,
    List<String> lines,
    List<RawExtractedField> fields,
  ) {
    // 1. Licence Number
    final dlMatch = RegExp(r'\b([A-Z]{2}[0-9]{2}[\s-]?[0-9]{11})\b')
        .firstMatch(upper);
    if (dlMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Licence Number',
          value: dlMatch.group(1)!,
          confidence: 0.98,
          confidenceCategory: 'High',
          sourceSnippet: dlMatch.group(1),
        ),
      );
    }

    // 2. Full Name
    String? dlName;
    for (int i = 0; i < lines.length; i++) {
      if (RegExp(
            r'^\s*(?:FULL\s+)?NAME\s*[-:]?\s*$',
            caseSensitive: false,
          ).hasMatch(lines[i]) &&
          i + 1 < lines.length) {
        final candidate = _cleanName(lines[i + 1]);
        if (_isLikelyPersonName(candidate)) {
          dlName = candidate;
          break;
        }
      }
    }
    final dlSameLine = RegExp(
      r'^\s*(?:FULL\s+)?NAME\s*[-:]\s*([A-Za-z .]{3,35})\s*$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(fullText);
    if (dlSameLine != null && (dlName == null || dlName.isEmpty)) {
      final candidate = _cleanName(dlSameLine.group(1)!);
      if (_isLikelyPersonName(candidate)) {
        dlName = candidate;
      }
    }
    if (dlName != null && dlName.isNotEmpty) {
      fields.add(
        RawExtractedField(
          fieldName: 'Full Name',
          value: dlName,
          confidence: 0.86,
          confidenceCategory: 'High',
        ),
      );
    }

    // 3. Father's / Husband's Name
    final relMatch = RegExp(
      r'^\s*(?:S/O|D/O|W/O|FATHER(?:\x27S)?\s*NAME)\s*[-:]\s*([A-Za-z .]{3,35})\s*$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(fullText);
    final relativeName = relMatch == null
        ? null
        : _cleanName(relMatch.group(1)!);
    if (relativeName != null && _isLikelyPersonName(relativeName)) {
      fields.add(
        RawExtractedField(
          fieldName: "Father's / Husband's Name",
          value: relativeName,
          confidence: 0.86,
          confidenceCategory: 'High',
        ),
      );
    }

    // 4. Date of Birth
    final dobMatch = RegExp(
      r'(?:DOB|DATE OF BIRTH)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})',
    ).firstMatch(upper);
    if (dobMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Date of Birth',
          value: dobMatch.group(1)!,
          confidence: 0.95,
          confidenceCategory: 'High',
        ),
      );
    }

    // 5. Blood Group
    final bgMatch = RegExp(r'(?:BLOOD GROUP|BG)[\s:]*([ABO\+\-]{2,4})')
        .firstMatch(upper);
    if (bgMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Blood Group',
          value: bgMatch.group(1)!,
          confidence: 0.90,
          confidenceCategory: 'High',
        ),
      );
    }

    // 6. Address
    final addrIdx = lines.indexWhere(
      (l) =>
          l.toUpperCase().contains('ADDRESS') ||
          l.toUpperCase().contains('RESIDENCE'),
    );
    if (addrIdx != -1 && addrIdx + 1 < lines.length) {
      fields.add(
        RawExtractedField(
          fieldName: 'Address',
          value: lines.skip(addrIdx + 1).take(2).join(', '),
          confidence: 0.80,
          confidenceCategory: 'Medium',
        ),
      );
    }

    // 7. Date of Issue
    final issueMatch = RegExp(
      r'(?:ISSUE DATE|DATE OF ISSUE|DOI)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})',
    ).firstMatch(upper);
    if (issueMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Issue Date',
          value: issueMatch.group(1)!,
          confidence: 0.92,
          confidenceCategory: 'High',
        ),
      );
    }

    // 8. Validity (Non-Transport)
    final valNtMatch = RegExp(
      r'(?:NON-TRANSPORT|NT|VALIDITY NT)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})',
    ).firstMatch(upper);
    if (valNtMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Validity (Non-Transport)',
          value: valNtMatch.group(1)!,
          confidence: 0.92,
          confidenceCategory: 'High',
        ),
      );
    }

    // 9. Validity (Transport)
    final valTrMatch = RegExp(
      r'(?:TRANSPORT|TR|VALIDITY TR)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})',
    ).firstMatch(upper);
    if (valTrMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Validity (Transport)',
          value: valTrMatch.group(1)!,
          confidence: 0.90,
          confidenceCategory: 'High',
        ),
      );
    }

    // 10. Authorised Vehicle Class
    final hasVehicleClassEvidence =
        dlMatch != null ||
        RegExp(
          r'(?:AUTHORI[ZS]ED\s+(?:TO\s+DRIVE\s+)?VEHICLE|VEHICLE\s+CLASS|CLASS\s+OF\s+VEHICLE|DL\s+CLASS)',
        ).hasMatch(upper);
    final classes = <String>[];
    if (hasVehicleClassEvidence) {
      if (upper.contains('MCWG') || upper.contains('M/CYL')) {
        classes.add('MCWG (Motorcycle with Gear)');
      }
      if (upper.contains('LMV')) {
        classes.add('LMV (Light Motor Vehicle)');
      }
      if (upper.contains('TRANS') || upper.contains('HMV')) {
        classes.add('Transport (Commercial)');
      }
    }
    if (classes.isNotEmpty) {
      fields.add(
        RawExtractedField(
          fieldName: 'Authorised Vehicle Class',
          value: classes.join(', '),
          confidence: 0.94,
          confidenceCategory: 'High',
        ),
      );
    }

    // 11. Issuing Authority
    final rtoMatch = RegExp(
      r'(?:LICENSING AUTHORITY|ISSUING AUTHORITY|RTO)[\s:]*([A-Za-z0-9 \(\)\.\-]{3,35})',
      caseSensitive: false,
    ).firstMatch(fullText);
    final authority = rtoMatch?.group(1)?.trim();
    if (authority != null && _isLikelyAuthority(authority)) {
      fields.add(
        RawExtractedField(
          fieldName: 'Issuing Authority',
          value: authority,
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }
  }

  // =========================================================================
  // 3. AADHAAR CARD
  // =========================================================================
  static void _extractAadhaarFields(
    String fullText,
    String upper,
    List<String> lines,
    List<RawExtractedField> fields,
  ) {
    // 1. Aadhaar Number (Masked preference)
    final aadhaarNumber = _findAadhaarNumber(fullText);
    if (aadhaarNumber != null) {
      final masked = 'XXXX XXXX ${aadhaarNumber.substring(8)}';
      fields.add(
        RawExtractedField(
          fieldName: 'Aadhaar Number',
          value: masked,
          confidence: 0.99,
          confidenceCategory: 'High',
          sourceSnippet: aadhaarNumber,
        ),
      );
    }

    // 2. Full Name
    String? detectedName;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('GOVERNMENT OF INDIA') ||
          line.contains('UIDAI') ||
          line.contains('भारत सरकार')) {
        if (i + 1 < lines.length && _isValidName(lines[i + 1])) {
          detectedName = lines[i + 1];
          break;
        }
      }
    }
    if (detectedName != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Full Name',
          value: detectedName,
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 3. Date of Birth or Year of Birth
    final dobMatch = RegExp(
      r'(?:DOB|DATE OF BIRTH|BIRTH)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})',
    ).firstMatch(upper);
    if (dobMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Date of Birth',
          value: dobMatch.group(1)!,
          confidence: 0.96,
          confidenceCategory: 'High',
        ),
      );
    } else {
      final yobMatch = RegExp(r'(?:YEAR OF BIRTH|YOB)[\s:]*(\d{4})')
          .firstMatch(upper);
      if (yobMatch != null) {
        fields.add(
          RawExtractedField(
            fieldName: 'Year of Birth',
            value: yobMatch.group(1)!,
            confidence: 0.92,
            confidenceCategory: 'High',
          ),
        );
      }
    }

    // 4. Gender
    final genderMatch = RegExp(r'\b(MALE|FEMALE|TRANSGENDER|पुरुष|महिला)\b')
        .firstMatch(upper);
    if (genderMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Gender',
          value: genderMatch.group(1)!,
          confidence: 0.95,
          confidenceCategory: 'High',
        ),
      );
    }

    // 5. Father's / Husband's Name (C/O, S/O, W/O, D/O)
    final coMatch = RegExp(
      r'(?:C/O|S/O|W/O|D/O)[\s:]*([A-Za-z ]{3,35})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (coMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: "Father's / Husband's Name (C/O)",
          value: _cleanName(coMatch.group(1)!),
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 6. Address
    final addrIdx = lines.indexWhere(
      (l) =>
          l.toUpperCase().contains('ADDRESS') ||
          l.toUpperCase().contains('पता'),
    );
    if (addrIdx != -1 && addrIdx + 1 < lines.length) {
      final addrText = lines
          .skip(addrIdx)
          .take(3)
          .join(', ')
          .replaceFirst(
            RegExp(r'^(Address|पता)[\s:]*', caseSensitive: false),
            '',
          );
      fields.add(
        RawExtractedField(
          fieldName: 'Address',
          value: addrText,
          confidence: 0.84,
          confidenceCategory: 'High',
        ),
      );
    }

    // 7. PIN Code
    final pinMatch = RegExp(r'\b([1-9][0-9]{5})\b').firstMatch(fullText);
    if (pinMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'PIN Code',
          value: pinMatch.group(1)!,
          confidence: 0.92,
          confidenceCategory: 'High',
        ),
      );
    }
  }

  // =========================================================================
  // 4. PAN CARD
  // =========================================================================
  static void _extractPanFields(
    String fullText,
    String upper,
    List<String> lines,
    List<RawExtractedField> fields,
  ) {
    // 1. PAN Number
    final panMatch = RegExp(r'\b([A-Z]{5}[0-9]{4}[A-Z])\b').firstMatch(upper);
    if (panMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'PAN Number',
          value: panMatch.group(1)!,
          confidence: 0.99,
          confidenceCategory: 'High',
          sourceSnippet: panMatch.group(1),
        ),
      );
    }

    // 2. Date of Birth
    final dobMatch = RegExp(r'\b(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})\b')
        .firstMatch(upper);
    if (dobMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Date of Birth',
          value: dobMatch.group(1)!,
          confidence: 0.95,
          confidenceCategory: 'High',
        ),
      );
    }

    // 3. Name & Father's Name
    String? detectedName;
    String? fatherName;

    // Check same-line FATHER NAME: ...
    final fnMatch = RegExp(
      r'(?:FATHER(?:\x27S)?\s*NAME)[\s:]*([A-Za-z ]{3,35})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (fnMatch != null) {
      fatherName = _cleanName(fnMatch.group(1)!);
    } else {
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].toUpperCase();
        if (line.contains("FATHER") && i + 1 < lines.length) {
          fatherName = _cleanName(lines[i + 1]);
          if (i > 0 &&
              !lines[i - 1].contains("INCOME TAX") &&
              !lines[i - 1].contains("GOVT")) {
            detectedName = _cleanName(lines[i - 1]);
          }
          break;
        }
      }
    }

    if (detectedName == null || detectedName.isEmpty) {
      // Find candidate name from uppercase lines
      for (final line in lines) {
        if (RegExp(r'^[A-Za-z ]{4,30}$').hasMatch(line) &&
            !line.toUpperCase().contains('INCOME') &&
            !line.toUpperCase().contains('TAX') &&
            !line.toUpperCase().contains('INDIA') &&
            !line.toUpperCase().contains('FATHER') &&
            !line.toUpperCase().contains('PERMANENT')) {
          detectedName = _cleanName(line);
          break;
        }
      }
    }

    if (detectedName != null && detectedName.length > 2) {
      fields.add(
        RawExtractedField(
          fieldName: 'Full Name',
          value: detectedName,
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    if (fatherName != null && fatherName.length > 2) {
      fields.add(
        RawExtractedField(
          fieldName: "Father's Name",
          value: fatherName,
          confidence: 0.86,
          confidenceCategory: 'High',
        ),
      );
    }
  }

  // =========================================================================
  // 5. PUC CERTIFICATE
  // =========================================================================
  static void _extractPucFields(
    String fullText,
    String upper,
    List<String> lines,
    List<RawExtractedField> fields,
  ) {
    // 1. Certificate Number
    final certMatch = RegExp(
      r'(?:CERTIFICATE NO|PUCC NO|PUC NO)[\s:]*([A-Z0-9\/-]+)',
    ).firstMatch(upper);
    if (certMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Certificate Number',
          value: certMatch.group(1)!,
          confidence: 0.95,
          confidenceCategory: 'High',
        ),
      );
    }

    // 2. Vehicle Registration Number
    final registrationNumber = _findVehicleRegistration(upper);
    if (registrationNumber != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Vehicle Registration Number',
          value: registrationNumber,
          confidence: 0.98,
          confidenceCategory: 'High',
        ),
      );
    }

    // 3. Date of Issue
    final dateMatch = RegExp(
      r'(?:DATE OF ISSUE|DOI|ISSUED ON)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})',
    ).firstMatch(upper);
    if (dateMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Date of Issue',
          value: dateMatch.group(1)!,
          confidence: 0.92,
          confidenceCategory: 'High',
        ),
      );
    }

    // 4. Validity / Expiry Date
    final valMatch = RegExp(
      r'(?:VALID UPTO|VALID TILL|EXPIRY DATE)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})',
    ).firstMatch(upper);
    if (valMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Expiry Date',
          value: valMatch.group(1)!,
          confidence: 0.96,
          confidenceCategory: 'High',
        ),
      );
    }

    // 5. Emission Values (CO, HC)
    final coMatch = RegExp(
      r'(?:CO\s*\(?%?\)?|CARBON MONOXIDE(?:\s*\(CO\))?)[\s:]*([0-9]+\.[0-9]+)',
    ).firstMatch(upper);
    if (coMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'CO Emission Value (%)',
          value: coMatch.group(1)!,
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    final hcMatch = RegExp(
      r'(?:HYDROCARBONS(?:\s*\(HC\))?|HC\s*\(?PPM\)?)[\s:]*([0-9]+)',
    ).firstMatch(upper);
    if (hcMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'HC Emission Value (PPM)',
          value: hcMatch.group(1)!,
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 6. Compliance Status
    if (upper.contains('PASS') ||
        upper.contains('COMPLIANT') ||
        upper.contains('WITHIN LIMITS')) {
      fields.add(
        const RawExtractedField(
          fieldName: 'Compliance Status',
          value: 'Pass / Compliant',
          confidence: 0.94,
          confidenceCategory: 'High',
        ),
      );
    }
  }

  // =========================================================================
  // 6. VEHICLE INSURANCE
  // =========================================================================
  static void _extractVehicleInsuranceFields(
    String fullText,
    String upper,
    List<String> lines,
    List<RawExtractedField> fields,
  ) {
    // 1. Policy Number
    final policyMatch = RegExp(
      r'(?:POLICY\s*(?:NO\.?|NUMBER))[\s:#.]*([A-Z0-9\/-]{8,30})',
    ).firstMatch(upper);
    if (policyMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Policy Number',
          value: policyMatch.group(1)!,
          confidence: 0.96,
          confidenceCategory: 'High',
        ),
      );
    }

    // 2. Insurer Name
    final insurerMatch = RegExp(
      r'(?:ICICI LOMBARD|HDFC ERGO|BAJAJ ALLIANZ|NEW INDIA ASSURANCE|TATA AIG|GO DIGIT|IFFCO TOKIO|UNITED INDIA|NATIONAL INSURANCE|ORIENTAL INSURANCE|STAR HEALTH|SBI GENERAL)',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (insurerMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Insurance Company',
          value: insurerMatch.group(0)!,
          confidence: 0.95,
          confidenceCategory: 'High',
        ),
      );
    }

    // 3. Insured Name
    final nameMatch = RegExp(
      r'(?:INSURED NAME|NAME OF INSURED|POLICYHOLDER)[\s:]*([A-Za-z ]{3,35})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (nameMatch != null) {
      final insuredName = _cleanName(nameMatch.group(1)!);
      if (_isLikelyPersonName(insuredName)) {
        fields.add(
          RawExtractedField(
            fieldName: 'Insured Name',
            value: insuredName,
            confidence: 0.88,
            confidenceCategory: 'High',
          ),
        );
      }
    }

    // 4. Vehicle Registration Number
    final registrationNumber = _findVehicleRegistration(upper);
    if (registrationNumber != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Vehicle Registration Number',
          value: registrationNumber,
          confidence: 0.96,
          confidenceCategory: 'High',
        ),
      );
    }

    // 5. Policy Start Date
    final startMatch = RegExp(
      r'(?:FROM|POLICY START|COMMENCEMENT DATE)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})',
    ).firstMatch(upper);
    if (startMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Policy Start Date',
          value: startMatch.group(1)!,
          confidence: 0.92,
          confidenceCategory: 'High',
        ),
      );
    }

    // 6. Policy Expiry Date
    final expMatch = RegExp(
      r'(?:TO MIDNIGHT OF|EXPIRY DATE|VALID TILL|POLICY END)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})',
    ).firstMatch(upper);
    if (expMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Policy Expiry Date',
          value: expMatch.group(1)!,
          confidence: 0.96,
          confidenceCategory: 'High',
        ),
      );
    }

    // 7. IDV (Insured Declared Value)
    final idvMatch = RegExp(
      r'(?:IDV|INSURED DECLARED VALUE)[\s:]*(?:RS\.?|INR)?\s*([0-9,]+)',
    ).firstMatch(upper);
    if (idvMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'IDV (Insured Declared Value)',
          value: '₹${idvMatch.group(1)!}',
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 8. Premium Amount
    final premMatch = RegExp(
      r'(?:TOTAL PREMIUM|PREMIUM AMOUNT|NET PREMIUM)[\s:]*(?:RS\.?|INR)?\s*([0-9,]+(?:\.[0-9]{2})?)',
    ).firstMatch(upper);
    if (premMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Premium Amount',
          value: '₹${premMatch.group(1)!}',
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }
  }

  // =========================================================================
  // 7. PASSPORT
  // =========================================================================
  static void _extractPassportFields(
    String fullText,
    String upper,
    List<String> lines,
    List<RawExtractedField> fields,
  ) {
    // 1. Passport Number
    final passMatch = RegExp(r'\b([A-Z][0-9]{7,8})\b').firstMatch(upper);
    if (passMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Passport Number',
          value: passMatch.group(1)!,
          confidence: 0.99,
          confidenceCategory: 'High',
          sourceSnippet: passMatch.group(1),
        ),
      );
    }

    // 2. Type & Country Code. These must come from the document itself: a
    // passport can be non-Indian even when it is imported into this app.
    final typeMatch = RegExp(
      r'(?:^|\n)\s*TYPE\s*[:\-]\s*([A-Z])\b',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (typeMatch != null) {
      final type = typeMatch.group(1)!.toUpperCase();
      fields.add(
        RawExtractedField(
          fieldName: 'Passport Type',
          value: type == 'P' ? 'P (Personal)' : type,
          confidence: 0.94,
          confidenceCategory: 'High',
        ),
      );
    }

    final countryMatch = RegExp(
      r'(?:COUNTRY\s*CODE|COUNTRY)\s*[:\-]\s*([A-Z]{3})\b',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (countryMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Country Code',
          value: countryMatch.group(1)!.toUpperCase(),
          confidence: 0.94,
          confidenceCategory: 'High',
        ),
      );
    }

    // 3. Surname & Given Names
    final surnameMatch = RegExp(
      r'(?:SURNAME|LAST NAME)[\s:]*([A-Za-z ]{2,30})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (surnameMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Surname',
          value: _cleanName(surnameMatch.group(1)!),
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    final givenMatch = RegExp(
      r'(?:GIVEN NAMES?|FIRST NAME)[\s:]*([A-Za-z ]{2,35})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (givenMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Given Names',
          value: _cleanName(givenMatch.group(1)!),
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 4. Nationality
    final nationalityMatch = RegExp(
      r'(?:NATIONALITY)\s*[:\-]\s*([A-Za-z ]{3,30})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (nationalityMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Nationality',
          value: nationalityMatch.group(1)!.trim().toUpperCase(),
          confidence: 0.94,
          confidenceCategory: 'High',
        ),
      );
    }

    // 5. Sex
    final sexMatch = RegExp(r'\b(SEX|GENDER)[\s:]*([MF])\b').firstMatch(upper);
    if (sexMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Sex',
          value: sexMatch.group(2) == 'M' ? 'Male' : 'Female',
          confidence: 0.92,
          confidenceCategory: 'High',
        ),
      );
    }

    // 6. Dates. Prefer their labels rather than assuming the first three
    // dates on a page are DOB, issue and expiry. That assumption frequently
    // turns a travel date or visa date into an identity field.
    final dobMatch = _findLabeledDate(fullText, ['DOB', 'DATE OF BIRTH']);
    if (dobMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Date of Birth',
          value: dobMatch,
          confidence: 0.94,
          confidenceCategory: 'High',
        ),
      );
    }
    final issueDate = _findLabeledDate(fullText, ['DOI', 'DATE OF ISSUE']);
    if (issueDate != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Date of Issue',
          value: issueDate,
          confidence: 0.94,
          confidenceCategory: 'High',
        ),
      );
    }
    final expiryDate = _findLabeledDate(fullText, [
      'DOE',
      'DATE OF EXPIRY',
      'EXPIRY DATE',
      'VALID UNTIL',
    ]);
    if (expiryDate != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Date of Expiry',
          value: expiryDate,
          confidence: 0.96,
          confidenceCategory: 'High',
        ),
      );
    }

    // 7. Place of Issue / Place of Birth
    final pobMatch = RegExp(
      r'(?:PLACE OF BIRTH)[\s:]*([A-Za-z ]{3,30})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (pobMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Place of Birth',
          value: _cleanName(pobMatch.group(1)!),
          confidence: 0.85,
          confidenceCategory: 'High',
        ),
      );
    }

    final poiMatch = RegExp(
      r'(?:PLACE OF ISSUE)[\s:]*([A-Za-z ]{3,30})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (poiMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Place of Issue',
          value: _cleanName(poiMatch.group(1)!),
          confidence: 0.85,
          confidenceCategory: 'High',
        ),
      );
    }
  }

  // =========================================================================
  // 8. BANK DOCUMENT (Statement / Passbook / Cheque)
  // CRITICAL SECURITY: Never extract ATM PIN, CVV, Card Expiry, Net Banking Password, OTP
  // =========================================================================
  static void _extractBankDocumentFields(
    String fullText,
    String upper,
    List<String> lines,
    List<RawExtractedField> fields,
  ) {
    // 1. Bank Name
    final bankMatch = RegExp(
      r'(?:STATE BANK OF INDIA|HDFC BANK|ICICI BANK|AXIS BANK|PUNJAB NATIONAL BANK|BANK OF BARODA|CANARA BANK|KOTAK MAHINDRA|UNION BANK|INDUSIND BANK|IDFC FIRST BANK|YES BANK)',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (bankMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Bank Name',
          value: bankMatch.group(0)!,
          confidence: 0.96,
          confidenceCategory: 'High',
        ),
      );
    }

    // 2. Account Holder Name
    final nameMatch = RegExp(
      r'(?:ACCOUNT HOLDER|CUSTOMER NAME)[\s:]*([A-Za-z ]{3,35})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (nameMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Account Holder Name',
          value: _cleanName(nameMatch.group(1)!),
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 3. Account Number
    final accMatch = RegExp(
      r'(?:A/C NO|ACCOUNT NO|ACCOUNT NUMBER)[\s:]*([0-9]{9,18})',
    ).firstMatch(upper);
    if (accMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Account Number',
          value: accMatch.group(1)!,
          confidence: 0.95,
          confidenceCategory: 'High',
          sourceSnippet: accMatch.group(1),
        ),
      );
    }

    // 4. IFSC Code
    final ifscMatch = RegExp(r'\b([A-Z]{4}0[A-Z0-9]{6})\b').firstMatch(upper);
    if (ifscMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'IFSC Code',
          value: ifscMatch.group(1)!,
          confidence: 0.98,
          confidenceCategory: 'High',
        ),
      );
    }

    // 5. Branch Name
    final branchMatch = RegExp(
      r'(?:BRANCH|BRANCH NAME)[\s:]*([A-Za-z0-9 ]{3,30})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (branchMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Branch Name',
          value: branchMatch.group(1)!.trim(),
          confidence: 0.86,
          confidenceCategory: 'High',
        ),
      );
    }

    // 6. MICR Code
    final micrMatch = RegExp(r'(?:MICR|MICR CODE)[\s:]*([0-9]{9})')
        .firstMatch(upper);
    if (micrMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'MICR Code',
          value: micrMatch.group(1)!,
          confidence: 0.90,
          confidenceCategory: 'High',
        ),
      );
    }

    // 7. Account Type
    if (upper.contains('SAVINGS') || upper.contains('SAVING A/C')) {
      fields.add(
        const RawExtractedField(
          fieldName: 'Account Type',
          value: 'Savings Account',
          confidence: 0.92,
          confidenceCategory: 'High',
        ),
      );
    } else if (upper.contains('CURRENT') || upper.contains('CURRENT A/C')) {
      fields.add(
        const RawExtractedField(
          fieldName: 'Account Type',
          value: 'Current Account',
          confidence: 0.92,
          confidenceCategory: 'High',
        ),
      );
    }
  }

  // =========================================================================
  // 9. EDUCATIONAL CERTIFICATE / MARKSHEET
  // =========================================================================
  static void _extractEducationCertificateFields(
    String fullText,
    String upper,
    List<String> lines,
    List<RawExtractedField> fields,
  ) {
    // 1. Candidate Name
    final nameMatch = RegExp(
      r'(?:NAME OF CANDIDATE|CANDIDATE NAME|STUDENT NAME)[\s:]*([A-Za-z ]{3,35})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (nameMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Candidate Name',
          value: _cleanName(nameMatch.group(1)!),
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 2. Roll Number / Reg No
    final rollMatch = RegExp(
      r'(?:ROLL NO|REGISTRATION NO|ENROLMENT NO)[\s:]*([A-Z0-9\/-]+)',
    ).firstMatch(upper);
    if (rollMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Roll / Registration Number',
          value: rollMatch.group(1)!,
          confidence: 0.92,
          confidenceCategory: 'High',
        ),
      );
    }

    // 3. Degree / Course Name
    final courseMatch = RegExp(
      r'(?:BACHELOR OF [A-Za-z ]+|MASTER OF [A-Za-z ]+|DIPLOMA IN [A-Za-z ]+|HIGHER SECONDARY|CLASS XII|CLASS X|B\.TECH|B\.E|B\.SC|B\.COM|M\.TECH)',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (courseMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Degree / Course',
          value: courseMatch.group(0)!.trim(),
          confidence: 0.90,
          confidenceCategory: 'High',
        ),
      );
    }

    // 4. Institution / University Name
    final univMatch = RegExp(
      r'(?:UNIVERSITY OF [A-Za-z ]+|[A-Za-z ]+ UNIVERSITY|CENTRAL BOARD OF SECONDARY EDUCATION|[A-Za-z ]+ COLLEGE)',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (univMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Institution / University',
          value: univMatch.group(0)!.trim(),
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 5. Passing Year
    final yearMatch = RegExp(
      r'(?:YEAR OF PASSING|PASSING YEAR|HELD IN)[\s:]*([0-9]{4})',
    ).firstMatch(upper);
    if (yearMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Passing Year',
          value: yearMatch.group(1)!,
          confidence: 0.90,
          confidenceCategory: 'High',
        ),
      );
    }

    // 6. Grade / CGPA / Percentage
    final gradeMatch = RegExp(
      r'(?:CGPA|PERCENTAGE|GRADE|MARKS OBTAINED)[\s:]*([0-9\.]+(?:%|\s*CGPA|\s*\/\s*10)?)',
    ).firstMatch(upper);
    if (gradeMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Grade / CGPA / Percentage',
          value: gradeMatch.group(1)!,
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }
  }

  // =========================================================================
  // 10. PROPERTY / RENT AGREEMENT / OWNERSHIP
  // =========================================================================
  static void _extractPropertyFields(
    String fullText,
    String upper,
    List<String> lines,
    List<RawExtractedField> fields,
  ) {
    // 1. Document Title / Agreement Type
    if (upper.contains('RENT AGREEMENT') || upper.contains('LEASE AGREEMENT')) {
      fields.add(
        const RawExtractedField(
          fieldName: 'Agreement Type',
          value: 'Rent / Lease Agreement',
          confidence: 0.95,
          confidenceCategory: 'High',
        ),
      );
    } else if (upper.contains('SALE DEED')) {
      fields.add(
        const RawExtractedField(
          fieldName: 'Agreement Type',
          value: 'Sale Deed',
          confidence: 0.95,
          confidenceCategory: 'High',
        ),
      );
    } else if (lines.isNotEmpty) {
      fields.add(
        RawExtractedField(
          fieldName: 'Agreement Type',
          value: lines.first,
          confidence: 0.80,
          confidenceCategory: 'Medium',
        ),
      );
    }

    // 2. Lessor / Landlord / Owner Name
    final lessorMatch = RegExp(
      r'(?:LESSOR|LANDLORD|OWNER|FIRST PARTY)[\s:]*([A-Za-z ]{3,35})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (lessorMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Lessor / Owner Name',
          value: _cleanName(lessorMatch.group(1)!),
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 3. Lessee / Tenant / Buyer Name
    final lesseeMatch = RegExp(
      r'(?:LESSEE|TENANT|BUYER|SECOND PARTY)[\s:]*([A-Za-z ]{3,35})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (lesseeMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Lessee / Tenant Name',
          value: _cleanName(lesseeMatch.group(1)!),
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 4. Property Address / Demised Premises
    final propAddrMatch = RegExp(
      r'(?:PROPERTY ADDRESS|PREMISES|FLAT NO|SITUATED AT)[\s:]*([^\n\r]{10,80})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (propAddrMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Property Address',
          value: propAddrMatch.group(1)!.trim(),
          confidence: 0.85,
          confidenceCategory: 'High',
        ),
      );
    }

    // 5. Agreement Date
    final dateMatch = RegExp(
      r'(?:EXECUTED ON|AGREEMENT DATE|DATE OF EXECUTION)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})',
    ).firstMatch(upper);
    if (dateMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Agreement Date',
          value: dateMatch.group(1)!,
          confidence: 0.90,
          confidenceCategory: 'High',
        ),
      );
    }

    // 6. Term / Lease Period
    final termMatch = RegExp(
      r'(?:TERM|PERIOD|LEASE PERIOD)[\s:]*([0-9]{1,2}\s*(?:MONTHS|YEARS))',
    ).firstMatch(upper);
    if (termMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Lease Period',
          value: termMatch.group(1)!,
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 7. Monthly Rent / Consideration
    final rentMatch = RegExp(
      r'(?:MONTHLY RENT|RENT AMOUNT|CONSIDERATION)[\s:]*(?:RS\.?|INR)?\s*([0-9,]+)',
    ).firstMatch(upper);
    if (rentMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Monthly Rent',
          value: rentMatch.group(1)!,
          confidence: 0.89,
          confidenceCategory: 'High',
        ),
      );
    }

    // 8. Security Deposit
    final depositMatch = RegExp(
      r'(?:SECURITY DEPOSIT|DEPOSIT AMOUNT)[\s:]*(?:RS\.?|INR)?\s*([0-9,]+)',
    ).firstMatch(upper);
    if (depositMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Security Deposit',
          value: depositMatch.group(1)!,
          confidence: 0.89,
          confidenceCategory: 'High',
        ),
      );
    }

    // 9. Registration / Stamp Duty Number
    final regNumMatch = RegExp(
      r'(?:REGISTRATION NO|DOC NO|STAMP DUTY)[\s:#]*([A-Z0-9\/-]{4,25})',
    ).firstMatch(upper);
    if (regNumMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Registration / Document No',
          value: regNumMatch.group(1)!,
          confidence: 0.86,
          confidenceCategory: 'High',
        ),
      );
    }
  }

  // =========================================================================
  // 11. MEDICAL REPORT / HEALTH INSURANCE
  // =========================================================================
  static void _extractMedicalFields(
    String fullText,
    String upper,
    List<String> lines,
    List<RawExtractedField> fields,
  ) {
    // 1. Patient Name
    final patMatch = RegExp(
      r'(?:PATIENT NAME|PATIENT|NAME OF PATIENT)[\s:]*([A-Za-z ]{3,35})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (patMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Patient Name',
          value: _cleanName(patMatch.group(1)!),
          confidence: 0.92,
          confidenceCategory: 'High',
        ),
      );
    }

    // 2. Age / Gender
    final ageGenderMatch = RegExp(
      r'(?:AGE\s*(?:\/|\&)?\s*(?:SEX|GENDER)?|PATIENT AGE)[\s\/:;]*([0-9]{1,3}(?:\s*(?:YEARS|YRS|Y))?(?:\s*[\/\-]?\s*(?:MALE|FEMALE|OTHER|M|F))?)',
      caseSensitive: false,
    ).firstMatch(upper);
    if (ageGenderMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Age / Gender',
          value: ageGenderMatch.group(1)!.trim(),
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 3. Doctor / Consultant Name
    final docMatch = RegExp(
      r'(?:CONSULTANT|REFERRED BY|DOCTOR|DR\.?)[\s:]*([A-Za-z \.]{3,35})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (docMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Consulting Doctor',
          value: _cleanName(docMatch.group(1)!),
          confidence: 0.89,
          confidenceCategory: 'High',
        ),
      );
    }

    // 4. Hospital / Clinic / Lab Name
    final hospFieldMatch = RegExp(
      r'(?:HOSPITAL|CLINIC|LAB|LABORATORY)[\s]*:[\s]*([A-Za-z0-9 \.\-]{3,40})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (hospFieldMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Hospital / Lab Name',
          value: hospFieldMatch.group(1)!.trim(),
          confidence: 0.90,
          confidenceCategory: 'High',
        ),
      );
    } else if (lines.isNotEmpty &&
        (lines.first.toUpperCase().contains('HOSPITAL') ||
            lines.first.toUpperCase().contains('LAB') ||
            lines.first.toUpperCase().contains('HEALTHCARE') ||
            lines.first.toUpperCase().contains('CLINIC'))) {
      fields.add(
        RawExtractedField(
          fieldName: 'Hospital / Lab Name',
          value: lines.first,
          confidence: 0.85,
          confidenceCategory: 'High',
        ),
      );
    }

    // 5. Report Date / Collection Date
    final repDateMatch = RegExp(
      r'(?:REPORT DATE|COLLECTION DATE|DATE OF REPORT|DATE)[\s:]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})',
    ).firstMatch(upper);
    if (repDateMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Report Date',
          value: repDateMatch.group(1)!,
          confidence: 0.92,
          confidenceCategory: 'High',
        ),
      );
    }

    // 6. Test Name / Investigation / Diagnosis
    final testMatch = RegExp(
      r'(?:INVESTIGATION|TEST NAME|DIAGNOSIS|REPORT FOR)[\s:]*([A-Za-z0-9 \(\)\.\-]{3,40})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (testMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Investigation / Test Name',
          value: testMatch.group(1)!.trim(),
          confidence: 0.88,
          confidenceCategory: 'High',
        ),
      );
    }

    // 7. UHID / Patient ID / Lab Ref No
    final uhidMatch = RegExp(
      r'(?:UHID|PATIENT ID|SAMPLE ID|REF NO|LAB NO)[\s:#]*([A-Z0-9-]{4,20})',
    ).firstMatch(upper);
    if (uhidMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Patient UHID / Ref No',
          value: uhidMatch.group(1)!,
          confidence: 0.90,
          confidenceCategory: 'High',
        ),
      );
    }
  }

  // =========================================================================
  // 12. GENERIC / OTHER DOCUMENTS + DYNAMIC DISCOVERY
  // =========================================================================
  static void _extractGenericFields(
    String fullText,
    String upper,
    List<String> lines,
    List<RawExtractedField> fields,
  ) {
    // 1. Document Title
    if (lines.isNotEmpty) {
      fields.add(
        RawExtractedField(
          fieldName: 'Document Title',
          value: lines.first,
          confidence: 0.80,
          confidenceCategory: 'High',
        ),
      );
    }

    // 2. Dates
    final dates = RegExp(r'\b(\d{2}[\/\.-]\d{2}[\/\.-]\d{4})\b')
        .allMatches(upper)
        .toList();
    if (dates.isNotEmpty) {
      fields.add(
        RawExtractedField(
          fieldName: 'Document Date',
          value: dates.first.group(1)!,
          confidence: 0.85,
          confidenceCategory: 'High',
        ),
      );
    }

    // 3. Reference Number
    final refMatch = RegExp(r'(?:NO|NUMBER|REF|ID)[\s.:#]*([A-Z0-9-]{6,25})')
        .firstMatch(upper);
    if (refMatch != null) {
      fields.add(
        RawExtractedField(
          fieldName: 'Reference Number',
          value: refMatch.group(1)!,
          confidence: 0.82,
          confidenceCategory: 'Medium',
        ),
      );
    }

    // 4. Dynamic Key-Value Field Discovery (Line patterns like "Key : Value")
    final kvRegex = RegExp(r'^([A-Za-z ]{3,22})\s*[:=]\s*([^\n\r]{2,60})$');
    for (final line in lines) {
      final match = kvRegex.firstMatch(line);
      if (match != null) {
        final key = match.group(1)!.trim();
        final val = match.group(2)!.trim();
        // Ignore overly short or sensitive tokens
        if (key.length >= 3 &&
            val.isNotEmpty &&
            !_isSensitiveExcludedKey(key)) {
          if (!fields.any(
            (f) => f.fieldName.toLowerCase() == key.toLowerCase(),
          )) {
            fields.add(
              RawExtractedField(
                fieldName: _toTitleCase(key),
                value: val,
                confidence: 0.80,
                confidenceCategory: 'Medium',
                isSelected: true,
              ),
            );
          }
        }
      }
    }
  }

  // =========================================================================
  // HELPER METHODS
  // =========================================================================
  static String _normalizeOcrText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp('[\u2010-\u2015\u2212]'), '-')
        .replaceAll('\u200B', '')
        .replaceAll(RegExp(r'[ \t]+'), ' ');
  }

  /// OCR often puts a space or a hyphen between number-plate groups. Keep the
  /// detector flexible, but only return a canonical value after every group
  /// matches the Indian registration-number shape.
  static String? _findVehicleRegistration(String text) {
    final match = RegExp(
      r'(?<![A-Z0-9])([A-Z]{2}[ \t-]*[0-9]{1,2}[ \t-]*[A-Z]{1,3}[ \t-]*[0-9]{4})(?![A-Z0-9])',
    ).firstMatch(text.toUpperCase());
    return match?.group(1)?.replaceAll(RegExp(r'[\s-]'), '');
  }

  /// Supports printed, hyphenated and tightly grouped Aadhaar numbers. The
  /// digit boundaries prevent taking the first twelve digits of a VID or a
  /// longer account number.
  static String? _findAadhaarNumber(String text) {
    final match = RegExp(r'(?<!\d)(\d{4}[ \t-]*\d{4}[ \t-]*\d{4})(?!\d)')
        .firstMatch(text);
    final digits = match?.group(1)?.replaceAll(RegExp(r'\D'), '');
    return digits != null && digits.length == 12 ? digits : null;
  }

  static String? _findLabeledDate(String text, List<String> labels) {
    final escapedLabels = labels.map(RegExp.escape).join('|');
    final match = RegExp(
      '(?:$escapedLabels)\\b\\s*(?:[:=-]\\s*)?(\\d{1,2}\\s*[/.\\-]\\s*\\d{1,2}\\s*[/.\\-]\\s*\\d{4})',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;

    final value = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
    return _isRealDate(value) ? value : null;
  }

  static bool _isRealDate(String value) {
    final match = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})$')
        .firstMatch(value);
    if (match == null) return false;
    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final year = int.tryParse(match.group(3)!);
    if (day == null ||
        month == null ||
        year == null ||
        year < 1900 ||
        year > 2100) {
      return false;
    }
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }

  static List<RawExtractedField> _deduplicateFields(
    List<RawExtractedField> fields,
  ) {
    final byName = <String, RawExtractedField>{};
    for (final field in fields) {
      final key = field.fieldName.trim().toLowerCase();
      if (key.isEmpty || field.value.trim().isEmpty) continue;
      final existing = byName[key];
      if (existing == null || field.confidence > existing.confidence) {
        byName[key] = field;
      }
    }
    return byName.values.toList(growable: false);
  }

  static String _cleanName(String raw) {
    return raw
        .replaceAll(
          RegExp(
            r'^(MR\.?|MRS\.?|MS\.?|DR\.?|SHRI|SMT\.?)\s+',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'[^A-Za-z\u0900-\u097F\u0A80-\u0AFF \.]'), '')
        .trim();
  }

  static bool _isValidName(String s) {
    final clean = s.trim();
    return clean.length >= 3 &&
        clean.length <= 40 &&
        RegExp(r'^[A-Za-z\u0900-\u097F\u0A80-\u0AFF \.]+$').hasMatch(clean);
  }

  /// Avoid presenting arbitrary OCR prose as a person's name. This is stricter
  /// than _isValidName because extracted data is shown as verified-looking
  /// information in the document screen.
  static bool _isLikelyPersonName(String value) {
    final clean = value.trim();
    if (!_isValidName(clean) || clean.split(RegExp(r'\s+')).length < 2) {
      return false;
    }
    final upper = clean.toUpperCase();
    const disallowed = [
      'POLICY',
      'PACKAGE',
      'INSURANCE',
      'VEHICLE',
      'REGISTRATION',
      'CERTIFICATE',
      'DEPARTMENT',
      'AUTHORITY',
    ];
    return !disallowed.any(upper.contains);
  }

  static bool _isLikelyAuthority(String value) {
    final upper = value.toUpperCase();
    return !upper.contains('POLICY') &&
        !upper.contains('REGISTRATION') &&
        !upper.contains('VEHICLE') &&
        (upper.contains('RTO') ||
            upper.contains('TRANSPORT') ||
            upper.contains('LICENSING') ||
            upper.contains('REGIONAL'));
  }

  static bool _isSensitiveExcludedKey(String key) {
    final lower = key.toLowerCase();
    return lower.contains('pin') ||
        lower.contains('cvv') ||
        lower.contains('otp') ||
        lower.contains('password') ||
        lower.contains('card exp');
  }

  static String _toTitleCase(String str) {
    return str
        .split(' ')
        .map(
          (w) => w.isNotEmpty
              ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
              : '',
        )
        .join(' ');
  }
}
