import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_session.dart';

abstract interface class SessionStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

/// Android uses the plugin's encrypted storage defaults; Windows uses its
/// platform credential protection. Only one serialized session is persisted.
class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'ironbook.auth.session';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Later feature clients can depend on this without knowing storage details.
abstract interface class AccessTokenProvider {
  Future<String?> getAccessToken();
}

class SessionStore implements AccessTokenProvider {
  SessionStore({SessionStorage? storage, DateTime Function()? now})
    : _storage = storage ?? SecureSessionStorage(),
      _now = now ?? DateTime.now;

  final SessionStorage _storage;
  final DateTime Function() _now;

  Future<void> save(AuthSession session) async {
    if (!session.expiresAt.isAfter(_now())) {
      throw const FormatException('Authentication session has expired.');
    }
    await _storage.write(jsonEncode(session.toJson()));
  }

  Future<AuthSession?> load() async {
    final value = await _storage.read();
    if (value == null) return null;
    try {
      final json = jsonDecode(value);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Invalid stored session.');
      }
      final session = AuthSession.fromJson(json);
      if (session.expiresAt.isAfter(_now())) return session;
    } on FormatException {
      // Malformed or obsolete stored credentials must not remain usable.
    }
    await clear();
    return null;
  }

  @override
  Future<String?> getAccessToken() async => (await load())?.accessToken;
  Future<String?> getRole() async => (await load())?.role;
  Future<bool> get isAuthenticated async => await load() != null;
  Future<void> clear() => _storage.clear();
}
