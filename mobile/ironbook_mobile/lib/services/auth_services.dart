import 'package:http/http.dart' as http;
import 'package:ironbook_auth/ironbook_auth.dart';

import '../app_config.dart';

export 'package:ironbook_auth/ironbook_auth.dart';

/// Composition point for later authentication UI. Uses the existing
/// --dart-define=API_BASE_URL configuration; no platform URL is duplicated.
AuthApiService createAuthApiService({
  http.Client? client,
  SessionStore? sessions,
}) => AuthApiService(
  apiBaseUrl: AppConfig.apiBaseUrl,
  sessions: sessions ?? SessionStore(),
  client: client,
);
