class AdminTrainerOption {
  const AdminTrainerOption({
    required this.id,
    required this.displayName,
    required this.email,
  });

  final int id;
  final String displayName;
  final String email;

  factory AdminTrainerOption.fromJson(Map<String, dynamic> json) {
    return AdminTrainerOption(
      id: _readInt(json, 'id'),
      displayName: _readString(json, 'displayName'),
      email: _readString(json, 'email'),
    );
  }
}

class AdminGroupTraining {
  const AdminGroupTraining({
    required this.id,
    required this.centerId,
    required this.centerName,
    required this.centerLocation,
    required this.trainerProfileId,
    required this.trainerName,
    required this.name,
    required this.category,
    required this.difficulty,
    required this.startsAt,
    required this.durationMinutes,
    required this.capacity,
    required this.enrolledCount,
    required this.status,
    required this.createdAt,
    this.description,
    this.includes,
    this.whoFor,
  });

  final int id;
  final int centerId;
  final String centerName;
  final String centerLocation;
  final int trainerProfileId;
  final String trainerName;
  final String name;
  final String? description;
  final String category;
  final String difficulty;
  final DateTime startsAt;
  final int durationMinutes;
  final int capacity;
  final int enrolledCount;
  final String status;
  final String? includes;
  final String? whoFor;
  final DateTime createdAt;

  int get availableSpots => capacity - enrolledCount;

  factory AdminGroupTraining.fromJson(Map<String, dynamic> json) {
    return AdminGroupTraining(
      id: _readInt(json, 'id'),
      centerId: _readInt(json, 'centerId'),
      centerName: _readString(json, 'centerName'),
      centerLocation: _readString(json, 'centerLocation'),
      trainerProfileId: _readInt(json, 'trainerProfileId'),
      trainerName: _readString(json, 'trainerName'),
      name: _readString(json, 'name'),
      description: _readOptionalString(json, 'description'),
      category: _readString(json, 'category'),
      difficulty: _readString(json, 'difficulty'),
      startsAt: DateTime.parse(_readString(json, 'startsAt')),
      durationMinutes: _readInt(json, 'durationMinutes'),
      capacity: _readInt(json, 'capacity'),
      enrolledCount: _readInt(json, 'enrolledCount'),
      status: _readString(json, 'status'),
      includes: _readOptionalString(json, 'includes'),
      whoFor: _readOptionalString(json, 'whoFor'),
      createdAt: DateTime.parse(_readString(json, 'createdAt')),
    );
  }
}

class AdminGroupTrainingWriteRequest {
  const AdminGroupTrainingWriteRequest({
    required this.name,
    required this.centerId,
    required this.trainerProfileId,
    required this.category,
    required this.difficulty,
    required this.startsAt,
    required this.durationMinutes,
    required this.capacity,
    required this.status,
    this.description,
    this.includes,
    this.whoFor,
  });

  final String name;
  final String? description;
  final int centerId;
  final int trainerProfileId;
  final String category;
  final String difficulty;
  final DateTime startsAt;
  final int durationMinutes;
  final int capacity;
  final String status;
  final String? includes;
  final String? whoFor;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'centerId': centerId,
      'trainerProfileId': trainerProfileId,
      'category': category,
      'difficulty': difficulty,
      'startsAt': startsAt.toUtc().toIso8601String(),
      'durationMinutes': durationMinutes,
      'capacity': capacity,
      'status': status,
      'includes': includes,
      'whoFor': whoFor,
    };
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

  throw FormatException('Invalid string field "$key".');
}

Map<String, dynamic> readAdminGroupTrainingObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  throw const FormatException('API returned an unexpected JSON shape.');
}
