class CheckInValidationResult {
  const CheckInValidationResult({
    required this.checkInId,
    required this.checkedInAt,
    required this.membershipId,
    required this.centerId,
    required this.centerName,
    required this.memberName,
    required this.accessResult,
  });

  final int checkInId;
  final DateTime checkedInAt;
  final int membershipId;
  final int centerId;
  final String centerName;
  final String memberName;
  final String accessResult;

  factory CheckInValidationResult.fromJson(Map<String, dynamic> json) {
    return CheckInValidationResult(
      checkInId: _readInt(json, 'checkInId'),
      checkedInAt: DateTime.parse(_readString(json, 'checkedInAt')),
      membershipId: _readInt(json, 'membershipId'),
      centerId: _readInt(json, 'centerId'),
      centerName: _readString(json, 'centerName'),
      memberName: _readString(json, 'memberName'),
      accessResult: _readString(json, 'accessResult'),
    );
  }

  static int _readInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }

    throw FormatException('Invalid or missing integer field "$key".');
  }

  static String _readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) {
      return value;
    }

    throw FormatException('Invalid or missing string field "$key".');
  }
}
