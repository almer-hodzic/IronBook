import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../models/admin_membership_plan.dart';

class AdminMembershipPlanApiException implements Exception {
  const AdminMembershipPlanApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AdminMembershipPlanApiService {
  AdminMembershipPlanApiService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<AdminMembershipPlan>> getMembershipPlans({String? search}) async {
    final query = search?.trim();
    final path = query == null || query.isEmpty
        ? '/api/admin/membership-plans'
        : '/api/admin/membership-plans?search=${Uri.encodeQueryComponent(query)}';
    final response = await _get(path);

    if (response.statusCode != 200) {
      throw const AdminMembershipPlanApiException(
        'Membership plans could not be loaded.',
      );
    }

    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const AdminMembershipPlanApiException(
        'Membership plans response was not in the expected format.',
      );
    }

    try {
      return decoded
          .map((item) => AdminMembershipPlan.fromJson(_readObject(item)))
          .toList(growable: false);
    } on FormatException catch (error) {
      throw AdminMembershipPlanApiException(error.message);
    }
  }

  Future<AdminMembershipPlan> getMembershipPlan(int id) async {
    final response = await _get('/api/admin/membership-plans/$id');

    if (response.statusCode == 404) {
      throw const AdminMembershipPlanApiException(
        'Membership plan was not found.',
      );
    }

    if (response.statusCode != 200) {
      throw const AdminMembershipPlanApiException(
        'Membership plan details could not be loaded.',
      );
    }

    try {
      return AdminMembershipPlan.fromJson(
        _readObject(_decodeJson(response.body)),
      );
    } on FormatException catch (error) {
      throw AdminMembershipPlanApiException(error.message);
    }
  }

  Future<AdminMembershipPlan> createMembershipPlan(
    AdminMembershipPlanWriteRequest request,
  ) async {
    final response = await _sendJson(
      method: 'POST',
      path: '/api/admin/membership-plans',
      body: request.toJson(),
    );

    if (response.statusCode == 201) {
      return AdminMembershipPlan.fromJson(_readObject(_decodeJson(response.body)));
    }

    throw AdminMembershipPlanApiException(
      _readProblemMessage(response.body, 'Membership plan could not be created.'),
    );
  }

  Future<AdminMembershipPlan> updateMembershipPlan(
    int id,
    AdminMembershipPlanWriteRequest request,
  ) async {
    final response = await _sendJson(
      method: 'PUT',
      path: '/api/admin/membership-plans/$id',
      body: request.toJson(),
    );

    if (response.statusCode == 200) {
      return AdminMembershipPlan.fromJson(_readObject(_decodeJson(response.body)));
    }

    if (response.statusCode == 404) {
      throw const AdminMembershipPlanApiException(
        'Membership plan was not found.',
      );
    }

    throw AdminMembershipPlanApiException(
      _readProblemMessage(response.body, 'Membership plan could not be updated.'),
    );
  }

  Future<http.Response> _get(String path) async {
    final uri = _buildUri(path);

    try {
      return await _client.get(uri).timeout(const Duration(seconds: 15));
    } on FormatException {
      throw const AdminMembershipPlanApiException(
        'API_BASE_URL is not a valid URL.',
      );
    } on TimeoutException {
      throw const AdminMembershipPlanApiException(
        'The IronBook API did not respond in time.',
      );
    } on http.ClientException {
      throw const AdminMembershipPlanApiException(
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
      throw const AdminMembershipPlanApiException(
        'API_BASE_URL is not a valid URL.',
      );
    } on TimeoutException {
      throw const AdminMembershipPlanApiException(
        'The IronBook API did not respond in time.',
      );
    } on http.ClientException {
      throw const AdminMembershipPlanApiException(
        'Unable to connect to the IronBook API.',
      );
    }
  }

  Uri _buildUri(String path) {
    final baseUrl = AppConfig.apiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw const AdminMembershipPlanApiException(
        'API_BASE_URL is not configured.',
      );
    }

    return Uri.parse(baseUrl).resolve(path);
  }

  Object? _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const AdminMembershipPlanApiException('API returned malformed JSON.');
    }
  }

  Map<String, dynamic> _readObject(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    throw const AdminMembershipPlanApiException(
      'API returned an unexpected JSON shape.',
    );
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
    } on AdminMembershipPlanApiException {
      return fallback;
    }

    return fallback;
  }
}
