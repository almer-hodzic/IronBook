class MyMembership {
  const MyMembership({
    required this.membershipId,
    required this.membershipPlanId,
    required this.planName,
    required this.centerId,
    required this.centerName,
    required this.startDate,
    required this.endDate,
    required this.membershipStatus,
    required this.hasQrAccess,
    required this.accessMessage,
    this.paymentAmount,
    this.paymentMethod,
    this.paymentStatus,
    this.qrAccessToken,
  });

  final int membershipId;
  final int membershipPlanId;
  final String planName;
  final int centerId;
  final String centerName;
  final DateTime startDate;
  final DateTime endDate;
  final String membershipStatus;
  final double? paymentAmount;
  final String? paymentMethod;
  final String? paymentStatus;
  final bool hasQrAccess;
  final String? qrAccessToken;
  final String accessMessage;

  factory MyMembership.fromJson(Map<String, dynamic> json) {
    return MyMembership(
      membershipId: _readInt(json, 'membershipId'),
      membershipPlanId: _readInt(json, 'membershipPlanId'),
      planName: _readString(json, 'planName'),
      centerId: _readInt(json, 'centerId'),
      centerName: _readString(json, 'centerName'),
      startDate: _readDate(json, 'startDate'),
      endDate: _readDate(json, 'endDate'),
      membershipStatus: _readString(json, 'membershipStatus'),
      paymentAmount: _readOptionalDecimal(json, 'paymentAmount'),
      paymentMethod: _readOptionalString(json, 'paymentMethod'),
      paymentStatus: _readOptionalString(json, 'paymentStatus'),
      hasQrAccess: _readBool(json, 'hasQrAccess'),
      qrAccessToken: _readOptionalString(json, 'qrAccessToken'),
      accessMessage: _readString(json, 'accessMessage'),
    );
  }

  bool get isActive => membershipStatus.toLowerCase() == 'active';

  bool get isPending => membershipStatus.toLowerCase() == 'pending';

  static int _readInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }

    throw FormatException('Invalid or missing integer field "$key".');
  }

  static double? _readOptionalDecimal(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    throw FormatException('Invalid decimal field "$key".');
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

  static DateTime _readDate(Map<String, dynamic> json, String key) {
    return DateTime.parse(_readString(json, key));
  }
}

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
      checkInId: MyMembership._readInt(json, 'checkInId'),
      checkedInAt: MyMembership._readDate(json, 'checkedInAt'),
      membershipId: MyMembership._readInt(json, 'membershipId'),
      centerId: MyMembership._readInt(json, 'centerId'),
      centerName: MyMembership._readString(json, 'centerName'),
      memberName: MyMembership._readString(json, 'memberName'),
      accessResult: MyMembership._readString(json, 'accessResult'),
    );
  }
}
