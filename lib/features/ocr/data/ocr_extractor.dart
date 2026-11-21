class OcrExtractionResult {
  final String rawText;
  final String? suggestedName;
  final String? suggestedCategoryId;
  final String? suggestedDocumentType;
  final String? suggestedNumber;
  final String? suggestedOwner;
  final String? suggestedAuthority;
  final DateTime? suggestedIssueDate;
  final DateTime? suggestedExpiryDate;

  const OcrExtractionResult({
    required this.rawText,
    this.suggestedName,
    this.suggestedCategoryId,
    this.suggestedDocumentType,
    this.suggestedNumber,
    this.suggestedOwner,
    this.suggestedAuthority,
    this.suggestedIssueDate,
    this.suggestedExpiryDate,
  });
}

class OcrExtractor {
  static OcrExtractionResult extract(String rawText) {
    if (rawText.trim().isEmpty) {
      return OcrExtractionResult(rawText: rawText);
    }

    final upper = rawText.toUpperCase();
    String? name;
    String? categoryId;
    String? docType;
    String? docNumber;
    String? owner;
    String? authority;
    DateTime? issueDate;
    DateTime? expiryDate;

    // 1. Identify Document Type & Category
    if (upper.contains('INCOME TAX') ||
        upper.contains('PERMANENT ACCOUNT NUMBER') ||
        RegExp(r'\bPAN\b').hasMatch(upper)) {
      name = 'PAN Card';
      categoryId = 'personal_identity';
      docType = 'PAN Card';
      authority = 'Income Tax Department';

      final panMatch = RegExp(r'\b[A-Z]{5}[0-9]{4}[A-Z]\b').firstMatch(upper);
      if (panMatch != null) {
        docNumber = panMatch.group(0);
      }
    } else if (upper.contains('UNIQUE IDENTIFICATION') ||
        upper.contains('AADHAAR') ||
        upper.contains('UIDAI')) {
      name = 'Aadhaar Card';
      categoryId = 'personal_identity';
      docType = 'Aadhaar Card';
      authority = 'UIDAI';

      docNumber = _findAadhaarNumber(rawText);
    } else if ((upper.contains('MOTOR INSURANCE') ||
            upper.contains('VEHICLE INSURANCE') ||
            upper.contains('PACKAGE POLICY') ||
            upper.contains('LIABILITY ONLY POLICY')) &&
        (upper.contains('REGISTRATION NO') ||
            upper.contains('REGISTRATION NUMBER') ||
            upper.contains('INSURED VEHICLE') ||
            upper.contains('VEHICLE REGISTRATION'))) {
      // Policies can include a driver's licence number. Prefer the document's
      // own policy and vehicle markers over that incidental information.
      name = 'Vehicle Insurance Policy';
      categoryId = 'vehicle_documents';
      docType = 'Vehicle Insurance';
    } else if (upper.contains('DRIVING LICENCE') ||
        upper.contains('DRIVING LICENSE') ||
        upper.contains('UNION OF INDIA DRIVING')) {
      name = 'Driving Licence';
      categoryId = 'vehicle_documents';
      docType = 'Driving Licence';
      authority = 'Transport Department';

      final dlMatch = RegExp(r'\b[A-Z]{2}[ \t-]*[0-9]{2}[ \t-]*[0-9]{11}\b')
          .firstMatch(upper);
      if (dlMatch != null) {
        docNumber = dlMatch.group(0)!.replaceAll(RegExp(r'[\s-]'), '');
      }
    } else if (upper.contains('POLLUTION UNDER CONTROL') ||
        upper.contains('PUC CERTIFICATE') ||
        upper.contains('PUCC')) {
      name = 'PUC Certificate';
      categoryId = 'vehicle_documents';
      docType = 'PUC Certificate';
      authority = 'Transport Department';
    } else if (upper.contains('CERTIFICATE OF REGISTRATION') ||
        upper.contains('REGISTRATION CERTIFICATE') ||
        upper.contains('FORM 23')) {
      name = 'Vehicle RC Book';
      categoryId = 'vehicle_documents';
      docType = 'Vehicle RC Book';
      authority = 'Transport Department';
    } else if (upper.contains('PASSPORT') ||
        upper.contains('REPUBLIC OF INDIA')) {
      name = 'Passport';
      categoryId = 'personal_identity';
      docType = 'Passport';
      authority = 'Ministry of External Affairs';

      final passMatch = RegExp(r'\b[A-Z][0-9]{7,8}\b').firstMatch(upper);
      if (passMatch != null) {
        docNumber = passMatch.group(0);
      }
    } else if (upper.contains('ELECTION COMMISSION') ||
        upper.contains('ELECTOR PHOTO') ||
        upper.contains('VOTER')) {
      name = 'Voter ID';
      categoryId = 'personal_identity';
      docType = 'Voter ID';
      authority = 'Election Commission of India';

      final epicMatch = RegExp(r'\b[A-Z]{3}[0-9]{7}\b').firstMatch(upper);
      if (epicMatch != null) {
        docNumber = epicMatch.group(0);
      }
    } else if (upper.contains('INSURANCE') || upper.contains('POLICY')) {
      name = 'Insurance Policy';
      categoryId = 'financial_documents';
      docType = 'Insurance Policies';
    } else if (upper.contains('UNIVERSITY') ||
        upper.contains('MARKSHEET') ||
        upper.contains('DEGREE') ||
        upper.contains('EXAMINATION')) {
      name = 'Degree Certificate';
      categoryId = 'education';
      docType = 'Degree Certificates';
    } else {
      name = 'Document';
      categoryId = 'other';
      docType = 'Custom Documents';
    }

    // 2. Generic Vehicle Number matching if doc is vehicle related
    if (categoryId == 'vehicle_documents' && docNumber == null) {
      docNumber = _findVehicleRegistration(upper);
    }

    // 3. Extract dates. Both common Indian (DD/MM/YYYY) and ISO
    // (YYYY-MM-DD) notation occur in imported statements and certificates.
    final dateMatches = RegExp(r'\b(\d{1,4})[/\-\.](\d{1,2})[/\-\.](\d{1,4})\b')
        .allMatches(rawText);
    final List<DateTime> extractedDates = [];
    for (final m in dateMatches) {
      final parsed = _parseDateMatch(m);
      if (parsed != null) extractedDates.add(parsed);
    }

    // 4. Prefer explicit labels. A DOB is usually an old date, so choosing
    // the earliest past date as an issue date makes otherwise good OCR look
    // incorrect in the review screen.
    final lines = rawText.split('\n');
    for (final line in lines) {
      final lineUpper = line.toUpperCase();
      final lineDateMatch = RegExp(
        r'\b(\d{1,4})[/\-\.](\d{1,2})[/\-\.](\d{1,4})\b',
      ).firstMatch(line);
      final parsed = lineDateMatch == null
          ? null
          : _parseDateMatch(lineDateMatch);
      if (lineUpper.contains('VALID UPTO') ||
          lineUpper.contains('VALID TILL') ||
          lineUpper.contains('EXPIRY') ||
          lineUpper.contains('EXP DATE')) {
        if (parsed != null) expiryDate = parsed;
      }
      if (lineUpper.contains('ISSUE DATE') ||
          lineUpper.contains('DATE OF ISSUE') ||
          lineUpper.contains('ISSUED ON') ||
          RegExp(r'\bDOI\b').hasMatch(lineUpper)) {
        if (parsed != null) issueDate = parsed;
      }
      if (lineUpper.contains('NAME') &&
          !lineUpper.contains('FATHER') &&
          !lineUpper.contains('DEPARTMENT')) {
        final parts = line.split(RegExp(r'[:\-]'));
        if (parts.length > 1) {
          final candidate = parts[1].trim();
          if (candidate.length > 2 &&
              candidate.length < 40 &&
              !candidate.contains(RegExp(r'\d'))) {
            owner ??= candidate;
          }
        }
      }
    }

    // Fall back only when a document did not provide a semantic date label.
    extractedDates.sort();
    final now = DateTime.now();
    for (final date in extractedDates) {
      if (date.isAfter(now)) {
        expiryDate ??= date;
      } else {
        issueDate ??= date;
      }
    }

    return OcrExtractionResult(
      rawText: rawText,
      suggestedName: name,
      suggestedCategoryId: categoryId,
      suggestedDocumentType: docType,
      suggestedNumber: docNumber,
      suggestedOwner: owner,
      suggestedAuthority: authority,
      suggestedIssueDate: issueDate,
      suggestedExpiryDate: expiryDate,
    );
  }

  static String? _findAadhaarNumber(String text) {
    final match = RegExp(r'(?<!\d)(\d{4}[ \t-]*\d{4}[ \t-]*\d{4})(?!\d)')
        .firstMatch(text);
    final digits = match?.group(1)?.replaceAll(RegExp(r'\D'), '');
    if (digits == null || digits.length != 12) return null;
    return '${digits.substring(0, 4)} ${digits.substring(4, 8)} ${digits.substring(8)}';
  }

  static String? _findVehicleRegistration(String text) {
    final match = RegExp(
      r'(?<![A-Z0-9])([A-Z]{2}[ \t-]*[0-9]{1,2}[ \t-]*[A-Z]{1,3}[ \t-]*[0-9]{4})(?![A-Z0-9])',
    ).firstMatch(text.toUpperCase());
    return match?.group(1)?.replaceAll(RegExp(r'[\s-]'), '');
  }

  static DateTime? _parseDateMatch(RegExpMatch match) {
    final first = int.tryParse(match.group(1) ?? '');
    final second = int.tryParse(match.group(2) ?? '');
    final third = int.tryParse(match.group(3) ?? '');
    if (first == null || second == null || third == null) return null;

    final isIso = (match.group(1)?.length ?? 0) == 4;
    final year = isIso ? first : third;
    final month = second;
    final day = isIso ? third : first;
    if (year < 1950 ||
        year > 2060 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      return null;
    }
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }
}
