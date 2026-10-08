import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../models/admin_trainer.dart';

class AdminTrainerApiException implements Exception {
  const AdminTrainerApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AdminTrainerApiService {
  AdminTrainerApiService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<AdminTrainer>> getTrainers({String? search}) async {
    final query = search?.trim();
    final path = query == null || query.isEmpty
        ? '/api/admin/trainers'
        : '/api/admin/trainers?search=${Uri.encodeQueryComponent(query)}';
    final response = await _get(path);

    if (response.statusCode != 200) {
      throw const AdminTrainerApiException('Trainers could not be loaded.');
    }

    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const AdminTrainerApiException(
        'Trainers response was not in the expected format.',
      );
    }

    try {
      return decoded
          .map((item) => AdminTrainer.fromJson(readAdminTrainerObject(item)))
          .toList(growable: false);
    } on FormatException catch (error) {
      throw AdminTrainerApiException(error.message);
    }
  }

  Future<AdminTrainer> getTrainer(int id) async {
    final response = await _get('/api/admin/trainers/$id');

    if (response.statusCode == 404) {
      throw const AdminTrainerApiException('Trainer was not found.');
    }

    if (response.statusCode != 200) {
      throw const AdminTrainerApiException(
        'Trainer details could not be loaded.',
      );
    }

    try {
      return AdminTrainer.fromJson(
        readAdminTrainerObject(_decodeJson(response.body)),
      );
    } on FormatException catch (error) {
      throw AdminTrainerApiException(error.message);
    }
  }

  Future<AdminTrainer> createTrainer(AdminTrainerWriteRequest request) async {
    final response = await _sendJson(
      method: 'POST',
      path: '/api/admin/trainers',
      body: request.toJson(),
    );

    if (response.statusCode == 201) {
      return AdminTrainer.fromJson(
        readAdminTrainerObject(_decodeJson(response.body)),
      );
    }

    throw AdminTrainerApiException(
      _readProblemMessage(response.body, 'Trainer could not be created.'),
    );
  }

  Future<AdminTrainer> updateTrainer(
    int id,
    AdminTrainerWriteRequest request,
  ) async {
    final response = await _sendJson(
      method: 'PUT',
      path: '/api/admin/trainers/$id',
      body: request.toJson(),
    );

    if (response.statusCode == 200) {
      return AdminTrainer.fromJson(
        readAdminTrainerObject(_decodeJson(response.body)),
      );
    }

    if (response.statusCode == 404) {
      throw const AdminTrainerApiException('Trainer was not found.');
    }

    throw AdminTrainerApiException(
      _readProblemMessage(response.body, 'Trainer could not be updated.'),
    );
  }

  Future<http.Response> _get(String path) async {
    final uri = _buildUri(path);

    try {
      return await _client.get(uri).timeout(const Duration(seconds: 15));
    } on FormatException {
      throw const AdminTrainerApiException('API_BASE_URL is not a valid URL.');
    } on TimeoutException {
      throw const AdminTrainerApiException(
        'The IronBook API did not respond in time.',
      );
    } on http.ClientException {
      throw const AdminTrainerApiException(
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
      throw const AdminTrainerApiException('API_BASE_URL is not a valid URL.');
    } on TimeoutException {
      throw const AdminTrainerApiException(
        'The IronBook API did not respond in time.',
      );
    } on http.ClientException {
      throw const AdminTrainerApiException(
        'Unable to connect to the IronBook API.',
      );
    }
  }

  Uri _buildUri(String path) {
    final baseUrl = AppConfig.apiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw const AdminTrainerApiException('API_BASE_URL is not configured.');
    }

    return Uri.parse(baseUrl).resolve(path);
  }

  Object? _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const AdminTrainerApiException('API returned malformed JSON.');
    }
  }

  String _readProblemMessage(String body, String fallback) {
    try {
      final decoded = _decodeJson(body);
      if (decoded is! Map<String, dynamic>) {
        return fallback;
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
    } on AdminTrainerApiException {
      return fallback;
    }

    return fallback;
  }
}
