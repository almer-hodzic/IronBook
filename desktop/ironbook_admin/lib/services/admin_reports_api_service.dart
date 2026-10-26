import '../models/paged_result.dart';

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ironbook_auth/ironbook_auth.dart';

import 'bearer_http_client.dart';

import '../app_config.dart';
import '../models/admin_center.dart';
import '../models/admin_reports.dart';

class AdminReportsApiException implements Exception {
  const AdminReportsApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class AdminReportsApiService {
  AdminReportsApiService({
    http.Client? client,
    String? apiBaseUrl,
    AccessTokenProvider? accessTokenProvider,
  }) : _client = BearerHttpClient(
         client: client ?? http.Client(),
         accessTokenProvider: accessTokenProvider ?? SessionStore(),
       ),
       _baseUrl = (apiBaseUrl ?? AppConfig.apiBaseUrl).replaceFirst(
         RegExp(r'/+$'),
         '',
       );

  final http.Client _client;
  final String _baseUrl;

  Future<AdminReportSummary> getSummary(AdminReportFilter filter) async =>
      _parse(
        () async => AdminReportSummary.fromJson(
          _object(await _get('/api/admin/reports/summary', filter)),
        ),
      );

  Future<List<AdminCenterActivity>> getCenterActivity(
    AdminReportFilter filter,
  ) async => _parse(() async {
    final data = await _get('/api/admin/reports/centers', filter);
    if (data is! List) {
      throw const FormatException('Invalid center activity response.');
    }
    return data
        .map((item) => AdminCenterActivity.fromJson(_object(item)))
        .toList();
  });

  Future<List<AdminCenter>> getFilterCenters() async => _parse(
    () => loadAllPages(
      (page) async => PagedResult.fromJson(
        await _get(
          '/api/admin/centers',
          const AdminReportFilter(),
          query: {'pageNumber': '$page', 'pageSize': '100'},
        ),
        AdminCenter.fromJson,
      ),
    ),
  );

  Future<T> _parse<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FormatException catch (error) {
      throw AdminReportsApiException(error.message);
    }
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('Invalid reports response.');
  }

  Future<Object?> _get(
    String path,
    AdminReportFilter filter, {
    Map<String, String> query = const {},
  }) async {
    if (_baseUrl.isEmpty) {
      throw const AdminReportsApiException(
        'Configure API_BASE_URL to load reports.',
      );
    }
    try {
      final uri = Uri.parse('$_baseUrl$path').replace(
        queryParameters: {...filter.query, ...query}.isEmpty
            ? null
            : {...filter.query, ...query},
      );
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        var message = 'Reports could not be loaded. Please try again.';
        try {
          final problem = _object(jsonDecode(response.body));
          final errors = problem['errors'];
          if (errors is Map) {
            final messages = errors.values
                .whereType<List>()
                .expand((values) => values)
                .whereType<String>();
            if (messages.isNotEmpty) message = messages.first;
          } else if (problem['detail'] is String) {
            message = problem['detail'] as String;
          }
        } on FormatException {
          /* Use the fallback for non-JSON error responses. */
        }
        throw AdminReportsApiException(
          message,
          statusCode: response.statusCode,
        );
      }
      return jsonDecode(response.body);
    } on AuthenticationRequiredException {
      throw AdminReportsApiException(
        'Please log in to continue.',
        statusCode: 401,
      );
    } on TimeoutException {
      throw const AdminReportsApiException(
        'Reports request timed out. Please retry.',
      );
    } on http.ClientException {
      throw const AdminReportsApiException(
        'Cannot connect to the API. Check the connection and retry.',
      );
    }
  }
}
