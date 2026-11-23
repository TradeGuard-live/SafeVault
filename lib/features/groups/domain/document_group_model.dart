class DocumentGroupModel {
  final String id;
  final String name;
  final String? description;
  final String icon;
  final int colorValue;
  final int documentCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DocumentGroupModel({
    required this.id,
    required this.name,
    this.description,
    required this.icon,
    required this.colorValue,
    this.documentCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  DocumentGroupModel copyWith({
    String? id,
    String? name,
    String? description,
    String? icon,
    int? colorValue,
    int? documentCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DocumentGroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      colorValue: colorValue ?? this.colorValue,
      documentCount: documentCount ?? this.documentCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'color_value': colorValue,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory DocumentGroupModel.fromMap(Map<String, dynamic> map, {int documentCount = 0}) {
    return DocumentGroupModel(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      icon: map['icon'] as String,
      colorValue: map['color_value'] as int,
      documentCount: (map['doc_count'] as int?) ?? documentCount,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
