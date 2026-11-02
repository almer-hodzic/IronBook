import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ironbook_auth/ironbook_auth.dart';

import 'bearer_http_client.dart';

import '../app_config.dart';
import '../models/check_in_validation.dart';
import '../models/admin_reports.dart';
import '../models/pdf_download.dart';
import 'pdf_download_response.dart';

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

  Future<PdfDownload> downloadCheckInRegister(AdminReportFilter filter) async {
    try {
      final query = Map<String, String>.fromEntries(
        filter.query.entries.where((entry) => entry.value.trim().isNotEmpty),
      );
      final response = await _client
          .get(
            _buildUri('/api/admin/check-ins/pdf')
                .replace(queryParameters: query.isEmpty ? null : query),
            headers: {'Accept': 'application/pdf'},
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        var message = _readProblemMessage(
          response.body,
          'The Check-In Register could not be downloaded. Please retry.',
        );
        try {
          final problem = jsonDecode(response.body);
          if (problem is Map && problem['errors'] is Map) {
            final errors = (problem['errors'] as Map).values
                .whereType<List>()
                .expand((values) => values)
                .whereType<String>();
            if (errors.isNotEmpty) message = errors.first;
          }
        } on FormatException {
          /* Keep the existing controlled fallback. */
        }
        throw AdminCheckInApiException(
          message,
          statusCode: response.statusCode,
        );
      }
      try {
        return parsePdfDownload(
          response,
          fallbackFileName: 'ironbook-check-in-register.pdf',
        );
      } on FormatException catch (error) {
        throw AdminCheckInApiException(error.message);
      }
    } on AuthenticationRequiredException {
      throw const AdminCheckInApiException(
        'Please log in to continue.',
        statusCode: 401,
      );
    } on TimeoutException {
      throw const AdminCheckInApiException(
        'The Check-In Register download timed out. Please retry.',
      );
    } on http.ClientException {
      throw const AdminCheckInApiException(
        'Unable to connect to the API. Please retry.',
      );
    } on FormatException {
      throw const AdminCheckInApiException('API_BASE_URL is not a valid URL.');
    }
  }

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
