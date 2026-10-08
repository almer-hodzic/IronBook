import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../models/admin_coaching_request.dart';
import '../models/admin_trainer.dart';

class AdminCoachingRequestApiException implements Exception {
  const AdminCoachingRequestApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AdminCoachingRequestApiService {
  AdminCoachingRequestApiService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<AdminCoachingRequest>> getCoachingRequests({
    String? search,
    String? status,
  }) async {
    final params = <String>[];
    final trimmedSearch = search?.trim();
    final trimmedStatus = status?.trim();

    if (trimmedSearch != null && trimmedSearch.isNotEmpty) {
      params.add('search=${Uri.encodeQueryComponent(trimmedSearch)}');
    }

    if (trimmedStatus != null && trimmedStatus.isNotEmpty) {
      params.add('status=${Uri.encodeQueryComponent(trimmedStatus)}');
    }

    final path = params.isEmpty
        ? '/api/admin/coaching-requests'
        : '/api/admin/coaching-requests?${params.join('&')}';
    final response = await _get(path);

    if (response.statusCode != 200) {
      throw const AdminCoachingRequestApiException(
        'Coaching requests could not be loaded.',
      );
    }

    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const AdminCoachingRequestApiException(
        'Coaching requests response was not in the expected format.',
      );
    }

    try {
      return decoded
          .map(
            (item) => AdminCoachingRequest.fromJson(
              readAdminCoachingRequestObject(item),
            ),
          )
          .toList(growable: false);
    } on FormatException catch (error) {
      throw AdminCoachingRequestApiException(error.message);
    }
  }

  Future<AdminCoachingRequest> approve(int id) async {
    return _runAction(id, 'approve');
  }

  Future<AdminCoachingRequest> reject(int id) async {
    return _runAction(id, 'reject');
  }

  Future<AdminCoachingRequest> cancel(int id) async {
    return _runAction(id, 'cancel');
  }

  Future<AdminCoachingRequest> reassignTrainer(
    int id,
    int trainerProfileId,
  ) async {
    final response = await _sendJson(
      method: 'POST',
      path: '/api/admin/coaching-requests/$id/reassign-trainer',
      body: {'trainerProfileId': trainerProfileId},
    );

    if (response.statusCode == 200) {
      return AdminCoachingRequest.fromJson(
        readAdminCoachingRequestObject(_decodeJson(response.body)),
      );
    }

    if (response.statusCode == 404) {
      throw const AdminCoachingRequestApiException(
        'Coaching request was not found.',
      );
    }

    if (response.statusCode == 409) {
      throw AdminCoachingRequestApiException(
        _readProblemMessage(response.body, 'The selected trainer is unavailable.'),
      );
    }

    throw AdminCoachingRequestApiException(
      _readProblemMessage(
        response.body,
        'Trainer could not be reassigned.',
      ),
    );
  }

  Future<List<AdminTrainer>> getActiveTrainersForCenter(int centerId) async {
    final trainers = await _getTrainers();
    return trainers
        .where(
          (trainer) =>
              trainer.isActive &&
              trainer.centers.any((assignment) =>
                  assignment.centerId == centerId && assignment.centerName.isNotEmpty),
        )
        .toList(growable: false);
  }

  Future<AdminCoachingRequest> _runAction(int id, String action) async {
    final response = await _sendJson(
      method: 'POST',
      path: '/api/admin/coaching-requests/$id/$action',
      body: const <String, dynamic>{},
    );

    if (response.statusCode == 200) {
      return AdminCoachingRequest.fromJson(
        readAdminCoachingRequestObject(_decodeJson(response.body)),
      );
    }

    if (response.statusCode == 404) {
      throw const AdminCoachingRequestApiException(
        'Coaching request was not found.',
      );
    }

    throw AdminCoachingRequestApiException(
      _readProblemMessage(response.body, 'Action could not be completed.'),
    );
  }

  Future<List<AdminTrainer>> _getTrainers() async {
    final response = await _get('/api/admin/trainers');

    if (response.statusCode != 200) {
      throw const AdminCoachingRequestApiException(
        'Trainer options could not be loaded.',
      );
    }

    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const AdminCoachingRequestApiException(
        'Trainer response was not in the expected format.',
      );
    }

    return decoded
        .map((item) => AdminTrainer.fromJson(readAdminTrainerObject(item)))
        .toList(growable: false);
  }

  Future<http.Response> _get(String path) async {
    final uri = _buildUri(path);

    try {
      return await _client.get(uri).timeout(const Duration(seconds: 15));
    } on FormatException {
      throw const AdminCoachingRequestApiException('API_BASE_URL is not a valid URL.');
    } on TimeoutException {
      throw const AdminCoachingRequestApiException(
        'The IronBook API did not respond in time.',
      );
    } on http.ClientException {
      throw const AdminCoachingRequestApiException(
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

    try {
      final request = method == 'POST'
          ? _client.post(uri, headers: headers, body: jsonEncode(body))
          : _client.put(uri, headers: headers, body: jsonEncode(body));

      return await request.timeout(const Duration(seconds: 15));
    } on FormatException {
      throw const AdminCoachingRequestApiException('API_BASE_URL is not a valid URL.');
    } on TimeoutException {
      throw const AdminCoachingRequestApiException(
        'The IronBook API did not respond in time.',
      );
    } on http.ClientException {
      throw const AdminCoachingRequestApiException(
        'Unable to connect to the IronBook API.',
      );
    }
  }

  Uri _buildUri(String path) {
    final baseUrl = AppConfig.apiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw const AdminCoachingRequestApiException('API_BASE_URL is not configured.');
    }

    return Uri.parse(baseUrl).resolve(path);
  }

  Object? _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const AdminCoachingRequestApiException('API returned malformed JSON.');
    }
  }

  String _readProblemMessage(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.isNotEmpty) {
          return detail;
        }

        final errors = decoded['errors'];
        if (errors is Map<String, dynamic>) {
          final values = errors.values;
          final messages = <String>[];
          for (final value in values) {
            if (value is List && value.isNotEmpty && value.first is String) {
              messages.addAll(value.cast<String>());
            }
          }

          if (messages.isNotEmpty) {
            return messages.join(' ');
          }
        }
      }
    } on FormatException {
      return fallback;
    }

    return fallback;
  }
}
