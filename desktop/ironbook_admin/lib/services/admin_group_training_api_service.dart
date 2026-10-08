import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../models/admin_group_training.dart';

class AdminGroupTrainingApiException implements Exception {
  const AdminGroupTrainingApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AdminGroupTrainingApiService {
  AdminGroupTrainingApiService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<AdminGroupTraining>> getGroupTrainings({
    String? search,
    int? centerId,
  }) async {
    final params = <String, String>{};
    final query = search?.trim();
    if (query != null && query.isNotEmpty) {
      params['search'] = query;
    }
    if (centerId != null) {
      params['centerId'] = centerId.toString();
    }

    final response = await _get(_path('/api/admin/group-trainings', params));
    if (response.statusCode != 200) {
      throw const AdminGroupTrainingApiException(
        'Group trainings could not be loaded.',
      );
    }

    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const AdminGroupTrainingApiException(
        'Group trainings response was not in the expected format.',
      );
    }

    try {
      return decoded
          .map(
            (item) =>
                AdminGroupTraining.fromJson(readAdminGroupTrainingObject(item)),
          )
          .toList(growable: false);
    } on FormatException catch (error) {
      throw AdminGroupTrainingApiException(error.message);
    }
  }

  Future<AdminGroupTraining> getGroupTraining(int id) async {
    final response = await _get('/api/admin/group-trainings/$id');

    if (response.statusCode == 404) {
      throw const AdminGroupTrainingApiException(
        'Group training was not found.',
      );
    }

    if (response.statusCode != 200) {
      throw const AdminGroupTrainingApiException(
        'Group training details could not be loaded.',
      );
    }

    try {
      return AdminGroupTraining.fromJson(
        readAdminGroupTrainingObject(_decodeJson(response.body)),
      );
    } on FormatException catch (error) {
      throw AdminGroupTrainingApiException(error.message);
    }
  }

  Future<List<AdminTrainerOption>> getTrainerOptions({int? centerId}) async {
    final params = <String, String>{};
    if (centerId != null) {
      params['centerId'] = centerId.toString();
    }

    final response = await _get(
      _path('/api/admin/group-trainings/trainer-options', params),
    );
    if (response.statusCode != 200) {
      throw const AdminGroupTrainingApiException(
        'Trainer options could not be loaded.',
      );
    }

    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const AdminGroupTrainingApiException(
        'Trainer options response was not in the expected format.',
      );
    }

    try {
      return decoded
          .map(
            (item) =>
                AdminTrainerOption.fromJson(readAdminGroupTrainingObject(item)),
          )
          .toList(growable: false);
    } on FormatException catch (error) {
      throw AdminGroupTrainingApiException(error.message);
    }
  }

  Future<AdminGroupTraining> createGroupTraining(
    AdminGroupTrainingWriteRequest request,
  ) async {
    final response = await _sendJson(
      method: 'POST',
      path: '/api/admin/group-trainings',
      body: request.toJson(),
    );

    if (response.statusCode == 201) {
      return AdminGroupTraining.fromJson(
        readAdminGroupTrainingObject(_decodeJson(response.body)),
      );
    }

    throw AdminGroupTrainingApiException(
      _readProblemMessage(
        response.body,
        'Group training could not be created.',
      ),
    );
  }

  Future<AdminGroupTraining> updateGroupTraining(
    int id,
    AdminGroupTrainingWriteRequest request,
  ) async {
    final response = await _sendJson(
      method: 'PUT',
      path: '/api/admin/group-trainings/$id',
      body: request.toJson(),
    );

    if (response.statusCode == 200) {
      return AdminGroupTraining.fromJson(
        readAdminGroupTrainingObject(_decodeJson(response.body)),
      );
    }

    if (response.statusCode == 404) {
      throw const AdminGroupTrainingApiException(
        'Group training was not found.',
      );
    }

    throw AdminGroupTrainingApiException(
      _readProblemMessage(
        response.body,
        'Group training could not be updated.',
      ),
    );
  }

  Future<http.Response> _get(String path) async {
    final uri = _buildUri(path);

    try {
      return await _client.get(uri).timeout(const Duration(seconds: 15));
    } on FormatException {
      throw const AdminGroupTrainingApiException(
        'API_BASE_URL is not a valid URL.',
      );
    } on TimeoutException {
      throw const AdminGroupTrainingApiException(
        'The IronBook API did not respond in time.',
      );
    } on http.ClientException {
      throw const AdminGroupTrainingApiException(
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
    final headers = {'Content-Type': 'application/json'};
    final encodedBody = jsonEncode(body);

    try {
      final request = method == 'POST'
          ? _client.post(uri, headers: headers, body: encodedBody)
          : _client.put(uri, headers: headers, body: encodedBody);

      return await request.timeout(const Duration(seconds: 15));
    } on FormatException {
      throw const AdminGroupTrainingApiException(
        'API_BASE_URL is not a valid URL.',
      );
    } on TimeoutException {
      throw const AdminGroupTrainingApiException(
        'The IronBook API did not respond in time.',
      );
    } on http.ClientException {
      throw const AdminGroupTrainingApiException(
        'Unable to connect to the IronBook API.',
      );
    }
  }

  Uri _buildUri(String path) {
    final baseUrl = AppConfig.apiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw const AdminGroupTrainingApiException(
        'API_BASE_URL is not configured.',
      );
    }

    return Uri.parse(baseUrl).resolve(path);
  }

  Object? _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const AdminGroupTrainingApiException(
        'API returned malformed JSON.',
      );
    }
  }

  String _path(String basePath, Map<String, String> query) {
    if (query.isEmpty) {
      return basePath;
    }

    final encoded = query.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    return '$basePath?$encoded';
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
    } on AdminGroupTrainingApiException {
      return fallback;
    }

    return fallback;
  }
}
