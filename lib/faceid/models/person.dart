class Person {
  const Person({
    required this.id,
    required this.fullName,
    required this.employeeCode,
    required this.createdAt,
    this.externalId,
    this.position,
    this.spotId,
    this.accountName,
    this.faceCount = 0,
  });

  final int id;
  final int? externalId;
  final String fullName;
  final String employeeCode;
  final String? position;
  final int? spotId;
  final String? accountName;
  final DateTime createdAt;
  final int faceCount;

  factory Person.fromMap(Map<String, Object?> map) {
    return Person(
      id: map['id'] as int,
      externalId: map['external_id'] as int?,
      fullName: (map['full_name'] as String?) ?? '',
      employeeCode: (map['employee_code'] as String?) ?? '',
      position: map['position'] as String?,
      spotId: map['spot_id'] as int?,
      accountName: map['account_name'] as String?,
      createdAt:
          DateTime.tryParse((map['created_at'] as String?) ?? '') ??
          DateTime.now(),
      faceCount: (map['face_count'] as int?) ?? 0,
    );
  }
}
