import '../models/paged_result.dart';

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ironbook_auth/ironbook_auth.dart';

import 'bearer_http_client.dart';

import '../app_config.dart';
import '../models/admin_center.dart';
import '../models/admin_payment.dart';
import '../models/payment_register_download.dart';

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

  Future<PagedResult<AdminPayment>> getPayments(
    AdminPaymentFilter filter, {
    int pageNumber = 1,
  }) async {
    final data = await _request(
      '/api/admin/payments',
      query: {...filter.query, 'pageNumber': '$pageNumber'},
    );
    return _parse(() => PagedResult.fromJson(data, AdminPayment.fromJson));
  }

  Future<List<AdminCenter>> getCenters() async {
    try {
      return await loadAllPages((page) async {
        final data = await _request(
          '/api/admin/centers',
          query: {'pageNumber': '$page', 'pageSize': '100'},
        );
        return _parse(() => PagedResult.fromJson(data, AdminCenter.fromJson));
      });
    } on FormatException catch (error) {
      throw AdminPaymentApiException(error.message);
    }
  }

  Future<PaymentRegisterDownload> downloadPaymentRegister(
    AdminPaymentFilter filter,
  ) async {
    if (_baseUrl.isEmpty) {
      throw const AdminPaymentApiException(
        'Configure API_BASE_URL to download the Payment Register.',
      );
    }
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/api/admin/payments/pdf').replace(
              queryParameters: filter.query.isEmpty ? null : filter.query,
            ),
            headers: {'Accept': 'application/pdf'},
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        throw AdminPaymentApiException(
          _errorMessage(
            response,
            'The Payment Register could not be downloaded. Please retry.',
          ),
          statusCode: response.statusCode,
        );
      }
      final bytes = response.bodyBytes;
      if (response.headers['content-type']
                  ?.split(';')
                  .first
                  .trim()
                  .toLowerCase() !=
              'application/pdf' ||
          bytes.length < 5 ||
          ascii.decode(bytes.take(5).toList(), allowInvalid: true) != '%PDF-') {
        throw const AdminPaymentApiException(
          'The API did not return a valid PDF. Please retry.',
        );
      }
      return PaymentRegisterDownload(
        bytes: bytes,
        fileName: _pdfFileName(response.headers['content-disposition']),
      );
    } on AuthenticationRequiredException {
      throw const AdminPaymentApiException(
        'Please log in to continue.',
        statusCode: 401,
      );
    } on TimeoutException {
      throw const AdminPaymentApiException(
        'The Payment Register download timed out. Please retry.',
      );
    } on http.ClientException {
      throw const AdminPaymentApiException(
        'Unable to connect to the API. Please retry.',
      );
    } on FormatException {
      throw const AdminPaymentApiException('Invalid API URL or PDF response.');
    }
  }

  static String _pdfFileName(String? header) {
    const fallback = 'ironbook-payment-register.pdf';
    if (header == null) return fallback;
    String? name;
    final extended = RegExp(
      r"(?:^|;)\s*filename\*\s*=\s*UTF-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(header);
    if (extended != null) {
      try {
        name = Uri.decodeComponent(extended.group(1)!.trim());
      } on FormatException {
        /* Try the ordinary filename instead. */
      } on ArgumentError {
        /* Invalid percent encoding: try the ordinary filename instead. */
      }
    }
    name ??= RegExp(
      r'(?:^|;)\s*filename\s*=\s*(?:"([^"]*)"|([^;]+))',
      caseSensitive: false,
    ).firstMatch(header)?.groups([1, 2]).whereType<String>().firstOrNull;
    name = name?.trim();
    if (name == null ||
        name.length > 180 ||
        name.toLowerCase() == '.pdf' ||
        !name.toLowerCase().endsWith('.pdf') ||
        RegExp(r'[\\/:*?"<>|\x00-\x1f]').hasMatch(name)) {
      return fallback;
    }
    return name;
  }

  static String _errorMessage(http.Response response, String fallback) {
    try {
      final problem = _object(jsonDecode(response.body));
      final errors = problem['errors'];
      if (errors is Map) {
        final messages = errors.values
            .whereType<List>()
            .expand((values) => values)
            .whereType<String>();
        if (messages.isNotEmpty) return messages.first;
      } else if (problem['message'] is String) {
        return problem['message'] as String;
      } else if (problem['detail'] is String) {
        return problem['detail'] as String;
      }
    } on FormatException {
      /* Keep the fallback for non-JSON errors. */
    }
    return fallback;
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
        message = _errorMessage(response, message);
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
