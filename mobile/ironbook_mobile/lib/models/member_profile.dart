class MemberProfile {
  const MemberProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phoneNumber,
    required this.isActive,
    required this.createdAt,
  });

  final int id;
  final String firstName;
  final String lastName;
  final String email;
  final String? phoneNumber;
  final bool isActive;
  final DateTime createdAt;

  factory MemberProfile.fromJson(Map<String, dynamic> json) {
    T read<T>(String key) {
      final value = json[key];
      if (value is T) return value;
      throw FormatException('Invalid profile field "$key".');
    }

    return MemberProfile(
      id: read<int>('id'),
      firstName: read<String>('firstName'),
      lastName: read<String>('lastName'),
      email: read<String>('email'),
      phoneNumber: read<String?>('phoneNumber'),
      isActive: read<bool>('isActive'),
      createdAt: DateTime.parse(read<String>('createdAt')),
    );
  }
}
