class TrainerClientDetails {
  const TrainerClientDetails({
    required this.id,
    required this.memberName,
    required this.centerName,
    required this.requestedStartAt,
    required this.durationMinutes,
    required this.fitnessGoal,
    required this.note,
    required this.status,
    required this.hasTrainingReport,
    required this.createdAt,
  });

  final int id;
  final String memberName;
  final String centerName;
  final DateTime requestedStartAt;
  final int durationMinutes;
  final String? fitnessGoal;
  final String? note;
  final String status;
  final bool hasTrainingReport;
  final DateTime createdAt;

  factory TrainerClientDetails.fromJson(Map<String, dynamic> json) {
    return TrainerClientDetails(
      id: _readInt(json, 'id'),
      memberName: _readString(json, 'memberName'),
      centerName: _readString(json, 'centerName'),
      requestedStartAt: DateTime.parse(_readString(json, 'requestedStartAt')),
      durationMinutes: _readInt(json, 'durationMinutes'),
      fitnessGoal: _readOptionalString(json, 'fitnessGoal'),
      note: _readOptionalString(json, 'note'),
      status: _readString(json, 'status'),
      hasTrainingReport: _readBool(json, 'hasTrainingReport'),
      createdAt: DateTime.parse(_readString(json, 'createdAt')),
    );
  }
}

int _readInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }

  throw FormatException('Invalid or missing integer field "$key".');
}

String _readString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) {
    return value;
  }

  throw FormatException('Invalid or missing string field "$key".');
}

String? _readOptionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }

  if (value is String) {
    return value;
  }

  throw FormatException('Invalid or missing string field "$key".');
}

bool _readBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }

  throw FormatException('Invalid or missing boolean field "$key".');
}
