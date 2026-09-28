import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../models/admin_center.dart';

class AdminCenterApiException implements Exception {
  const AdminCenterApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AdminCenterApiService {
  AdminCenterApiService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<AdminCenter>> getCenters({String? search}) async {
    final query = search?.trim();
    final path = query == null || query.isEmpty
        ? '/api/admin/centers'
        : '/api/admin/centers?search=${Uri.encodeQueryComponent(query)}';
    final response = await _get(path);

    if (response.statusCode != 200) {
      throw const AdminCenterApiException('Centers could not be loaded.');
    }

    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const AdminCenterApiException(
        'Centers response was not in the expected format.',
      );
    }

    try {
      return decoded
          .map((item) => AdminCenter.fromJson(_readObject(item)))
          .toList(growable: false);
    } on FormatException catch (error) {
      throw AdminCenterApiException(error.message);
    }
  }

  Future<AdminCenter> getCenter(int id) async {
    final response = await _get('/api/admin/centers/$id');

    if (response.statusCode == 404) {
      throw const AdminCenterApiException('Center was not found.');
    }

    if (response.statusCode != 200) {
      throw const AdminCenterApiException(
        'Center details could not be loaded.',
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
      throw const AdminCenterApiException('Center was not found.');
    }

    throw AdminCenterApiException(
      _readProblemMessage(response.body, 'Center could not be updated.'),
    );
  }

  Future<http.Response> _get(String path) async {
    final uri = _buildUri(path);

    try {
      return await _client.get(uri).timeout(const Duration(seconds: 15));
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
