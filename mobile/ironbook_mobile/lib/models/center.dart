class FitnessCenter {
  const FitnessCenter({
    required this.id,
    required this.name,
    required this.location,
    this.capacity,
    required this.isActive,
    this.amenities,
    this.notes,
  });

  final int id;
  final String name;
  final String location;
  final int? capacity;
  final bool isActive;
  final String? amenities;
  final String? notes;

  factory FitnessCenter.fromJson(Map<String, dynamic> json) {
    return FitnessCenter(
      id: _readInt(json, 'id'),
      name: _readString(json, 'name'),
      location: _readString(json, 'location'),
      capacity: _readOptionalInt(json, 'capacity'),
      isActive: json['isActive'] as bool? ?? true,
      amenities: _readOptionalString(json, 'amenities'),
      notes: _readOptionalString(json, 'notes'),
    );
  }

  static int _readInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }

    throw FormatException('Invalid or missing integer field "$key".');
  }

  static int? _readOptionalInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    throw FormatException('Invalid integer field "$key".');
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
