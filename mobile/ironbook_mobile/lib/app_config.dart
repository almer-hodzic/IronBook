class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static bool get hasApiBaseUrl => apiBaseUrl.trim().isNotEmpty;
}
