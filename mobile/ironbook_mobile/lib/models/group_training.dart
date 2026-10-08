class GroupTraining {
  const GroupTraining({
    required this.id,
    required this.centerId,
    required this.centerName,
    required this.name,
    required this.category,
    required this.difficulty,
    required this.startsAt,
    required this.durationMinutes,
    required this.capacity,
    required this.enrolledCount,
    required this.availableSpots,
    required this.status,
    required this.trainerName,
    required this.isEnrolled,
    this.description,
    this.includes,
    this.whoFor,
  });

  final int id;
  final int centerId;
  final String centerName;
  final String name;
  final String? description;
  final String category;
  final String difficulty;
  final DateTime startsAt;
  final int durationMinutes;
  final int capacity;
  final int enrolledCount;
  final int availableSpots;
  final String status;
  final String trainerName;
  final String? includes;
  final String? whoFor;
  final bool isEnrolled;

  factory GroupTraining.fromJson(Map<String, dynamic> json) {
    return GroupTraining(
      id: _readInt(json, 'id'),
      centerId: _readInt(json, 'centerId'),
      centerName: _readString(json, 'centerName'),
      name: _readString(json, 'name'),
      description: _readOptionalString(json, 'description'),
      category: _readString(json, 'category'),
      difficulty: _readString(json, 'difficulty'),
      startsAt: DateTime.parse(_readString(json, 'startsAt')),
      durationMinutes: _readInt(json, 'durationMinutes'),
      capacity: _readInt(json, 'capacity'),
      enrolledCount: _readInt(json, 'enrolledCount'),
      availableSpots: _readInt(json, 'availableSpots'),
      status: _readString(json, 'status'),
      trainerName: _readString(json, 'trainerName'),
      includes: _readOptionalString(json, 'includes'),
      whoFor: _readOptionalString(json, 'whoFor'),
      isEnrolled: _readBool(json, 'isEnrolled'),
    );
  }
}

class GroupTrainingEnrollment {
  const GroupTrainingEnrollment({
    required this.id,
    required this.groupTrainingId,
    required this.memberProfileId,
    required this.status,
    required this.enrolledAt,
  });

  final int id;
  final int groupTrainingId;
  final int memberProfileId;
  final String status;
  final DateTime enrolledAt;

  factory GroupTrainingEnrollment.fromJson(Map<String, dynamic> json) {
    return GroupTrainingEnrollment(
      id: _readInt(json, 'id'),
      groupTrainingId: _readInt(json, 'groupTrainingId'),
      memberProfileId: _readInt(json, 'memberProfileId'),
      status: _readString(json, 'status'),
      enrolledAt: DateTime.parse(_readString(json, 'enrolledAt')),
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

bool _readBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }

  throw FormatException('Invalid or missing boolean field "$key".');
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

  throw FormatException('Invalid string field "$key".');
}
