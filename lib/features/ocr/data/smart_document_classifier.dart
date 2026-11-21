class ClassifiedDocumentInfo {
  final String categoryId;
  final String documentType;
  final String suggestedName;
  final double confidence;

  const ClassifiedDocumentInfo({
    required this.categoryId,
    required this.documentType,
    required this.suggestedName,
    required this.confidence,
  });
}

/// Local, offline document classifier using keyword density, regex patterns,
/// and document structure recognition.
class SmartDocumentClassifier {
  static ClassifiedDocumentInfo classify(String text, {String? originalFileName}) {
    final upper = text.toUpperCase();
    final lowerName = originalFileName?.toLowerCase() ?? '';

    // 1. Personal Identity: PAN Card
    if (upper.contains('INCOME TAX DEPARTMENT') ||
        upper.contains('PERMANENT ACCOUNT NUMBER') ||
        upper.contains('GOVT. OF INDIA') && upper.contains('PAN') ||
        RegExp(r'\b[A-Z]{5}[0-9]{4}[A-Z]\b').hasMatch(upper)) {
      return const ClassifiedDocumentInfo(
        categoryId: 'personal_identity',
        documentType: 'PAN Card',
        suggestedName: 'PAN Card',
        confidence: 0.95,
      );
    }

    // 2. Personal Identity: Aadhaar Card
    if (upper.contains('UNIQUE IDENTIFICATION AUTHORITY OF INDIA') ||
        upper.contains('AADHAAR') ||
        upper.contains('UIDAI') ||
        upper.contains('MERA AADHAAR') ||
        upper.contains('HELP@UIDAI.GOV.IN') ||
        RegExp(r'\b\d{4}\s\d{4}\s\d{4}\b').hasMatch(text)) {
      return const ClassifiedDocumentInfo(
        categoryId: 'personal_identity',
        documentType: 'Aadhaar Card',
        suggestedName: 'Aadhaar Card',
        confidence: 0.95,
      );
    }

    // 3. Vehicle Documents: Driving Licence
    if (upper.contains('DRIVING LICENCE') ||
        upper.contains('DRIVING LICENSE') ||
        upper.contains('UNION OF INDIA DRIVING') ||
        upper.contains('FORM 7') && upper.contains('LICENCE') ||
        RegExp(r'\b[A-Z]{2}[0-9]{2}\s?[0-9]{11}\b').hasMatch(upper)) {
      return const ClassifiedDocumentInfo(
        categoryId: 'vehicle_documents',
        documentType: 'Driving Licence',
        suggestedName: 'Driving Licence',
        confidence: 0.92,
      );
    }

    // 4. Vehicle Documents: Vehicle RC Book
    if (upper.contains('CERTIFICATE OF REGISTRATION') ||
        upper.contains('REGISTRATION CERTIFICATE') ||
        upper.contains('FORM 23') ||
        upper.contains('CHASSIS NO') && upper.contains('ENGINE NO') ||
        upper.contains('VEHICLE CLASS') && upper.contains('REGISTERED OWNER')) {
      return const ClassifiedDocumentInfo(
        categoryId: 'vehicle_documents',
        documentType: 'Vehicle RC Book',
        suggestedName: 'Vehicle RC Book',
        confidence: 0.90,
      );
    }

    // 5. Vehicle Documents: PUC Certificate
    if (upper.contains('POLLUTION UNDER CONTROL') ||
        upper.contains('PUC CERTIFICATE') ||
        upper.contains('PUCC') ||
        upper.contains('EMISSION NORMS') && upper.contains('POLLUTION')) {
      return const ClassifiedDocumentInfo(
        categoryId: 'vehicle_documents',
        documentType: 'PUC Certificate',
        suggestedName: 'PUC Certificate',
        confidence: 0.92,
      );
    }

    // 6. Vehicle Documents: Vehicle Insurance
    if ((upper.contains('MOTOR INSURANCE') ||
            upper.contains('VEHICLE INSURANCE') ||
            upper.contains('PACKAGE POLICY') ||
            upper.contains('LIABILITY ONLY POLICY')) &&
        (upper.contains('REGISTRATION NO') || upper.contains('INSURED VEHICLE'))) {
      return const ClassifiedDocumentInfo(
        categoryId: 'vehicle_documents',
        documentType: 'Vehicle Insurance',
        suggestedName: 'Vehicle Insurance Policy',
        confidence: 0.88,
      );
    }

    // 7. Personal Identity: Passport
    if (upper.contains('PASSPORT') && (upper.contains('REPUBLIC OF INDIA') || upper.contains('EXTERNAL AFFAIRS')) ||
        RegExp(r'\b[A-Z][0-9]{7,8}\b').hasMatch(upper) && upper.contains('NATIONALITY')) {
      return const ClassifiedDocumentInfo(
        categoryId: 'personal_identity',
        documentType: 'Passport',
        suggestedName: 'Passport',
        confidence: 0.95,
      );
    }

    // 8. Personal Identity: Voter ID
    if (upper.contains('ELECTION COMMISSION') ||
        upper.contains('ELECTOR PHOTO') ||
        upper.contains('VOTER IDENTITY') ||
        RegExp(r'\b[A-Z]{3}[0-9]{7}\b').hasMatch(upper)) {
      return const ClassifiedDocumentInfo(
        categoryId: 'personal_identity',
        documentType: 'Voter ID',
        suggestedName: 'Voter ID Card',
        confidence: 0.90,
      );
    }

    // 9. Personal Identity: Birth Certificate
    if (upper.contains('BIRTH CERTIFICATE') ||
        upper.contains('REGISTRAR OF BIRTH') ||
        upper.contains('CERTIFICATE OF BIRTH')) {
      return const ClassifiedDocumentInfo(
        categoryId: 'personal_identity',
        documentType: 'Birth Certificate',
        suggestedName: 'Birth Certificate',
        confidence: 0.85,
      );
    }

    // 10. Financial: Bank Documents
    if (upper.contains('STATEMENT OF ACCOUNT') ||
        upper.contains('BANK STATEMENT') ||
        upper.contains('ACCOUNT NUMBER') && upper.contains('IFSC') ||
        upper.contains('SAVINGS ACCOUNT') ||
        upper.contains('CURRENT ACCOUNT')) {
      return const ClassifiedDocumentInfo(
        categoryId: 'financial',
        documentType: 'Bank Document',
        suggestedName: 'Bank Document',
        confidence: 0.85,
      );
    }

    // 11. Financial: Tax Documents
    if (upper.contains('FORM 16') ||
        upper.contains('ASSESSMENT YEAR') ||
        upper.contains('ITR-V') ||
        upper.contains('INCOME TAX RETURN')) {
      return const ClassifiedDocumentInfo(
        categoryId: 'financial',
        documentType: 'Tax Document',
        suggestedName: 'Tax Document',
        confidence: 0.88,
      );
    }

    // 12. Education: Degree / Marksheet
    if (upper.contains('DEGREE OF') ||
        upper.contains('STATEMENT OF MARKS') ||
        upper.contains('MARK SHEET') ||
        upper.contains('UNIVERSITY') && upper.contains('PASSED')) {
      return ClassifiedDocumentInfo(
        categoryId: 'education',
        documentType: upper.contains('MARK') ? 'Mark Sheet' : 'Degree Certificate',
        suggestedName: 'Academic Certificate',
        confidence: 0.82,
      );
    }

    // 13. Property: Rental / Sale Deed
    if (upper.contains('RENTAL AGREEMENT') ||
        upper.contains('LEASE AGREEMENT') ||
        upper.contains('SALE DEED') ||
        upper.contains('TENANCY AGREEMENT')) {
      return const ClassifiedDocumentInfo(
        categoryId: 'property',
        documentType: 'Property Document',
        suggestedName: 'Property Agreement',
        confidence: 0.82,
      );
    }

    // 14. Medical: Lab / Health Report
    if (upper.contains('LABORATORY REPORT') ||
        upper.contains('PATHOLOGY') ||
        upper.contains('DIAGNOSTIC REPORT') ||
        upper.contains('PRESCRIPTION')) {
      return const ClassifiedDocumentInfo(
        categoryId: 'medical',
        documentType: 'Medical Report',
        suggestedName: 'Medical Report',
        confidence: 0.80,
      );
    }

    // Filename heuristics fallback
    if (lowerName.contains('pan')) {
      return const ClassifiedDocumentInfo(categoryId: 'personal_identity', documentType: 'PAN Card', suggestedName: 'PAN Card', confidence: 0.6);
    } else if (lowerName.contains('aadhaar') || lowerName.contains('aadhar')) {
      return const ClassifiedDocumentInfo(categoryId: 'personal_identity', documentType: 'Aadhaar Card', suggestedName: 'Aadhaar Card', confidence: 0.6);
    } else if (lowerName.contains('dl') || lowerName.contains('licence') || lowerName.contains('license')) {
      return const ClassifiedDocumentInfo(categoryId: 'vehicle_documents', documentType: 'Driving Licence', suggestedName: 'Driving Licence', confidence: 0.6);
    } else if (lowerName.contains('rc') || lowerName.contains('vehicle')) {
      return const ClassifiedDocumentInfo(categoryId: 'vehicle_documents', documentType: 'Vehicle RC Book', suggestedName: 'Vehicle RC Book', confidence: 0.6);
    } else if (lowerName.contains('puc')) {
      return const ClassifiedDocumentInfo(categoryId: 'vehicle_documents', documentType: 'PUC Certificate', suggestedName: 'PUC Certificate', confidence: 0.6);
    } else if (lowerName.contains('passport')) {
      return const ClassifiedDocumentInfo(categoryId: 'personal_identity', documentType: 'Passport', suggestedName: 'Passport', confidence: 0.6);
    }

    return const ClassifiedDocumentInfo(
      categoryId: 'other',
      documentType: 'General Document',
      suggestedName: 'Imported Document',
      confidence: 0.3,
    );
  }
}
