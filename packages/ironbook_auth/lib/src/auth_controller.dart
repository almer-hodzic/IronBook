import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_api_service.dart';
import 'auth_session.dart';

/// Coordinates UI transitions; persistence and HTTP remain in the 7A services.
class AuthController extends ChangeNotifier {
  AuthController(this._api);

  final AuthApiService _api;
  AuthSession? _session;
  bool _busy = false;
  bool _restoring = true;
  bool _restoreFailed = false;
  bool _disposed = false;
  String? _error;

  AuthSession? get session => _session;
  bool get isAuthenticated => _session != null;
  bool get isBusy => _busy;
  bool get isRestoring => _restoring;
  bool get restoreFailed => _restoreFailed;
  String? get errorMessage => _error;

  Future<void> restore() async {
    if (_busy) return;
    _busy = true;
    _restoring = true;
    _restoreFailed = false;
    _error = null;
    _notify();
    try {
      _session = await _api.sessions.load();
    } catch (_) {
      _restoreFailed = true;
      _error = 'Unable to restore your session. Please try again.';
    } finally {
      _busy = false;
      _restoring = false;
      _notify();
    }
  }

  Future<bool> login(String username, String password) async {
    if (_busy || _restoring) return false;
    _busy = true;
    _error = null;
    _notify();
    try {
      _session = await _api.login(
        username: username.trim(),
        password: password,
      );
      return true;
    } catch (error) {
      _error = switch (error) {
        AuthApiException(statusCode: 401) => 'Invalid username or password.',
        AuthApiException(statusCode: 400) =>
          'Check your username and password.',
        http.ClientException() ||
        TimeoutException() => 'Cannot reach IronBook. Please try again.',
        FormatException() =>
          'Unable to read the sign-in response. Please try again.',
        _ => 'Unable to sign in. Please try again.',
      };
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> logout() async {
    if (_busy || !isAuthenticated) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      await _api.logout();
      _session = null;
    } catch (_) {
      _error = 'Unable to log out. Please try again.';
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
