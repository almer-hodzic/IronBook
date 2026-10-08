class Trainer {
  const Trainer({
    required this.id,
    required this.centerId,
    required this.centerName,
    required this.centerLocation,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    required this.email,
    this.phoneNumber,
    this.biography,
  });

  final int id;
  final int centerId;
  final String centerName;
  final String centerLocation;
  final String firstName;
  final String lastName;
  final String fullName;
  final String email;
  final String? phoneNumber;
  final String? biography;

  factory Trainer.fromJson(Map<String, dynamic> json) {
    return Trainer(
      id: _readInt(json, 'id'),
      centerId: _readInt(json, 'centerId'),
      centerName: _readString(json, 'centerName'),
      centerLocation: _readString(json, 'centerLocation'),
      firstName: _readString(json, 'firstName'),
      lastName: _readString(json, 'lastName'),
      fullName: _readString(json, 'fullName'),
      email: _readString(json, 'email'),
      phoneNumber: _readOptionalString(json, 'phoneNumber'),
      biography: _readOptionalString(json, 'biography'),
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

  throw FormatException('Invalid string field "$key".');
}
