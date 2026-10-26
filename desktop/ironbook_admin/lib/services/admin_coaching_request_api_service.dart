import '../models/paged_result.dart';

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ironbook_auth/ironbook_auth.dart';

import 'bearer_http_client.dart';

import '../app_config.dart';
import '../models/admin_coaching_request.dart';
import '../models/admin_trainer.dart';

class AdminCoachingRequestApiException implements Exception {
  const AdminCoachingRequestApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AdminCoachingRequestApiService {
  AdminCoachingRequestApiService({
    http.Client? client,
    AccessTokenProvider? accessTokenProvider,
  }) : _client = BearerHttpClient(
         client: client ?? http.Client(),
         accessTokenProvider: accessTokenProvider ?? SessionStore(),
       );

  final http.Client _client;

  Future<PagedResult<AdminCoachingRequest>> getCoachingRequests({
    int pageNumber = 1,
    int? pageSize,
    String? search,
    String? status,
  }) async {
    final params = <String>[
      'pageNumber=$pageNumber',
      if (pageSize != null) 'pageSize=$pageSize',
    ];
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
      throw AdminCoachingRequestApiException(
        'Coaching requests could not be loaded.',
        statusCode: response.statusCode,
      );
    }

    try {
      return PagedResult.fromJson(
        _decodeJson(response.body),
        AdminCoachingRequest.fromJson,
      );
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
      throw AdminCoachingRequestApiException(
        'Coaching request was not found.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode == 409) {
      throw AdminCoachingRequestApiException(
        _readProblemMessage(
          response.body,
          'The selected trainer is unavailable.',
        ),
        statusCode: response.statusCode,
      );
    }

    throw AdminCoachingRequestApiException(
      _readProblemMessage(response.body, 'Trainer could not be reassigned.'),
      statusCode: response.statusCode,
    );
  }

  Future<List<AdminTrainer>> getActiveTrainersForCenter(int centerId) async {
    final trainers = await _getTrainers();
    return trainers
        .where(
          (trainer) =>
              trainer.isActive &&
              trainer.centers.any(
                (assignment) =>
                    assignment.centerId == centerId &&
                    assignment.centerName.isNotEmpty,
              ),
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
      throw AdminCoachingRequestApiException(
        'Coaching request was not found.',
        statusCode: response.statusCode,
      );
    }

    throw AdminCoachingRequestApiException(
      _readProblemMessage(response.body, 'Action could not be completed.'),
      statusCode: response.statusCode,
    );
  }

  Future<List<AdminTrainer>> _getTrainers() async {
    try {
      return await loadAllPages((page) async {
        final response = await _get(
          '/api/admin/trainers?pageNumber=$page&pageSize=100',
        );
        if (response.statusCode != 200) {
          throw AdminCoachingRequestApiException(
            'Trainer options could not be loaded.',
            statusCode: response.statusCode,
          );
        }
        return PagedResult.fromJson(
          _decodeJson(response.body),
          AdminTrainer.fromJson,
        );
      });
    } on FormatException catch (error) {
      throw AdminCoachingRequestApiException(error.message);
    }
  }

  Future<http.Response> _get(String path) async {
    final uri = _buildUri(path);

    try {
      return await _client.get(uri).timeout(const Duration(seconds: 15));
    } on AuthenticationRequiredException {
      throw AdminCoachingRequestApiException(
        'Please log in to continue.',
        statusCode: 401,
      );
    } on FormatException {
      throw const AdminCoachingRequestApiException(
        'API_BASE_URL is not a valid URL.',
      );
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
    } on AuthenticationRequiredException {
      throw AdminCoachingRequestApiException(
        'Please log in to continue.',
        statusCode: 401,
      );
    } on FormatException {
      throw const AdminCoachingRequestApiException(
        'API_BASE_URL is not a valid URL.',
      );
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
      throw const AdminCoachingRequestApiException(
        'API_BASE_URL is not configured.',
      );
    }

    return Uri.parse(baseUrl).resolve(path);
  }

  Object? _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const AdminCoachingRequestApiException(
        'API returned malformed JSON.',
      );
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
