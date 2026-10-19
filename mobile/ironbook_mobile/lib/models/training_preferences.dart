const trainingPreferenceGoals = [
  'Build Strength',
  'Lose Fat',
  'Get Fitter',
  'Improve Performance',
  'Recovery',
];

const trainingPreferenceInterests = {
  'strength': 'Strength',
  'conditioning': 'Conditioning',
  'recovery': 'Recovery',
  'performance': 'Performance',
  'fat_loss': 'Fat Loss',
};

class TrainingPreferences {
  const TrainingPreferences({
    required this.primaryGoal,
    required this.interests,
  });

  final String primaryGoal;
  final List<String> interests;

  factory TrainingPreferences.fromJson(Map<String, dynamic> json) {
    final goal = json['primaryGoal'];
    final interests = json['interests'];
    if (goal is! String ||
        !trainingPreferenceGoals.contains(goal) ||
        interests is! List ||
        interests.length > 2 ||
        interests.any(
          (value) =>
              value is! String ||
              !trainingPreferenceInterests.containsKey(value),
        ) ||
        interests.toSet().length != interests.length) {
      throw const FormatException('Invalid training preferences response.');
    }
    return TrainingPreferences(
      primaryGoal: goal,
      interests: List<String>.from(interests),
    );
  }

  Map<String, Object?> toJson() => {
    'primaryGoal': primaryGoal,
    'interests': interests,
  };
}
