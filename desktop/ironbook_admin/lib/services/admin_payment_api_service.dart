import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ironbook_auth/ironbook_auth.dart';

import 'bearer_http_client.dart';

import '../app_config.dart';
import '../models/admin_center.dart';
import '../models/admin_payment.dart';

class AdminPaymentApiException implements Exception {
  const AdminPaymentApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class AdminPaymentApiService {
  AdminPaymentApiService({
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

  Future<List<AdminPayment>> getPayments(AdminPaymentFilter filter) async {
    final data = await _request('/api/admin/payments', query: filter.query);
    if (data is! List) {
      throw const AdminPaymentApiException('Invalid payments response.');
    }
    return _parse(
      () => data.map((item) => AdminPayment.fromJson(_object(item))).toList(),
    );
  }

  Future<List<AdminCenter>> getCenters() async {
    final data = await _request('/api/admin/centers');
    if (data is! List) {
      throw const AdminPaymentApiException('Invalid centers response.');
    }
    return _parse(
      () => data.map((item) => AdminCenter.fromJson(_object(item))).toList(),
    );
  }

  Future<AdminPayment> confirmReception(int id) async {
    final data = await _request(
      '/api/admin/payments/$id/confirm-reception',
      post: true,
    );
    final payment = _parse(() => AdminPayment.fromJson(_object(data)));
    if (payment.id != id ||
        payment.paymentMethod != 'Reception' ||
        payment.paymentStatus != 'Completed' ||
        payment.membershipStatus != 'Active') {
      throw const AdminPaymentApiException(
        'The API did not confirm this payment and membership. Refresh to check their current status.',
      );
    }
    return payment;
  }

  T _parse<T>(T Function() action) {
    try {
      return action();
    } on FormatException catch (error) {
      throw AdminPaymentApiException(error.message);
    }
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('Invalid payment response.');
  }

  Future<Object?> _request(
    String path, {
    Map<String, String> query = const {},
    bool post = false,
  }) async {
    if (_baseUrl.isEmpty) {
      throw const AdminPaymentApiException(
        'Configure API_BASE_URL to load payments.',
      );
    }
    try {
      final uri = Uri.parse('$_baseUrl$path')
          .replace(queryParameters: query.isEmpty ? null : query);
      final response =
          await (post
                  ? _client.post(
                      uri,
                      headers: {'Content-Type': 'application/json'},
                      body: '{}',
                    )
                  : _client.get(uri))
              .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        var message = post
            ? 'Payment could not be confirmed. Refresh and try again.'
            : 'Payments could not be loaded. Please retry.';
        try {
          final problem = _object(jsonDecode(response.body));
          final errors = problem['errors'];
          if (errors is Map) {
            final messages = errors.values
                .whereType<List>()
                .expand((values) => values)
                .whereType<String>();
            if (messages.isNotEmpty) message = messages.first;
          } else if (problem['message'] is String) {
            message = problem['message'] as String;
          } else if (problem['detail'] is String) {
            message = problem['detail'] as String;
          }
        } on FormatException {
          /* Keep the fallback for non-JSON error responses. */
        }
        throw AdminPaymentApiException(
          message,
          statusCode: response.statusCode,
        );
      }
      return jsonDecode(response.body);
    } on AuthenticationRequiredException {
      throw AdminPaymentApiException(
        'Please log in to continue.',
        statusCode: 401,
      );
    } on FormatException {
      throw const AdminPaymentApiException(
        'Invalid API URL or payment response.',
      );
    } on TimeoutException {
      throw const AdminPaymentApiException(
        'The API did not respond in time. Refresh to check current payment status.',
      );
    } on http.ClientException {
      throw const AdminPaymentApiException(
        'Unable to connect to the API. Refresh and retry.',
      );
    }
  }
}
