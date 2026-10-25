import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_admin/services/admin_check_in_api_service.dart';

import 'support/token_provider.dart';

void main() {
  test('Admin Check-In preserves signed QR input and successful DTO', () async {
    final api = AdminCheckInApiService(
      accessTokenProvider: FakeAccessTokenProvider(),
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/check-ins/validate');
        expect(request.headers['Authorization'], 'Bearer fixture-access-token');
        expect(jsonDecode(request.body), {
          'qrAccessToken': 'fixture-qr',
          'centerId': 3,
        });
        return http.Response(
          jsonEncode({
            'checkInId': 9,
            'checkedInAt': '2030-01-01T10:00:00Z',
            'membershipId': 4,
            'centerId': 3,
            'centerName': 'Ilidza',
            'memberName': 'Member',
            'accessResult': 'Allowed',
          }),
          200,
        );
      }),
    );
    final result = await api.validateCheckIn(
      qrAccessToken: 'fixture-qr',
      centerId: 3,
    );
    expect(result.checkInId, 9);
    expect(result.checkedInAt, DateTime.utc(2030, 1, 1, 10));
    expect(result.membershipId, 4);
    expect(result.centerId, 3);
    expect(result.centerName, 'Ilidza');
    expect(result.memberName, 'Member');
    expect(result.accessResult, 'Allowed');
  });
  for (final token in [null, '', 'Bearer malformed']) {
    test(
      'invalid token fails before Check-In network access ($token)',
      () async {
        var sent = 0;
        final api = AdminCheckInApiService(
          accessTokenProvider: FakeAccessTokenProvider(token),
          client: MockClient((_) async {
            sent++;
            return http.Response('', 500);
          }),
        );
        await expectLater(
          api.validateCheckIn(qrAccessToken: 'fixture-qr', centerId: 3),
          throwsA(
            isA<AdminCheckInApiException>().having(
              (e) => e.statusCode,
              'status',
              401,
            ),
          ),
        );
        expect(sent, 0);
      },
    );
  }
  for (final code in [401, 403, 400, 404, 409]) {
    test('Check-In $code remains observable without retry/logout', () async {
      var sent = 0;
      final tokens = FakeAccessTokenProvider();
      final api = AdminCheckInApiService(
        accessTokenProvider: tokens,
        client: MockClient((_) async {
          sent++;
          return http.Response(
            jsonEncode({'message': 'Existing rejection.'}),
            code,
          );
        }),
      );
      await expectLater(
        api.validateCheckIn(qrAccessToken: 'fixture-qr', centerId: 3),
        throwsA(
          isA<AdminCheckInApiException>().having(
            (e) => e.statusCode,
            'status',
            code,
          ),
        ),
      );
      expect(sent, 1);
      expect(tokens.token, 'fixture-access-token');
    });
  }
}
