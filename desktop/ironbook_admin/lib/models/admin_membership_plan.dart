class AdminMembershipPlanCenter {
  const AdminMembershipPlanCenter({
    required this.centerId,
    required this.centerName,
    required this.location,
  });

  final int centerId;
  final String centerName;
  final String location;

  factory AdminMembershipPlanCenter.fromJson(Map<String, dynamic> json) {
    return AdminMembershipPlanCenter(
      centerId: _readInt(json, 'centerId'),
      centerName: _readString(json, 'centerName'),
      location: _readString(json, 'location'),
    );
  }
}

class AdminMembershipPlan {
  const AdminMembershipPlan({
    required this.id,
    required this.name,
    required this.monthlyPrice,
    required this.isActive,
    required this.createdAt,
    required this.centers,
    this.description,
    this.benefits,
  });

  final int id;
  final String name;
  final String? description;
  final double monthlyPrice;
  final String? benefits;
  final bool isActive;
  final DateTime createdAt;
  final List<AdminMembershipPlanCenter> centers;

  factory AdminMembershipPlan.fromJson(Map<String, dynamic> json) {
    final centersJson = json['centers'];
    if (centersJson is! List) {
      throw const FormatException('Invalid or missing centers field.');
    }

    return AdminMembershipPlan(
      id: _readInt(json, 'id'),
      name: _readString(json, 'name'),
      description: _readOptionalString(json, 'description'),
      monthlyPrice: _readDecimal(json, 'monthlyPrice'),
      benefits: _readOptionalString(json, 'benefits'),
      isActive: _readBool(json, 'isActive'),
      createdAt: DateTime.parse(_readString(json, 'createdAt')),
      centers: centersJson
          .map(
            (item) => AdminMembershipPlanCenter.fromJson(_readObject(item)),
          )
          .toList(growable: false),
    );
  }
}

class AdminMembershipPlanWriteRequest {
  const AdminMembershipPlanWriteRequest({
    required this.name,
    required this.monthlyPrice,
    required this.isActive,
    required this.centerIds,
    this.description,
    this.benefits,
  });

  final String name;
  final String? description;
  final double monthlyPrice;
  final String? benefits;
  final bool isActive;
  final List<int> centerIds;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'monthlyPrice': monthlyPrice,
      'benefits': benefits,
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

double _readDecimal(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) {
    return value.toDouble();
  }

  throw FormatException('Invalid or missing decimal field "$key".');
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

Map<String, dynamic> _readObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  throw const FormatException('API returned an unexpected JSON shape.');
}
