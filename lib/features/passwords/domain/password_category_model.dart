class PasswordCategoryModel {
  final String id;
  final String name;
  final String icon;
  final int colorValue;
  final bool isDefault;
  final DateTime createdAt;

  const PasswordCategoryModel({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorValue,
    this.isDefault = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'color_value': colorValue,
      'is_default': isDefault ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PasswordCategoryModel.fromMap(Map<String, dynamic> map) {
    return PasswordCategoryModel(
      id: map['id'] as String,
      name: map['name'] as String,
      icon: map['icon'] as String,
      colorValue: map['color_value'] as int,
      isDefault: (map['is_default'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

