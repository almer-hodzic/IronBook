class AdminCenter {
  const AdminCenter({
    required this.id,
    required this.name,
    required this.location,
    required this.capacity,
    required this.isActive,
    required this.createdAt,
    this.amenities,
    this.notes,
  });

  final int id;
  final String name;
  final String location;
  final int capacity;
  final bool isActive;
  final String? amenities;
  final String? notes;
  final DateTime createdAt;

  factory AdminCenter.fromJson(Map<String, dynamic> json) {
    return AdminCenter(
      id: _readInt(json, 'id'),
      name: _readString(json, 'name'),
      location: _readString(json, 'location'),
      capacity: _readInt(json, 'capacity'),
      isActive: _readBool(json, 'isActive'),
      amenities: _readOptionalString(json, 'amenities'),
      notes: _readOptionalString(json, 'notes'),
      createdAt: DateTime.parse(_readString(json, 'createdAt')),
    );
  }

  static int _readInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }

    throw FormatException('Invalid or missing integer field "$key".');
  }

  static bool _readBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) {
      return value;
    }

    throw FormatException('Invalid or missing boolean field "$key".');
  }

  static String _readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) {
      return value;
    }

    throw FormatException('Invalid or missing string field "$key".');
  }

  static String? _readOptionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }

    if (value is String) {
      return value;
    }

    throw FormatException('Invalid string field "$key".');
  }
}

class AdminCenterWriteRequest {
  const AdminCenterWriteRequest({
    required this.name,
    required this.location,
    required this.capacity,
    required this.isActive,
    this.amenities,
    this.notes,
  });

  final String name;
  final String location;
  final int capacity;
  final bool isActive;
  final String? amenities;
  final String? notes;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'location': location,
      'capacity': capacity,
      'isActive': isActive,
      'amenities': amenities,
      'notes': notes,
    };
  }
}
