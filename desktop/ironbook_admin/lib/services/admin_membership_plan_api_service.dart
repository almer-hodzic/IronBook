import '../models/paged_result.dart';

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ironbook_auth/ironbook_auth.dart';

import 'bearer_http_client.dart';

import '../app_config.dart';
import '../models/admin_membership_plan.dart';

class AdminMembershipPlanApiException implements Exception {
  const AdminMembershipPlanApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AdminMembershipPlanApiService {
  AdminMembershipPlanApiService({
    http.Client? client,
    AccessTokenProvider? accessTokenProvider,
  }) : _client = BearerHttpClient(
         client: client ?? http.Client(),
         accessTokenProvider: accessTokenProvider ?? SessionStore(),
       );

  final http.Client _client;

  Future<PagedResult<AdminMembershipPlan>> getMembershipPlans({
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
      path: '/api/admin/membership-plans',
      queryParameters: params,
    ).toString();
    final response = await _get(path);

    if (response.statusCode != 200) {
      throw AdminMembershipPlanApiException(
        'Membership plans could not be loaded.',
        statusCode: response.statusCode,
      );
    }

    try {
      return PagedResult.fromJson(
        _decodeJson(response.body),
        AdminMembershipPlan.fromJson,
      );
    } on FormatException catch (error) {
      throw AdminMembershipPlanApiException(error.message);
    }
  }

  Future<AdminMembershipPlan> getMembershipPlan(int id) async {
    final response = await _get('/api/admin/membership-plans/$id');

    if (response.statusCode == 404) {
      throw AdminMembershipPlanApiException(
        'Membership plan was not found.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode != 200) {
      throw AdminMembershipPlanApiException(
        'Membership plan details could not be loaded.',
        statusCode: response.statusCode,
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
      return AdminMembershipPlan.fromJson(
        _readObject(_decodeJson(response.body)),
      );
    }

    throw AdminMembershipPlanApiException(
      _readProblemMessage(
        response.body,
        'Membership plan could not be created.',
      ),
      statusCode: response.statusCode,
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
      return AdminMembershipPlan.fromJson(
        _readObject(_decodeJson(response.body)),
      );
    }

    if (response.statusCode == 404) {
      throw AdminMembershipPlanApiException(
        'Membership plan was not found.',
        statusCode: response.statusCode,
      );
    }

    throw AdminMembershipPlanApiException(
      _readProblemMessage(
        response.body,
        'Membership plan could not be updated.',
      ),
      statusCode: response.statusCode,
    );
  }

  Future<http.Response> _get(String path) async {
    final uri = _buildUri(path);

    try {
      return await _client.get(uri).timeout(const Duration(seconds: 15));
    } on AuthenticationRequiredException {
      throw AdminMembershipPlanApiException(
        'Please log in to continue.',
        statusCode: 401,
      );
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
    } on AuthenticationRequiredException {
      throw AdminMembershipPlanApiException(
        'Please log in to continue.',
        statusCode: 401,
      );
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
      throw const AdminMembershipPlanApiException(
        'API returned malformed JSON.',
      );
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
