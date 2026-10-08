class TrainingAvailabilityDay {
  const TrainingAvailabilityDay({
    required this.date,
    required this.dayLabel,
    required this.dateLabel,
    required this.monthLabel,
    required this.slots,
  });

  final String date;
  final String dayLabel;
  final String dateLabel;
  final String monthLabel;
  final List<TrainingAvailabilitySlot> slots;

  factory TrainingAvailabilityDay.fromJson(Map<String, dynamic> json) {
    final slotsValue = json['slots'];
    if (slotsValue is! List) {
      throw const FormatException('Invalid or missing slots field.');
    }

    return TrainingAvailabilityDay(
      date: _readString(json, 'date'),
      dayLabel: _readString(json, 'dayLabel'),
      dateLabel: _readString(json, 'dateLabel'),
      monthLabel: _readString(json, 'monthLabel'),
      slots: slotsValue
          .map((item) => TrainingAvailabilitySlot.fromJson(_readObject(item)))
          .toList(growable: false),
    );
  }
}

class TrainingAvailabilitySlot {
  const TrainingAvailabilitySlot({
    required this.startsAt,
    required this.date,
    required this.time,
    required this.period,
    required this.isAvailable,
    required this.status,
  });

  final DateTime startsAt;
  final String date;
  final String time;
  final String period;
  final bool isAvailable;
  final String status;

  factory TrainingAvailabilitySlot.fromJson(Map<String, dynamic> json) {
    return TrainingAvailabilitySlot(
      startsAt: DateTime.parse(_readString(json, 'startsAt')),
      date: _readString(json, 'date'),
      time: _readString(json, 'time'),
      period: _readString(json, 'period'),
      isAvailable: _readBool(json, 'isAvailable'),
      status: _readString(json, 'status'),
    );
  }
}

class TrainingRequestResult {
  const TrainingRequestResult({
    required this.id,
    required this.centerId,
    required this.centerName,
    required this.trainerProfileId,
    required this.trainerName,
    required this.memberProfileId,
    required this.requestedStartAt,
    required this.durationMinutes,
    required this.status,
    required this.createdAt,
    this.fitnessGoal,
    this.note,
  });

  final int id;
  final int centerId;
  final String centerName;
  final int trainerProfileId;
  final String trainerName;
  final int memberProfileId;
  final DateTime requestedStartAt;
  final int durationMinutes;
  final String status;
  final String? fitnessGoal;
  final String? note;
  final DateTime createdAt;

  factory TrainingRequestResult.fromJson(Map<String, dynamic> json) {
    return TrainingRequestResult(
      id: _readInt(json, 'id'),
      centerId: _readInt(json, 'centerId'),
      centerName: _readString(json, 'centerName'),
      trainerProfileId: _readInt(json, 'trainerProfileId'),
      trainerName: _readString(json, 'trainerName'),
      memberProfileId: _readInt(json, 'memberProfileId'),
      requestedStartAt: DateTime.parse(_readString(json, 'requestedStartAt')),
      durationMinutes: _readInt(json, 'durationMinutes'),
      status: _readString(json, 'status'),
      fitnessGoal: _readOptionalString(json, 'fitnessGoal'),
      note: _readOptionalString(json, 'note'),
      createdAt: DateTime.parse(_readString(json, 'createdAt')),
    );
  }
}

Map<String, dynamic> _readObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  throw const FormatException('API returned an unexpected JSON shape.');
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
