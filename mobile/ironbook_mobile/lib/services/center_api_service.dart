import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../models/center.dart';
import '../models/group_training.dart';
import '../models/membership_checkout.dart';
import '../models/membership_plan.dart';
import '../models/my_membership.dart';

class CenterApiException implements Exception {
  const CenterApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CenterApiService {
  CenterApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<FitnessCenter>> getCenters() async {
    final response = await _get('/api/centers');

    if (response.statusCode != 200) {
      throw CenterApiException('Centers could not be loaded.');
    }

    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const CenterApiException(
        'Centers response was not in the expected format.',
      );
    }

    try {
      return decoded
          .map((item) => FitnessCenter.fromJson(_readObject(item)))
          .toList(growable: false);
    } on FormatException catch (error) {
      throw CenterApiException(error.message);
    }
  }

  Future<FitnessCenter> getCenter(int id) async {
    final response = await _get('/api/centers/$id');

    if (response.statusCode == 404) {
      throw const CenterApiException('Center was not found.');
    }

    if (response.statusCode != 200) {
      throw const CenterApiException('Center details could not be loaded.');
    }

    try {
      return FitnessCenter.fromJson(_readObject(_decodeJson(response.body)));
    } on FormatException catch (error) {
      throw CenterApiException(error.message);
    }
  }

  Future<List<MembershipPlan>> getMembershipPlansForCenter(int centerId) async {
    final response = await _get('/api/centers/$centerId/membership-plans');

    if (response.statusCode != 200) {
      throw const CenterApiException('Membership plans could not be loaded.');
    }

    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const CenterApiException(
        'Membership plans response was not in the expected format.',
      );
    }

    try {
      return decoded
          .map((item) => MembershipPlan.fromJson(_readObject(item)))
          .toList(growable: false);
    } on FormatException catch (error) {
      throw CenterApiException(error.message);
    }
  }

  Future<MembershipPlan> getMembershipPlanForCenter(
    int centerId,
    int planId,
  ) async {
    final response = await _get(
      '/api/centers/$centerId/membership-plans/$planId',
    );

    if (response.statusCode == 404) {
      throw const CenterApiException(
        'Membership plan is not available for this center.',
      );
    }

    if (response.statusCode != 200) {
      throw const CenterApiException(
        'Membership plan details could not be loaded.',
      );
    }

    try {
      return MembershipPlan.fromJson(_readObject(_decodeJson(response.body)));
    } on FormatException catch (error) {
      throw CenterApiException(error.message);
    }
  }

  Future<List<GroupTraining>> getGroupTrainingsForCenter(
    int centerId, {
    String? search,
  }) async {
    final query = search?.trim();
    final path = query == null || query.isEmpty
        ? '/api/centers/$centerId/group-trainings'
        : '/api/centers/$centerId/group-trainings?search=${Uri.encodeQueryComponent(query)}';
    final response = await _get(path);

    if (response.statusCode != 200) {
      throw const CenterApiException('Group trainings could not be loaded.');
    }

    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const CenterApiException(
        'Group trainings response was not in the expected format.',
      );
    }

    try {
      return decoded
          .map((item) => GroupTraining.fromJson(_readObject(item)))
          .toList(growable: false);
    } on FormatException catch (error) {
      throw CenterApiException(error.message);
    }
  }

  Future<GroupTraining> getGroupTrainingForCenter(
    int centerId,
    int groupTrainingId,
  ) async {
    final response = await _get(
      '/api/centers/$centerId/group-trainings/$groupTrainingId',
    );

    if (response.statusCode == 404) {
      throw const CenterApiException(
        'Group training is not available for this center.',
      );
    }

    if (response.statusCode != 200) {
      throw const CenterApiException(
        'Group training details could not be loaded.',
      );
    }

    try {
      return GroupTraining.fromJson(_readObject(_decodeJson(response.body)));
    } on FormatException catch (error) {
      throw CenterApiException(error.message);
    }
  }

  Future<GroupTrainingEnrollment> enrollGroupTraining({
    required int centerId,
    required int groupTrainingId,
  }) async {
    final response = await _post(
      '/api/centers/$centerId/group-trainings/$groupTrainingId/enroll',
      {},
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      try {
        return GroupTrainingEnrollment.fromJson(
          _readObject(_decodeJson(response.body)),
        );
      } on FormatException catch (error) {
        throw CenterApiException(error.message);
      }
    }

    if (response.statusCode == 400 ||
        response.statusCode == 404 ||
        response.statusCode == 409) {
      throw CenterApiException(
        _readProblemMessage(
          response.body,
          'Group training enrollment was rejected.',
        ),
      );
    }

    throw const CenterApiException(
      'Group training enrollment could not be completed.',
    );
  }

  Future<MembershipCheckoutResult> checkoutMembership({
    required int centerId,
    required int membershipPlanId,
    required MembershipCheckoutPaymentMethod paymentMethod,
  }) async {
    final response = await _post('/api/memberships/checkout', {
      'centerId': centerId,
      'membershipPlanId': membershipPlanId,
      'paymentMethod': paymentMethod.apiValue,
    });

    if (response.statusCode == 200 || response.statusCode == 201) {
      try {
        return MembershipCheckoutResult.fromJson(
          _readObject(_decodeJson(response.body)),
        );
      } on FormatException catch (error) {
        throw CenterApiException(error.message);
      }
    }

    if (response.statusCode == 400 || response.statusCode == 409) {
      throw CenterApiException(
        _readProblemMessage(response.body, 'Membership checkout was rejected.'),
      );
    }

    throw const CenterApiException(
      'Membership checkout could not be completed.',
    );
  }

  Future<MyMembership?> getMyMembership() async {
    final response = await _get('/api/memberships/my');

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode != 200) {
      throw const CenterApiException('Membership details could not be loaded.');
    }

    try {
      return MyMembership.fromJson(_readObject(_decodeJson(response.body)));
    } on FormatException catch (error) {
      throw CenterApiException(error.message);
    }
  }

  Future<CheckInValidationResult> validateCheckIn({
    required String qrAccessToken,
    required int centerId,
  }) async {
    final response = await _post('/api/check-ins/validate', {
      'qrAccessToken': qrAccessToken,
      'centerId': centerId,
    });

    if (response.statusCode == 200) {
      try {
        return CheckInValidationResult.fromJson(
          _readObject(_decodeJson(response.body)),
        );
      } on FormatException catch (error) {
        throw CenterApiException(error.message);
      }
    }

    if (response.statusCode == 400 ||
        response.statusCode == 404 ||
        response.statusCode == 409) {
      throw CenterApiException(
        _readProblemMessage(response.body, 'Check-in validation was rejected.'),
      );
    }

    throw const CenterApiException(
      'Check-in validation could not be completed.',
    );
  }

  Future<http.Response> _get(String path) async {
    final baseUrl = AppConfig.apiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw const CenterApiException('API_BASE_URL is not configured.');
    }

    final uri = Uri.parse(baseUrl).resolve(path);

    try {
      return await _client.get(uri).timeout(const Duration(seconds: 15));
    } on FormatException {
      throw const CenterApiException('API_BASE_URL is not a valid URL.');
    } on TimeoutException {
      throw const CenterApiException(
        'The IronBook API did not respond in time.',
      );
    } on http.ClientException {
      throw const CenterApiException('Unable to connect to the IronBook API.');
    }
  }

  Future<http.Response> _post(String path, Map<String, Object?> body) async {
    final baseUrl = AppConfig.apiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw const CenterApiException('API_BASE_URL is not configured.');
    }

    final uri = Uri.parse(baseUrl).resolve(path);

    try {
      return await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } on FormatException {
      throw const CenterApiException('API_BASE_URL is not a valid URL.');
    } on TimeoutException {
      throw const CenterApiException(
        'The IronBook API did not respond in time.',
      );
    } on http.ClientException {
      throw const CenterApiException('Unable to connect to the IronBook API.');
    }
  }

  Object? _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const CenterApiException('API returned malformed JSON.');
    }
  }

  Map<String, dynamic> _readObject(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    throw const CenterApiException('API returned an unexpected JSON shape.');
  }

  String _readProblemMessage(String body, String fallback) {
    try {
      final decoded = _decodeJson(body);
      if (decoded is! Map<String, dynamic>) {
        return fallback;
      }

      final errors = decoded['errors'];
      if (errors is Map<String, dynamic>) {
        for (final value in errors.values) {
          if (value is List && value.isNotEmpty) {
            final first = value.first;
            if (first is String && first.trim().isNotEmpty) {
              return first.trim();
            }
          }
        }
      }

      final detail = decoded['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }

      final title = decoded['title'];
      if (title is String && title.trim().isNotEmpty) {
        return title.trim();
      }
    } on CenterApiException {
      return fallback;
    }

    return fallback;
  }
}
