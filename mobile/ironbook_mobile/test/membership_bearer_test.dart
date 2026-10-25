import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/models/membership_checkout.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';

import 'support/token_provider.dart';

Map<String, Object?> membership({bool pending = false}) => {
  'membershipId': 12,
  'membershipPlanId': 4,
  'planName': 'Monthly',
  'centerId': 3,
  'centerName': 'Ilidza',
  'startDate': '2030-01-01T00:00:00Z',
  'endDate': '2030-02-01T00:00:00Z',
  'membershipStatus': pending ? 'Pending' : 'Active',
  'paymentAmount': 65.5,
  'paymentMethod': pending ? 'Reception' : 'Card',
  'paymentStatus': pending ? 'PendingReception' : 'Completed',
  'hasQrAccess': !pending,
  'qrAccessToken': pending ? null : 'opaque-signed-qr-fixture',
  'accessMessage': pending
      ? 'Awaiting reception payment.'
      : 'Membership is active.',
};

Map<String, Object?> checkout(MembershipCheckoutPaymentMethod method) => {
  'membershipId': 12,
  'paymentId': 24,
  'centerId': 3,
  'centerName': 'Ilidza',
  'membershipPlanId': 4,
  'planName': 'Monthly',
  'amount': 65.5,
  'paymentMethod': method.apiValue,
  'paymentStatus': method == MembershipCheckoutPaymentMethod.card
      ? 'Completed'
      : 'PendingReception',
  'membershipStatus': method == MembershipCheckoutPaymentMethod.card
      ? 'Active'
      : 'Pending',
  'startDate': '2030-01-01T00:00:00Z',
  'endDate': '2030-02-01T00:00:00Z',
};

void main() {
  final protectedCalls = <String, Future<Object?> Function(CenterApiService)>{
    'My Membership': (api) => api.getMyMembership(),
    'Checkout': (api) => api.checkoutMembership(
      centerId: 3,
      membershipPlanId: 4,
      paymentMethod: MembershipCheckoutPaymentMethod.card,
    ),
  };

  for (final pending in [false, true]) {
    test(
      'My Membership adds current token and preserves all fields (pending=$pending)',
      () async {
        final tokens = FakeAccessTokenProvider('first-token');
        final headers = <String?>[];
        final api = CenterApiService(
          apiBaseUrl: 'http://10.0.2.2:5100',
          accessTokenProvider: tokens,
          client: MockClient((request) async {
            expect(request.method, 'GET');
            expect(
              request.url.toString(),
              'http://10.0.2.2:5100/api/memberships/my',
            );
            expect(request.body, isEmpty);
            headers.add(request.headers['Authorization']);
            return http.Response(jsonEncode(membership(pending: pending)), 200);
          }),
        );
        final result = (await api.getMyMembership())!;
        expect(result.membershipId, 12);
        expect(result.membershipPlanId, 4);
        expect(result.planName, 'Monthly');
        expect(result.centerId, 3);
        expect(result.centerName, 'Ilidza');
        expect(result.startDate, DateTime.utc(2030, 1, 1));
        expect(result.endDate, DateTime.utc(2030, 2, 1));
        expect(result.membershipStatus, pending ? 'Pending' : 'Active');
        expect(result.isActive, !pending);
        expect(result.isPending, pending);
        expect(result.paymentAmount, 65.5);
        expect(result.paymentMethod, pending ? 'Reception' : 'Card');
        expect(
          result.paymentStatus,
          pending ? 'PendingReception' : 'Completed',
        );
        expect(result.hasQrAccess, !pending);
        expect(
          result.qrAccessToken,
          membership(pending: pending)['qrAccessToken'],
        );
        expect(
          result.accessMessage,
          membership(pending: pending)['accessMessage'],
        );
        tokens.token = 'second-token';
        await api.getMyMembership();
        expect(headers, ['Bearer first-token', 'Bearer second-token']);
        expect(tokens.reads, 2);
      },
    );
  }

  test('My Membership 404 retains the no-membership result', () async {
    final api = CenterApiService(
      apiBaseUrl: 'http://localhost',
      accessTokenProvider: FakeAccessTokenProvider(),
      client: MockClient((_) async => http.Response('', 404)),
    );
    expect(await api.getMyMembership(), isNull);
  });

  for (final method in MembershipCheckoutPaymentMethod.values) {
    for (final status in [200, 201]) {
      test(
        '${method.apiValue} checkout $status keeps the exact business-only payload and response',
        () async {
          final tokens = FakeAccessTokenProvider('checkout-token');
          final api = CenterApiService(
            apiBaseUrl: 'http://localhost:5100',
            accessTokenProvider: tokens,
            client: MockClient((request) async {
              expect(request.method, 'POST');
              expect(request.url.path, '/api/memberships/checkout');
              expect(request.headers['Authorization'], 'Bearer checkout-token');
              expect(request.headers['Content-Type'], 'application/json');
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              expect(body, {
                'centerId': 3,
                'membershipPlanId': 4,
                'paymentMethod': method.apiValue,
              });
              for (final forbidden in [
                'memberProfileId',
                'memberId',
                'email',
                'username',
              ]) {
                expect(body.containsKey(forbidden), isFalse);
              }
              return http.Response(jsonEncode(checkout(method)), status);
            }),
          );
          final result = await api.checkoutMembership(
            centerId: 3,
            membershipPlanId: 4,
            paymentMethod: method,
          );
          expect(result.membershipId, 12);
          expect(result.paymentId, 24);
          expect(result.centerId, 3);
          expect(result.centerName, 'Ilidza');
          expect(result.membershipPlanId, 4);
          expect(result.planName, 'Monthly');
          expect(result.amount, 65.5);
          expect(result.paymentMethod, method.apiValue);
          expect(result.paymentStatus, checkout(method)['paymentStatus']);
          expect(result.membershipStatus, checkout(method)['membershipStatus']);
          expect(result.startDate, DateTime.utc(2030, 1, 1));
          expect(result.endDate, DateTime.utc(2030, 2, 1));
          expect(tokens.reads, 1);
        },
      );
    }
  }

  for (final entry in protectedCalls.entries) {
    for (final token in [null, '', 'Bearer malformed']) {
      test(
        '${entry.key} missing/malformed token fails before sending ($token)',
        () async {
          var sent = false;
          final api = CenterApiService(
            apiBaseUrl: 'http://localhost',
            accessTokenProvider: FakeAccessTokenProvider(token),
            client: MockClient((_) async {
              sent = true;
              return http.Response('', 200);
            }),
          );
          await expectLater(
            entry.value(api),
            throwsA(
              isA<CenterApiException>().having(
                (error) => error.statusCode,
                'status',
                401,
              ),
            ),
          );
          expect(sent, isFalse);
        },
      );
    }

    test(
      '${entry.key} 401 remains observable without logout, refresh or retry',
      () async {
        final tokens = FakeAccessTokenProvider('private-fixture-token');
        var calls = 0;
        final api = CenterApiService(
          apiBaseUrl: 'http://localhost',
          accessTokenProvider: tokens,
          client: MockClient((request) async {
            calls++;
            expect(
              request.headers['Authorization'],
              'Bearer private-fixture-token',
            );
            expect(
              request.url.path,
              entry.key == 'Checkout'
                  ? '/api/memberships/checkout'
                  : '/api/memberships/my',
            );
            return http.Response('{"detail":"private-fixture-token"}', 401);
          }),
        );
        await expectLater(
          entry.value(api),
          throwsA(
            isA<CenterApiException>()
                .having((error) => error.statusCode, 'status', 401)
                .having(
                  (error) => error.toString(),
                  'safe message',
                  isNot(contains('private-fixture-token')),
                ),
          ),
        );
        expect(tokens.token, 'private-fixture-token');
        expect(calls, 1);
      },
    );
  }

  for (final status in [400, 409]) {
    test(
      'checkout $status keeps existing validation/conflict feedback',
      () async {
        final api = CenterApiService(
          apiBaseUrl: 'http://localhost',
          accessTokenProvider: FakeAccessTokenProvider(),
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'errors': {
                  'Membership': ['Existing checkout rejection.'],
                },
              }),
              status,
            ),
          ),
        );
        await expectLater(
          protectedCalls['Checkout']!(api),
          throwsA(
            isA<CenterApiException>().having(
              (error) => error.message,
              'message',
              'Existing checkout rejection.',
            ),
          ),
        );
      },
    );
  }

  test(
    'membership non-auth server and malformed-response errors remain unchanged',
    () async {
      var serverError = true;
      final api = CenterApiService(
        apiBaseUrl: 'http://localhost',
        accessTokenProvider: FakeAccessTokenProvider(),
        client: MockClient(
          (_) async => http.Response(
            serverError ? '' : '{invalid',
            serverError ? 500 : 200,
          ),
        ),
      );
      await expectLater(
        api.getMyMembership(),
        throwsA(
          isA<CenterApiException>().having(
            (error) => error.message,
            'message',
            'Membership details could not be loaded.',
          ),
        ),
      );
      await expectLater(
        protectedCalls['Checkout']!(api),
        throwsA(
          isA<CenterApiException>().having(
            (error) => error.message,
            'message',
            'Membership checkout could not be completed.',
          ),
        ),
      );
      serverError = false;
      for (final call in protectedCalls.values) {
        await expectLater(
          call(api),
          throwsA(
            isA<CenterApiException>().having(
              (error) => error.message,
              'message',
              'API returned malformed JSON.',
            ),
          ),
        );
      }
    },
  );

  test('public plan list/details remain usable without token and preserve center paths and parsing', () async {
    final tokens = FakeAccessTokenProvider(null);
    const plan = {
      'id': 4,
      'name': 'Monthly',
      'description': 'Center plan',
      'monthlyPrice': 65.5,
      'benefits': 'Gym; Group classes',
    };
    final paths = <String>[];
    final api = CenterApiService(
      apiBaseUrl: 'http://localhost',
      accessTokenProvider: tokens,
      client: MockClient((request) async {
        paths.add(request.url.path);
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response(
          jsonEncode(request.url.path.endsWith('/4') ? plan : [plan]),
          200,
        );
      }),
    );
    final plans = await api.getMembershipPlansForCenter(3);
    expect(plans, hasLength(1));
    final detail = await api.getMembershipPlanForCenter(3, 4);
    for (final value in [plans.single, detail]) {
      expect(value.id, 4);
      expect(value.name, 'Monthly');
      expect(value.monthlyPrice, 65.5);
      expect(value.description, 'Center plan');
      expect(value.benefitItems, ['Gym', 'Group classes']);
    }
    expect(paths, [
      '/api/centers/3/membership-plans',
      '/api/centers/3/membership-plans/4',
    ]);
    expect(tokens.reads, 0);
  });

  test(
    'public plans retain empty-list and unavailable-plan behavior',
    () async {
      final api = CenterApiService(
        apiBaseUrl: 'http://localhost',
        accessTokenProvider: FakeAccessTokenProvider(null),
        client: MockClient(
          (request) async => request.url.path.endsWith('/4')
              ? http.Response('', 404)
              : http.Response('[]', 200),
        ),
      );
      expect(await api.getMembershipPlansForCenter(3), isEmpty);
      await expectLater(
        api.getMembershipPlanForCenter(3, 4),
        throwsA(
          isA<CenterApiException>().having(
            (error) => error.message,
            'message',
            'Membership plan is not available for this center.',
          ),
        ),
      );
    },
  );

  test(
    'Notifications and Trainer report POST retain non-Bearer behavior',
    () async {
      final tokens = FakeAccessTokenProvider();
      final paths = <String>[];
      final api = CenterApiService(
        apiBaseUrl: 'http://localhost',
        accessTokenProvider: tokens,
        client: MockClient((request) async {
          expect(request.headers.containsKey('Authorization'), isFalse);
          paths.add(request.url.path);
          return request.method == 'GET'
              ? http.Response('[]', 200)
              : http.Response('{}', 400);
        }),
      );
      await api.getMemberNotifications();
      await expectLater(
        api.createTrainingReport(
          trainingRequestId: 8,
          trainingDate: DateTime.utc(2030),
          exercises: [],
        ),
        throwsA(isA<CenterApiException>()),
      );
      expect(tokens.reads, 0);
      expect(paths, [
        '/api/member/notifications',
        '/api/trainer/training-reports',
      ]);
    },
  );
}
