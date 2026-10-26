import '../models/paged_result.dart';

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ironbook_auth/ironbook_auth.dart';

import 'bearer_http_client.dart';

import '../app_config.dart';
import '../models/admin_center.dart';

class AdminCenterApiException implements Exception {
  const AdminCenterApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AdminCenterApiService {
  AdminCenterApiService({
    http.Client? client,
    AccessTokenProvider? accessTokenProvider,
  }) : _client = BearerHttpClient(
         client: client ?? http.Client(),
         accessTokenProvider: accessTokenProvider ?? SessionStore(),
       );

  final http.Client _client;

  Future<PagedResult<AdminCenter>> getCenters({
    String? search,
    int pageNumber = 1,
    int? pageSize,
  }) async {
    final query = search?.trim();
    final params = <String, String>{
      'pageNumber': '$pageNumber',
      if (pageSize != null) 'pageSize': '$pageSize',
      if (query != null && query.isNotEmpty) 'search': query,
    };
    final path = Uri(
      path: '/api/admin/centers',
      queryParameters: params,
    ).toString();
    final response = await _get(path);

    if (response.statusCode != 200) {
      throw AdminCenterApiException(
        'Centers could not be loaded.',
        statusCode: response.statusCode,
      );
    }

    try {
      return PagedResult.fromJson(
        _decodeJson(response.body),
        AdminCenter.fromJson,
      );
    } on FormatException catch (error) {
      throw AdminCenterApiException(error.message);
    }
  }

  Future<List<AdminCenter>> getAllCenters() async {
    try {
      return await loadAllPages(
        (page) => getCenters(pageNumber: page, pageSize: 100),
      );
    } on FormatException catch (error) {
      throw AdminCenterApiException(error.message);
    }
  }

  Future<AdminCenter> getCenter(int id) async {
    final response = await _get('/api/admin/centers/$id');

    if (response.statusCode == 404) {
      throw AdminCenterApiException(
        'Center was not found.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode != 200) {
      throw AdminCenterApiException(
        'Center details could not be loaded.',
        statusCode: response.statusCode,
      );
    }

    try {
      return AdminCenter.fromJson(_readObject(_decodeJson(response.body)));
    } on FormatException catch (error) {
      throw AdminCenterApiException(error.message);
    }
  }

  Future<AdminCenter> createCenter(AdminCenterWriteRequest request) async {
    final response = await _sendJson(
      method: 'POST',
      path: '/api/admin/centers',
      body: request.toJson(),
    );

    if (response.statusCode == 201) {
      return AdminCenter.fromJson(_readObject(_decodeJson(response.body)));
    }

    throw AdminCenterApiException(
      _readProblemMessage(response.body, 'Center could not be created.'),
      statusCode: response.statusCode,
    );
  }

  Future<AdminCenter> updateCenter(
    int id,
    AdminCenterWriteRequest request,
  ) async {
    final response = await _sendJson(
      method: 'PUT',
      path: '/api/admin/centers/$id',
      body: request.toJson(),
    );

    if (response.statusCode == 200) {
      return AdminCenter.fromJson(_readObject(_decodeJson(response.body)));
    }

    if (response.statusCode == 404) {
      throw AdminCenterApiException(
        'Center was not found.',
        statusCode: response.statusCode,
      );
    }

    throw AdminCenterApiException(
      _readProblemMessage(response.body, 'Center could not be updated.'),
      statusCode: response.statusCode,
    );
  }

  Future<http.Response> _get(String path) async {
    final uri = _buildUri(path);

    try {
      return await _client.get(uri).timeout(const Duration(seconds: 15));
    } on AuthenticationRequiredException {
      throw AdminCenterApiException(
        'Please log in to continue.',
        statusCode: 401,
      );
    } on FormatException {
      throw const AdminCenterApiException('API_BASE_URL is not a valid URL.');
    } on TimeoutException {
      throw const AdminCenterApiException(
        'The IronBook API did not respond in time.',
      );
    } on http.ClientException {
      throw const AdminCenterApiException(
        'Unable to connect to the IronBook API.',
      );
    }
  }

  Future<http.Response> _sendJson({
    required String method,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    final uri = _buildUri(path);
    final encodedBody = jsonEncode(body);
    final headers = {'Content-Type': 'application/json'};

    try {
      final request = method == 'POST'
          ? _client.post(uri, headers: headers, body: encodedBody)
          : _client.put(uri, headers: headers, body: encodedBody);

      return await request.timeout(const Duration(seconds: 15));
    } on AuthenticationRequiredException {
      throw AdminCenterApiException(
        'Please log in to continue.',
        statusCode: 401,
      );
    } on FormatException {
      throw const AdminCenterApiException('API_BASE_URL is not a valid URL.');
    } on TimeoutException {
      throw const AdminCenterApiException(
        'The IronBook API did not respond in time.',
      );
    } on http.ClientException {
      throw const AdminCenterApiException(
        'Unable to connect to the IronBook API.',
      );
    }
  }

  Uri _buildUri(String path) {
    final baseUrl = AppConfig.apiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw const AdminCenterApiException('API_BASE_URL is not configured.');
    }

    return Uri.parse(baseUrl).resolve(path);
  }

  Object? _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const AdminCenterApiException('API returned malformed JSON.');
    }
  }

  Map<String, dynamic> _readObject(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    throw const AdminCenterApiException(
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

      final errors = decoded['errors'];
      if (errors is Map<String, dynamic>) {
        final messages = <String>[];
        for (final entry in errors.entries) {
          final value = entry.value;
          if (value is List) {
            messages.addAll(value.whereType<String>());
          }
        }

        if (messages.isNotEmpty) {
          return messages.join('\n');
        }
      }

      final title = decoded['title'];
      if (title is String && title.trim().isNotEmpty) {
        return title;
      }
    } on AdminCenterApiException {
      return fallback;
    }

    return fallback;
  }
}
