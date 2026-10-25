import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_session.dart';
import 'session_store.dart';

/// Preserves HTTP status and validation data for callers to present later.
/// Does not retain request bodies, passwords, tokens, or response bodies.
class AuthApiException implements Exception {
  const AuthApiException(this.statusCode, {this.errors = const {}});
  final int statusCode;
  final Map<String, List<String>> errors;

  @override
  String toString() => 'Authentication request failed (HTTP $statusCode).';
}

class AuthApiService {
  AuthApiService({
    required String apiBaseUrl,
    required this.sessions,
    http.Client? client,
  }) : _baseUrl = apiBaseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final SessionStore sessions;
  final String _baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final response = await _post(
      '/api/auth/login',
      body: {'username': username, 'password': password},
    );
    if (response.statusCode != 200) throw _failure(response);
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid authentication response.');
    }
    final session = AuthSession.fromJson(data);
    await sessions.save(session);
    return session;
  }

  Future<void> logout() async {
    final token = await sessions.getAccessToken();
    if (token == null) {
      await sessions.clear();
      return;
    }
    final response = await _post('/api/auth/logout', token: token);
    if (response.statusCode != 204 && response.statusCode != 401) {
      throw _failure(response);
    }
    await sessions.clear();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final token = await sessions.getAccessToken();
    if (token == null) throw const AuthApiException(401);
    final response = await _post(
      '/api/auth/change-password',
      token: token,
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    if (response.statusCode == 401) await sessions.clear();
    if (response.statusCode != 204) throw _failure(response);
    await sessions.clear();
  }

  Future<http.Response> _post(
    String path, {
    String? token,
    Map<String, String>? body,
  }) {
    final base = Uri.tryParse(_baseUrl);
    if (base == null ||
        !base.hasAuthority ||
        !const ['http', 'https'].contains(base.scheme) ||
        base.hasQuery ||
        base.hasFragment ||
        base.userInfo.isNotEmpty) {
      throw StateError('A valid API_BASE_URL is required.');
    }
    return _client
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: {
            'Accept': 'application/json',
            if (body != null) 'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
  }

  AuthApiException _failure(http.Response response) {
    final errors = <String, List<String>>{};
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic> && data['errors'] is Map) {
        for (final entry in (data['errors'] as Map).entries) {
          if (entry.key is String &&
              entry.value is List &&
              (entry.value as List).every((value) => value is String)) {
            errors[entry.key as String] = List<String>.from(entry.value);
          }
        }
      }
    } on FormatException {
      // Status remains available for non-JSON responses too.
    }
    return AuthApiException(response.statusCode, errors: errors);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
