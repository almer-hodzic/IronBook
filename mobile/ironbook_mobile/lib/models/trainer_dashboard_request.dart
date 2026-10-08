class TrainerDashboardRequest {
  const TrainerDashboardRequest({
    required this.id,
    required this.memberName,
    required this.centerName,
    required this.requestedStartAt,
    required this.durationMinutes,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final String memberName;
  final String centerName;
  final DateTime requestedStartAt;
  final int durationMinutes;
  final String status;
  final DateTime createdAt;

  factory TrainerDashboardRequest.fromJson(Map<String, dynamic> json) {
    return TrainerDashboardRequest(
      id: _readInt(json, 'id'),
      memberName: _readString(json, 'memberName'),
      centerName: _readString(json, 'centerName'),
      requestedStartAt: DateTime.parse(_readString(json, 'requestedStartAt')),
      durationMinutes: _readInt(json, 'durationMinutes'),
      status: _readString(json, 'status'),
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
