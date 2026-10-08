class AdminCoachingRequest {
  const AdminCoachingRequest({
    required this.id,
    required this.centerId,
    required this.centerName,
    required this.trainerProfileId,
    required this.trainerName,
    required this.memberProfileId,
    required this.memberName,
    required this.requestedStartAt,
    required this.durationMinutes,
    required this.status,
    required this.fitnessGoal,
    required this.note,
    required this.createdAt,
  });

  final int id;
  final int centerId;
  final String centerName;
  final int trainerProfileId;
  final String trainerName;
  final int memberProfileId;
  final String memberName;
  final DateTime requestedStartAt;
  final int durationMinutes;
  final String status;
  final String? fitnessGoal;
  final String? note;
  final DateTime createdAt;

  factory AdminCoachingRequest.fromJson(Map<String, dynamic> json) {
    return AdminCoachingRequest(
      id: _readInt(json, 'id'),
      centerId: _readInt(json, 'centerId'),
      centerName: _readString(json, 'centerName'),
      trainerProfileId: _readInt(json, 'trainerProfileId'),
      trainerName: _readString(json, 'trainerName'),
      memberProfileId: _readInt(json, 'memberProfileId'),
      memberName: _readString(json, 'memberName'),
      requestedStartAt: DateTime.parse(_readString(json, 'requestedStartAt')),
      durationMinutes: _readInt(json, 'durationMinutes'),
      status: _readString(json, 'status'),
      fitnessGoal: _readOptionalString(json, 'fitnessGoal'),
      note: _readOptionalString(json, 'note'),
      createdAt: DateTime.parse(_readString(json, 'createdAt')),
    );
  }

  String get statusLabel => status[0].toUpperCase() + status.substring(1);

  static int _readInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    throw const FormatException('Invalid or missing integer field.');
  }

  static String _readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) {
      return value;
    }
    throw const FormatException('Invalid or missing string field.');
  }

  static String? _readOptionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw const FormatException('Invalid optional string field.');
  }
}

Map<String, dynamic> readAdminCoachingRequestObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw const FormatException('API returned an unexpected JSON shape.');
}
