class MemberRecommendations {
  const MemberRecommendations({
    required this.centerId,
    required this.centerName,
    required this.isPersonalized,
    required this.trainers,
    required this.groupTrainings,
  });

  final int centerId;
  final String centerName;
  final bool isPersonalized;
  final List<TrainerRecommendation> trainers;
  final List<GroupTrainingRecommendation> groupTrainings;

  factory MemberRecommendations.fromJson(Map<String, dynamic> json) =>
      MemberRecommendations(
        centerId: _read<int>(json, 'centerId'),
        centerName: _read<String>(json, 'centerName'),
        isPersonalized: _read<bool>(json, 'isPersonalized'),
        trainers: _objects(
          json,
          'trainers',
        ).map(TrainerRecommendation.fromJson).toList(),
        groupTrainings: _objects(
          json,
          'groupTrainings',
        ).map(GroupTrainingRecommendation.fromJson).toList(),
      );
}

class TrainerRecommendation {
  const TrainerRecommendation({
    required this.id,
    required this.name,
    required this.categories,
    required this.similarity,
    required this.approvedCoachingRequestCount,
    this.reasons = const [],
  });

  final int id;
  final String name;
  final List<String> categories;
  final double? similarity;
  final int approvedCoachingRequestCount;
  final List<String> reasons;

  factory TrainerRecommendation.fromJson(Map<String, dynamic> json) {
    final categories = _read<List>(json, 'categories');
    if (categories.any((category) => category is! String)) {
      throw const FormatException('Invalid recommendation categories.');
    }
    return TrainerRecommendation(
      id: _read<int>(json, 'id'),
      name: _read<String>(json, 'name'),
      categories: List<String>.from(categories),
      similarity: _number(json, 'similarity'),
      approvedCoachingRequestCount: _read<int>(
        json,
        'approvedCoachingRequestCount',
      ),
      reasons: _reasons(json),
    );
  }
}

class GroupTrainingRecommendation {
  const GroupTrainingRecommendation({
    required this.id,
    required this.name,
    required this.trainerName,
    required this.category,
    required this.startsAt,
    required this.capacity,
    required this.enrollmentCount,
    required this.fillRatio,
    required this.similarity,
    this.reasons = const [],
  });

  final int id;
  final String name;
  final String trainerName;
  final String category;
  final DateTime startsAt;
  final int capacity;
  final int enrollmentCount;
  final double fillRatio;
  final double? similarity;
  final List<String> reasons;

  factory GroupTrainingRecommendation.fromJson(Map<String, dynamic> json) =>
      GroupTrainingRecommendation(
        id: _read<int>(json, 'id'),
        name: _read<String>(json, 'name'),
        trainerName: _read<String>(json, 'trainerName'),
        category: _read<String>(json, 'category'),
        startsAt: DateTime.parse(_read<String>(json, 'startsAt')),
        capacity: _read<int>(json, 'capacity'),
        enrollmentCount: _read<int>(json, 'enrollmentCount'),
        fillRatio: _read<num>(json, 'fillRatio').toDouble(),
        similarity: _number(json, 'similarity'),
        reasons: _reasons(json),
      );
}

List<String> _reasons(Map<String, dynamic> json) {
  final reasons = json['reasons'];
  if (reasons == null) return const [];
  if (reasons is! List || reasons.any((reason) => reason is! String)) {
    throw const FormatException('Invalid recommendation reasons.');
  }
  return List<String>.from(reasons);
}

T _read<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException('Invalid recommendation field "$key".');
}

double? _number(Map<String, dynamic> json, String key) {
  final value = _read<num?>(json, key)?.toDouble();
  if (value != null && !value.isFinite) {
    throw FormatException('Invalid recommendation field "$key".');
  }
  return value;
}

Iterable<Map<String, dynamic>> _objects(
  Map<String, dynamic> json,
  String key,
) => _read<List>(json, key).map((item) {
  if (item is Map<String, dynamic>) return item;
  throw const FormatException('Invalid recommendation item.');
});
