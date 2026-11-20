import 'package:intl/intl.dart';

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
    if (upper.contains('INCOME TAX') || upper.contains('PERMANENT ACCOUNT NUMBER') || upper.contains('PAN')) {
      name = 'PAN Card';
      categoryId = 'personal_identity';
      docType = 'PAN Card';
      authority = 'Income Tax Department';

      final panMatch = RegExp(r'\b[A-Z]{5}[0-9]{4}[A-Z]\b').firstMatch(upper);
      if (panMatch != null) {
        docNumber = panMatch.group(0);
      }
    } else if (upper.contains('UNIQUE IDENTIFICATION') || upper.contains('AADHAAR') || upper.contains('UIDAI')) {
      name = 'Aadhaar Card';
      categoryId = 'personal_identity';
      docType = 'Aadhaar Card';
      authority = 'UIDAI';

      final aadharMatch = RegExp(r'\b\d{4}\s\d{4}\s\d{4}\b').firstMatch(rawText);
      if (aadharMatch != null) {
        docNumber = aadharMatch.group(0);
      }
    } else if (upper.contains('DRIVING LICENCE') || upper.contains('DRIVING LICENSE') || upper.contains('UNION OF INDIA DRIVING')) {
      name = 'Driving Licence';
      categoryId = 'vehicle_documents';
      docType = 'Driving Licence';
      authority = 'Transport Department';

      final dlMatch = RegExp(r'\b[A-Z]{2}[0-9]{2}\s?[0-9]{11}\b').firstMatch(upper);
      if (dlMatch != null) {
        docNumber = dlMatch.group(0);
      }
    } else if (upper.contains('POLLUTION UNDER CONTROL') || upper.contains('PUC CERTIFICATE') || upper.contains('PUCC')) {
      name = 'PUC Certificate';
      categoryId = 'vehicle_documents';
      docType = 'PUC Certificate';
      authority = 'Transport Department';
    } else if (upper.contains('CERTIFICATE OF REGISTRATION') || upper.contains('REGISTRATION CERTIFICATE') || upper.contains('FORM 23')) {
      name = 'Vehicle RC Book';
      categoryId = 'vehicle_documents';
      docType = 'Vehicle RC Book';
      authority = 'Transport Department';
    } else if (upper.contains('PASSPORT') || upper.contains('REPUBLIC OF INDIA')) {
      name = 'Passport';
      categoryId = 'personal_identity';
      docType = 'Passport';
      authority = 'Ministry of External Affairs';

      final passMatch = RegExp(r'\b[A-Z][0-9]{7,8}\b').firstMatch(upper);
      if (passMatch != null) {
        docNumber = passMatch.group(0);
      }
    } else if (upper.contains('ELECTION COMMISSION') || upper.contains('ELECTOR PHOTO') || upper.contains('VOTER')) {
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
    } else if (upper.contains('UNIVERSITY') || upper.contains('MARKSHEET') || upper.contains('DEGREE') || upper.contains('EXAMINATION')) {
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
      final regMatch = RegExp(r'\b[A-Z]{2}[-\s]?[0-9]{1,2}[-\s]?[A-Z]{1,3}[-\s]?[0-9]{4}\b').firstMatch(upper);
      if (regMatch != null) {
        docNumber = regMatch.group(0);
      }
    }

    // 3. Extract Dates (DD/MM/YYYY or YYYY-MM-DD)
    final dateMatches = RegExp(r'\b(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{4})\b').allMatches(rawText);
    final List<DateTime> extractedDates = [];
    for (final m in dateMatches) {
      final day = int.tryParse(m.group(1) ?? '');
      final month = int.tryParse(m.group(2) ?? '');
      final year = int.tryParse(m.group(3) ?? '');
      if (day != null && month != null && year != null && month >= 1 && month <= 12 && day >= 1 && day <= 31 && year >= 1950 && year <= 2060) {
        try {
          extractedDates.add(DateTime(year, month, day));
        } catch (_) {}
      }
    }

    // Sort dates
    extractedDates.sort();

    // 4. Distinguish Issue Date vs Expiry Date
    final now = DateTime.now();
    for (final date in extractedDates) {
      if (date.isAfter(now)) {
        expiryDate ??= date; // Future date is likely expiry
      } else {
        issueDate ??= date; // Past date is likely issue or DOB
      }
    }

    // Look specifically for "Valid Upto" or "Expiry" lines
    final lines = rawText.split('\n');
    for (final line in lines) {
      final lineUpper = line.toUpperCase();
      if (lineUpper.contains('VALID UPTO') || lineUpper.contains('VALID TILL') || lineUpper.contains('EXPIRY') || lineUpper.contains('EXP DATE')) {
        final lineDateMatch = RegExp(r'\b(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{4})\b').firstMatch(line);
        if (lineDateMatch != null) {
          final d = int.tryParse(lineDateMatch.group(1) ?? '');
          final m = int.tryParse(lineDateMatch.group(2) ?? '');
          final y = int.tryParse(lineDateMatch.group(3) ?? '');
          if (d != null && m != null && y != null) {
            try {
              expiryDate = DateTime(y, m, d);
            } catch (_) {}
          }
        }
      }
      if (lineUpper.contains('NAME') && !lineUpper.contains('FATHER') && !lineUpper.contains('DEPARTMENT')) {
        final parts = line.split(RegExp(r'[:\-]'));
        if (parts.length > 1) {
          final candidate = parts[1].trim();
          if (candidate.length > 2 && candidate.length < 40 && !candidate.contains(RegExp(r'\d'))) {
            owner ??= candidate;
          }
        }
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
}

