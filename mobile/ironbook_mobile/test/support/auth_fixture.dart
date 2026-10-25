import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/main.dart';
import 'package:ironbook_mobile/services/auth_services.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';

class MemorySessionStorage implements SessionStorage {
  String? value;
  Completer<String?>? pendingRead;
  bool failRead = false;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('Private storage detail');
    return pendingRead == null ? value : await pendingRead!.future;
  }

  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

class AuthFixture {
  final storage = MemorySessionStorage();
  final requests = <http.Request>[];
  final now = DateTime.utc(2030, 1, 1);
  Future<http.Response> Function(http.Request)? respond;
  late final http.Client client = MockClient((request) async {
    requests.add(request);
    if (respond != null) return respond!(request);
    if (request.url.path == '/api/auth/logout') return http.Response('', 204);
    return http.Response(jsonEncode(session()), 200);
  });
  late final api = AuthApiService(
    apiBaseUrl: 'http://localhost:5100',
    sessions: SessionStore(storage: storage, now: () => now),
    client: client,
  );

  Map<String, dynamic> session({
    String role = 'Member',
    bool expired = false,
  }) => {
    'accessToken': 'fixture-access-token',
    'expiresAt': now.add(Duration(hours: expired ? -1 : 1)).toIso8601String(),
    'accountId': 7,
    'username': 'fixture-user',
    'role': role,
  };

  void persist({String role = 'Member', bool expired = false}) {
    storage.value = jsonEncode(session(role: role, expired: expired));
  }

  Widget app() => IronBookMobileApp(
    authApiService: api,
    centerApiService: CenterApiService(
      apiBaseUrl: 'http://localhost:5100',
      accessTokenProvider: api.sessions,
      client: MockClient((request) async {
        if (request.url.path == '/api/member/notifications' ||
            request.url.path == '/api/trainer/dashboard/coaching-requests') {
          if (request.headers['Authorization'] !=
              'Bearer fixture-access-token') {
            throw StateError('Missing protected feature authentication');
          }
        } else if (request.headers.containsKey('Authorization')) {
          throw StateError('Unexpected feature auth migration');
        }
        return http.Response('[]', 200);
      }),
    ),
  );
}
