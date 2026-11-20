class ActivityModel {
  final String id;
  final String? documentId;
  final String documentName;
  final String activityType;
  final String? details;
  final DateTime timestamp;

  const ActivityModel({
    required this.id,
    this.documentId,
    required this.documentName,
    required this.activityType,
    this.details,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'document_id': documentId,
      'document_name': documentName,
      'activity_type': activityType,
      'details': details,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ActivityModel.fromMap(Map<String, dynamic> map) {
    return ActivityModel(
      id: map['id'] as String,
      documentId: map['document_id'] as String?,
      documentName: map['document_name'] as String,
      activityType: map['activity_type'] as String,
      details: map['details'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

