import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ironbook_auth/ironbook_auth.dart';

import 'bearer_http_client.dart';

import '../app_config.dart';
import '../models/check_in_validation.dart';

class AdminCheckInApiException implements Exception {
  const AdminCheckInApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AdminCheckInApiService {
  AdminCheckInApiService({
    http.Client? client,
    AccessTokenProvider? accessTokenProvider,
  }) : _client = BearerHttpClient(
         client: client ?? http.Client(),
         accessTokenProvider: accessTokenProvider ?? SessionStore(),
       );

  final http.Client _client;

  Future<CheckInValidationResult> validateCheckIn({
    required String qrAccessToken,
    required int centerId,
  }) async {
    final response = await _postJson('/api/check-ins/validate', {
      'qrAccessToken': qrAccessToken,
      'centerId': centerId,
    });

    if (response.statusCode == 200) {
      try {
        return CheckInValidationResult.fromJson(
          _readObject(_decodeJson(response.body)),
        );
      } on FormatException catch (error) {
        throw AdminCheckInApiException(error.message);
      }
    }

    if (response.statusCode == 400 ||
        response.statusCode == 404 ||
        response.statusCode == 409) {
      throw AdminCheckInApiException(
        _readProblemMessage(response.body, 'Access validation was denied.'),
        statusCode: response.statusCode,
      );
    }

    throw AdminCheckInApiException(
      'Access validation could not be completed.',
      statusCode: response.statusCode,
    );
  }

  Future<http.Response> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = _buildUri(path);
    final headers = {'Content-Type': 'application/json'};

    try {
      return await _client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
    } on AuthenticationRequiredException {
      throw const AdminCheckInApiException(
        'Please log in to continue.',
        statusCode: 401,
      );
    } on FormatException {
      throw const AdminCheckInApiException('API_BASE_URL is not a valid URL.');
    } on TimeoutException {
      throw const AdminCheckInApiException(
        'The IronBook API did not respond in time.',
      );
    } on http.ClientException {
      throw const AdminCheckInApiException(
        'Unable to connect to the IronBook API.',
      );
    }
  }

  Uri _buildUri(String path) {
    final baseUrl = AppConfig.apiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw const AdminCheckInApiException('API_BASE_URL is not configured.');
    }

    return Uri.parse(baseUrl).resolve(path);
  }

  Object? _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const AdminCheckInApiException('API returned malformed JSON.');
    }
  }

  Map<String, dynamic> _readObject(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    throw const AdminCheckInApiException(
      'API returned an unexpected JSON shape.',
    );
  }

  String _readProblemMessage(String body, String fallback) {
    try {
      final decoded = _decodeJson(body);
      if (decoded is! Map<String, dynamic>) {
        return fallback;
      }

      final message = decoded['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }

      final title = decoded['title'];
      if (title is String && title.trim().isNotEmpty) {
        return title;
      }
    } on AdminCheckInApiException {
      return fallback;
    }

    return fallback;
  }
}
