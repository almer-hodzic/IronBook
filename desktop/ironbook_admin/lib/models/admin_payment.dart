class AdminPayment {
  const AdminPayment({
    required this.id,
    required this.memberProfileId,
    required this.memberName,
    required this.memberEmail,
    required this.membershipId,
    required this.membershipPlanName,
    required this.centerId,
    required this.centerName,
    required this.amount,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.membershipStatus,
    required this.createdAt,
    required this.membershipStartDate,
    required this.membershipEndDate,
  });

  final int id;
  final int memberProfileId;
  final String memberName;
  final String memberEmail;
  final int membershipId;
  final String membershipPlanName;
  final int centerId;
  final String centerName;
  final num amount;
  final String paymentMethod;
  final String paymentStatus;
  final String membershipStatus;
  final DateTime createdAt;
  final DateTime membershipStartDate;
  final DateTime membershipEndDate;

  bool get canConfirm =>
      paymentMethod == 'Reception' &&
      paymentStatus == 'PendingReception' &&
      membershipStatus == 'Pending';

  factory AdminPayment.fromJson(Map<String, dynamic> json) {
    T read<T>(String key) {
      if (json[key] is T) return json[key] as T;
      throw FormatException('Invalid payment field "$key".');
    }

    return AdminPayment(
      id: read<int>('id'),
      memberProfileId: read<int>('memberProfileId'),
      memberName: read<String>('memberName'),
      memberEmail: read<String>('memberEmail'),
      membershipId: read<int>('membershipId'),
      membershipPlanName: read<String>('membershipPlanName'),
      centerId: read<int>('centerId'),
      centerName: read<String>('centerName'),
      amount: read<num>('amount'),
      paymentMethod: read<String>('paymentMethod'),
      paymentStatus: read<String>('paymentStatus'),
      membershipStatus: read<String>('membershipStatus'),
      createdAt: DateTime.parse(read<String>('createdAt')),
      membershipStartDate: DateTime.parse(read<String>('membershipStartDate')),
      membershipEndDate: DateTime.parse(read<String>('membershipEndDate')),
    );
  }
}

class AdminPaymentFilter {
  const AdminPaymentFilter({
    this.search = '',
    this.status,
    this.paymentMethod,
    this.centerId,
  });
  final String search;
  final String? status;
  final String? paymentMethod;
  final int? centerId;
  Map<String, String> get query => {
    if (search.trim().isNotEmpty) 'search': search.trim(),
    'status': ?status,
    'paymentMethod': ?paymentMethod,
    if (centerId != null) 'centerId': centerId.toString(),
  };
}
