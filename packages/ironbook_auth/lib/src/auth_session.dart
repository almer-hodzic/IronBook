/// Only the fields returned by the login endpoint. Never contains passwords.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.expiresAt,
    required this.accountId,
    required this.username,
    required this.role,
  });

  final String accessToken;
  final DateTime expiresAt;
  final int accountId;
  final String username;
  final String role;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final token = json['accessToken'];
    final expiry = json['expiresAt'];
    final id = json['accountId'];
    final username = json['username'];
    final role = json['role'];
    final parsedExpiry = expiry is String ? DateTime.tryParse(expiry) : null;
    if (token is! String ||
        token.trim().isEmpty ||
        parsedExpiry == null ||
        id is! int ||
        id <= 0 ||
        username is! String ||
        username.trim().isEmpty ||
        role is! String ||
        role.trim().isEmpty) {
      throw const FormatException('Invalid authentication response.');
    }
    // Preserve unknown nonempty roles so the gate can reject app entry while
    // still allowing the user to explicitly sign out of that session.
    return AuthSession(
      accessToken: token,
      expiresAt: parsedExpiry.toUtc(),
      accountId: id,
      username: username,
      role: role,
    );
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'accountId': accountId,
    'username': username,
    'role': role,
  };
}
