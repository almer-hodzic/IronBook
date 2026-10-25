import 'package:http/http.dart' as http;
import 'package:ironbook_auth/ironbook_auth.dart';

class AuthenticationRequiredException implements Exception {
  const AuthenticationRequiredException();

  @override
  String toString() => 'Authentication is required.';
}

/// Opt-in transport for authenticated feature calls. The provider handles
/// session expiry; this client never reads storage or handles login/logout.
class BearerHttpClient extends http.BaseClient {
  BearerHttpClient({
    required http.Client client,
    required AccessTokenProvider accessTokenProvider,
  }) : _inner = client,
       _tokens = accessTokenProvider;

  final http.Client _inner;
  final AccessTokenProvider _tokens;
  // Bearer credential syntax, not JWT claim/signature validation.
  static final _tokenSyntax = RegExp(r'^[A-Za-z0-9\-._~+/]+=*$');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final String? token;
    try {
      token = await _tokens.getAccessToken();
    } catch (_) {
      throw const AuthenticationRequiredException();
    }
    if (token == null ||
        token.isEmpty ||
        _tokenSyntax.firstMatch(token)?.end != token.length) {
      throw const AuthenticationRequiredException();
    }
    request.headers['Authorization'] = 'Bearer $token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
