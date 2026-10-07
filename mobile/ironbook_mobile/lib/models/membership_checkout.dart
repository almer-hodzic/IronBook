enum MembershipCheckoutPaymentMethod {
  card('Card', 'Card Payment'),
  reception('Reception', 'Pay at Reception');

  const MembershipCheckoutPaymentMethod(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

class MembershipCheckoutResult {
  const MembershipCheckoutResult({
    required this.membershipId,
    required this.paymentId,
    required this.centerId,
    required this.centerName,
    required this.membershipPlanId,
    required this.planName,
    required this.amount,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.membershipStatus,
    required this.startDate,
    required this.endDate,
  });

  final int membershipId;
  final int paymentId;
  final int centerId;
  final String centerName;
  final int membershipPlanId;
  final String planName;
  final double amount;
  final String paymentMethod;
  final String paymentStatus;
  final String membershipStatus;
  final DateTime startDate;
  final DateTime endDate;

  factory MembershipCheckoutResult.fromJson(Map<String, dynamic> json) {
    return MembershipCheckoutResult(
      membershipId: _readInt(json, 'membershipId'),
      paymentId: _readInt(json, 'paymentId'),
      centerId: _readInt(json, 'centerId'),
      centerName: _readString(json, 'centerName'),
      membershipPlanId: _readInt(json, 'membershipPlanId'),
      planName: _readString(json, 'planName'),
      amount: _readDecimal(json, 'amount'),
      paymentMethod: _readString(json, 'paymentMethod'),
      paymentStatus: _readString(json, 'paymentStatus'),
      membershipStatus: _readString(json, 'membershipStatus'),
      startDate: _readDate(json, 'startDate'),
      endDate: _readDate(json, 'endDate'),
    );
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

  static DateTime _readDate(Map<String, dynamic> json, String key) {
    final value = _readString(json, key);
    return DateTime.parse(value);
  }
}
