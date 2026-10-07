class MembershipPlan {
  const MembershipPlan({
    required this.id,
    required this.name,
    required this.monthlyPrice,
    this.description,
    this.benefits,
  });

  final int id;
  final String name;
  final String? description;
  final double monthlyPrice;
  final String? benefits;

  factory MembershipPlan.fromJson(Map<String, dynamic> json) {
    return MembershipPlan(
      id: _readInt(json, 'id'),
      name: _readString(json, 'name'),
      description: _readOptionalString(json, 'description'),
      monthlyPrice: _readDecimal(json, 'monthlyPrice'),
      benefits: _readOptionalString(json, 'benefits'),
    );
  }

  List<String> get benefitItems {
    final value = benefits;
    if (value == null || value.trim().isEmpty) {
      return const <String>[];
    }

    return value
        .split(RegExp(r'[\n,;]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static int _readInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }

    throw FormatException('Invalid or missing integer field "$key".');
  }

  static double _readDecimal(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is num) {
      return value.toDouble();
    }

    throw FormatException('Invalid or missing decimal field "$key".');
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
