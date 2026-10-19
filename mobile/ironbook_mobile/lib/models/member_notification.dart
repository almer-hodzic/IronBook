class MemberNotification {
  const MemberNotification({
    required this.id,
    required this.trainingRequestId,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.isRead,
  });

  final int id;
  final int trainingRequestId;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;

  factory MemberNotification.fromJson(Map<String, dynamic> json) =>
      MemberNotification(
        id: _read<int>(json, 'id'),
        trainingRequestId: _read<int>(json, 'trainingRequestId'),
        title: _read<String>(json, 'title'),
        message: _read<String>(json, 'message'),
        createdAt: _createdAt(_read<String>(json, 'createdAt')),
        isRead: _read<bool>(json, 'isRead'),
      );

  static int newestFirst(MemberNotification left, MemberNotification right) {
    final dateOrder = right.createdAt.compareTo(left.createdAt);
    return dateOrder == 0 ? right.id.compareTo(left.id) : dateOrder;
  }
}

T _read<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException('Invalid notification field "$key".');
}

DateTime _createdAt(String value) {
  final date = DateTime.parse(value);
  // SQL datetime2 may serialize without a zone; notification event times are UTC.
  return date.isUtc
      ? date
      : DateTime.utc(
          date.year,
          date.month,
          date.day,
          date.hour,
          date.minute,
          date.second,
          date.millisecond,
          date.microsecond,
        );
}
