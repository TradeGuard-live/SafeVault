class DefaultCategory {
  final String id;
  final String name;
  final String icon;
  final int colorValue;
  final List<String> documentTypes;

  const DefaultCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorValue,
    required this.documentTypes,
  });
}

class CategoryConstants {
  static const List<DefaultCategory> defaultCategories = [
    DefaultCategory(
      id: 'personal_identity',
      name: 'Personal Identity',
      icon: 'badge',
      colorValue: 0xFF0D9488, // Emerald Teal
      documentTypes: [
        'Aadhaar Card',
        'PAN Card',
        'Voter ID',
        'Passport',
        'Birth Certificate',
      ],
    ),
    DefaultCategory(
      id: 'vehicle_documents',
      name: 'Vehicle Documents',
      icon: 'directions_car',
      colorValue: 0xFF2563EB, // Royal Blue
      documentTypes: [
        'Driving Licence',
        'Vehicle RC Book',
        'PUC Certificate',
        'Vehicle Insurance',
        'Vehicle Fitness Certificate',
      ],
    ),
    DefaultCategory(
      id: 'financial_documents',
      name: 'Financial Documents',
      icon: 'account_balance',
      colorValue: 0xFF059669, // Forest Green
      documentTypes: [
        'Bank Documents',
        'Insurance Policies',
        'Tax Documents',
        'Investment Documents',
      ],
    ),
    DefaultCategory(
      id: 'education',
      name: 'Education',
      icon: 'school',
      colorValue: 0xFF7C3AED, // Violet
      documentTypes: [
        'School Certificates',
        'College Certificates',
        'Degree Certificates',
        'Mark Sheets',
      ],
    ),
    DefaultCategory(
      id: 'property',
      name: 'Property',
      icon: 'home_work',
      colorValue: 0xFFD97706, // Amber
      documentTypes: [
        'Property Documents',
        'Rent Agreements',
        'Ownership Documents',
      ],
    ),
    DefaultCategory(
      id: 'medical',
      name: 'Medical',
      icon: 'local_hospital',
      colorValue: 0xFFE11D48, // Rose Crimson
      documentTypes: [
        'Health Insurance',
        'Medical Reports',
        'Vaccination Certificates',
      ],
    ),
    DefaultCategory(
      id: 'other',
      name: 'Other',
      icon: 'folder',
      colorValue: 0xFF64748B, // Slate
      documentTypes: ['Custom Documents'],
    ),
  ];
}
