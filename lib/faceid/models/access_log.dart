class AccessLog {
  const AccessLog({
    required this.id,
    required this.personId,
    required this.personName,
    required this.employeeCode,
    required this.action,
    required this.confidence,
    required this.timestamp,
    this.photoPath,
  });

  final int id;
  final int? personId;
  final String personName;
  final String employeeCode;
  final String action;
  final double confidence;
  final DateTime timestamp;
  final String? photoPath;

  bool get isEntry => action == 'entry';
  String get actionLabel => isEntry ? 'KIRDI' : 'CHIQDI';

  factory AccessLog.fromMap(Map<String, Object?> map) {
    return AccessLog(
      id: map['id'] as int,
      personId: map['person_id'] as int?,
      personName: (map['person_name'] as String?) ?? "Noma'lum",
      employeeCode: (map['employee_code'] as String?) ?? '',
      action: (map['action'] as String?) ?? 'entry',
      confidence: ((map['confidence'] as num?) ?? 0).toDouble(),
      timestamp:
          DateTime.tryParse((map['timestamp'] as String?) ?? '') ??
          DateTime.now(),
      photoPath: map['photo_path'] as String?,
    );
  }
}
