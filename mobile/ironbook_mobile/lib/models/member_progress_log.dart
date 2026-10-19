class MemberProgressLog {
  const MemberProgressLog({
    required this.id,
    required this.trainingDate,
    required this.trainerName,
    required this.centerName,
    required this.reportNotes,
    required this.exercises,
  });

  final int id;
  final DateTime trainingDate;
  final String trainerName;
  final String centerName;
  final String? reportNotes;
  final List<MemberProgressLogExercise> exercises;

  factory MemberProgressLog.fromJson(Map<String, dynamic> json) {
    final exercises = json['exercises'];
    if (exercises is! List) {
      throw const FormatException('Invalid progress log exercises.');
    }
    return MemberProgressLog(
      id: _read<int>(json, 'id'),
      trainingDate: DateTime.parse(_read<String>(json, 'trainingDate')),
      trainerName: _read<String>(json, 'trainerName'),
      centerName: _read<String>(json, 'centerName'),
      reportNotes: _read<String?>(json, 'reportNotes'),
      exercises: exercises
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('Invalid progress log exercise.');
            }
            return MemberProgressLogExercise.fromJson(item);
          })
          .toList(growable: false),
    );
  }
}

class MemberProgressLogExercise {
  const MemberProgressLogExercise({
    required this.exerciseName,
    required this.sets,
    required this.reps,
    required this.weight,
    required this.notes,
  });

  final String exerciseName;
  final int sets;
  final int reps;
  final double? weight;
  final String? notes;

  factory MemberProgressLogExercise.fromJson(Map<String, dynamic> json) {
    return MemberProgressLogExercise(
      exerciseName: _read<String>(json, 'exerciseName'),
      sets: _read<int>(json, 'sets'),
      reps: _read<int>(json, 'reps'),
      weight: _read<num?>(json, 'weight')?.toDouble(),
      notes: _read<String?>(json, 'notes'),
    );
  }
}

T _read<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException('Invalid progress log field "$key".');
}
