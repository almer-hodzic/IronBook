class TrainingReport {
  const TrainingReport({
    required this.id,
    required this.trainingRequestId,
    required this.trainerProfileId,
    required this.memberProfileId,
    required this.centerId,
    required this.trainingDate,
    required this.notes,
    required this.createdAt,
    required this.exercises,
  });

  final int id;
  final int trainingRequestId;
  final int trainerProfileId;
  final int memberProfileId;
  final int centerId;
  final DateTime trainingDate;
  final String? notes;
  final DateTime createdAt;
  final List<TrainingReportExercise> exercises;

  factory TrainingReport.fromJson(Map<String, dynamic> json) {
    final exercises = json['exercises'];
    return TrainingReport(
      id: _readInt(json, 'id'),
      trainingRequestId: _readInt(json, 'trainingRequestId'),
      trainerProfileId: _readInt(json, 'trainerProfileId'),
      memberProfileId: _readInt(json, 'memberProfileId'),
      centerId: _readInt(json, 'centerId'),
      trainingDate: DateTime.parse(_readString(json, 'trainingDate')),
      notes: _readOptionalString(json, 'notes'),
      createdAt: DateTime.parse(_readString(json, 'createdAt')),
      exercises: exercises is List
          ? exercises
              .map((item) => TrainingReportExercise.fromJson(_readObject(item)))
              .toList(growable: false)
          : const <TrainingReportExercise>[],
    );
  }
}

class TrainingReportExercise {
  const TrainingReportExercise({
    required this.id,
    required this.exerciseName,
    required this.sets,
    required this.reps,
    required this.weight,
    required this.notes,
  });

  final int id;
  final String exerciseName;
  final int sets;
  final int reps;
  final double? weight;
  final String? notes;

  factory TrainingReportExercise.fromJson(Map<String, dynamic> json) {
    return TrainingReportExercise(
      id: _readInt(json, 'id'),
      exerciseName: _readString(json, 'exerciseName'),
      sets: _readInt(json, 'sets'),
      reps: _readInt(json, 'reps'),
      weight: _readOptionalDouble(json, 'weight'),
      notes: _readOptionalString(json, 'notes'),
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

  throw FormatException('Invalid or missing string field "$key".');
}

double? _readOptionalDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }

  if (value is num) {
    return value.toDouble();
  }

  throw FormatException('Invalid or missing numeric field "$key".');
}

Map<String, dynamic> _readObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  throw const FormatException('API returned an unexpected JSON shape.');
}
