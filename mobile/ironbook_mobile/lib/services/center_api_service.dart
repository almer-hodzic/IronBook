import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../models/center.dart';

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
      throw const CenterApiException('Centers response was not in the expected format.');
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
      throw const CenterApiException('The IronBook API did not respond in time.');
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
}
