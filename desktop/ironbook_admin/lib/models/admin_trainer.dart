class AdminTrainerCenterAssignment {
  const AdminTrainerCenterAssignment({
    required this.centerId,
    required this.centerName,
    required this.location,
  });

  final int centerId;
  final String centerName;
  final String location;

  factory AdminTrainerCenterAssignment.fromJson(Map<String, dynamic> json) {
    return AdminTrainerCenterAssignment(
      centerId: _readInt(json, 'centerId'),
      centerName: _readString(json, 'centerName'),
      location: _readString(json, 'location'),
    );
  }
}

class AdminTrainer {
  const AdminTrainer({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.isActive,
    required this.createdAt,
    required this.centers,
    this.phoneNumber,
    this.biography,
  });

  final int id;
  final String firstName;
  final String lastName;
  final String email;
  final String? phoneNumber;
  final String? biography;
  final bool isActive;
  final DateTime createdAt;
  final List<AdminTrainerCenterAssignment> centers;

  String get displayName => '$firstName $lastName';

  factory AdminTrainer.fromJson(Map<String, dynamic> json) {
    final centersJson = json['centers'];
    if (centersJson is! List) {
      throw const FormatException('Invalid or missing centers field.');
    }

    return AdminTrainer(
      id: _readInt(json, 'id'),
      firstName: _readString(json, 'firstName'),
      lastName: _readString(json, 'lastName'),
      email: _readString(json, 'email'),
      phoneNumber: _readOptionalString(json, 'phoneNumber'),
      biography: _readOptionalString(json, 'biography'),
      isActive: _readBool(json, 'isActive'),
      createdAt: DateTime.parse(_readString(json, 'createdAt')),
      centers: centersJson
          .map(
            (item) => AdminTrainerCenterAssignment.fromJson(
              readAdminTrainerObject(item),
            ),
          )
          .toList(growable: false),
    );
  }
}

class AdminTrainerWriteRequest {
  const AdminTrainerWriteRequest({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.isActive,
    required this.centerIds,
    this.phoneNumber,
    this.biography,
  });

  final String firstName;
  final String lastName;
  final String email;
  final String? phoneNumber;
  final String? biography;
  final bool isActive;
  final List<int> centerIds;

  Map<String, dynamic> toJson() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phoneNumber': phoneNumber,
      'biography': biography,
      'isActive': isActive,
      'centerIds': centerIds,
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

Map<String, dynamic> readAdminTrainerObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  throw const FormatException('API returned an unexpected JSON shape.');
}
