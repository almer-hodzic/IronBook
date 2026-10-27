import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/models/membership_checkout.dart';
import 'package:ironbook_mobile/models/membership_plan.dart';
import 'package:ironbook_mobile/screens/card_payment_screen.dart';
import 'package:ironbook_mobile/screens/membership_checkout_screen.dart';
import 'package:ironbook_mobile/screens/membership_confirmation_screen.dart';
import 'package:ironbook_mobile/screens/my_membership_screen.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';
import 'package:ironbook_mobile/services/stripe_payment_client.dart';
import 'package:ironbook_mobile/theme/ironbook_mobile_theme.dart';

import 'membership_bearer_test.dart' show checkout, membership;
import 'support/token_provider.dart';

Map<String, Object?> cardCheckout({
  String status = 'PendingCard',
  bool details = true,
}) => {
  ...checkout(MembershipCheckoutPaymentMethod.card),
  'paymentStatus': status,
  'membershipStatus': status == 'Completed'
      ? 'Active'
      : status == 'Cancelled'
      ? 'Cancelled'
      : 'Pending',
  if (details)
    'cardPayment': {
      'paymentIntentId': 'pi_fixture',
      'clientSecret': 'pi_fixture_secret_fixture',
      'currency': 'eur',
      'status': 'requires_payment_method',
    },
};

class FakeStripe implements StripePaymentClient {
  String? failure;
  bool configured = true;
  int readyCalls = 0;
  final secrets = <String>[];
  Completer<void>? confirmation;

  @override
  Future<void> ensureReady() async {
    readyCalls++;
    if (!configured) {
      throw const CardPaymentException('Card payment is not configured.');
    }
  }

  @override
  Future<void> confirmPayment(
    String clientSecret, {
    required bool Function() canPresent,
  }) async {
    secrets.add(clientSecret);
    if (confirmation != null) await confirmation!.future;
    if (!canPresent()) return;
    if (failure != null) throw CardPaymentException(failure!);
  }
}

class PaymentFixture {
  final stripe = FakeStripe();
  final requests = <http.Request>[];
  bool hasMembership = false;
  bool active = false;
  String completionStatus = 'Completed';
  int completionHttp = 200;
  int checkoutHttp = 201;
  bool loseCheckoutResponse = false;
  bool failMembershipRefresh = false;
  String? seenMethod;
  int get creates =>
      requests.where((r) => r.url.path == '/api/memberships/checkout').length;
  int get resumes =>
      requests.where((r) => r.url.path.endsWith('/card-payment')).length;
  int get completes =>
      requests.where((r) => r.url.path.endsWith('/complete-card')).length;
  int get reads => requests.where((r) => r.method == 'GET').length;

  late final api = CenterApiService(
    apiBaseUrl: 'http://localhost:5100',
    accessTokenProvider: FakeAccessTokenProvider(),
    client: MockClient((request) async {
      requests.add(request);
      expect(request.headers['Authorization'], 'Bearer fixture-access-token');
      if (request.method == 'GET') {
        if (!hasMembership) return http.Response('', 404);
        if (failMembershipRefresh && active) return http.Response('', 503);
        return http.Response(
          jsonEncode({
            ...membership(pending: !active),
            'paymentMethod': seenMethod ?? 'Card',
            'paymentStatus': active
                ? 'Completed'
                : seenMethod == 'Reception'
                ? 'PendingReception'
                : 'PendingCard',
          }),
          200,
        );
      }
      if (request.url.path == '/api/memberships/checkout') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys.toSet(), {
          'centerId',
          'membershipPlanId',
          'paymentMethod',
        });
        expect(body['centerId'], 3);
        expect(body['membershipPlanId'], 4);
        seenMethod = body['paymentMethod'] as String;
        hasMembership = true;
        if (loseCheckoutResponse) throw http.ClientException('lost response');
        final result = seenMethod == 'Reception'
            ? checkout(MembershipCheckoutPaymentMethod.reception)
            : cardCheckout();
        return http.Response(
          jsonEncode(
            checkoutHttp == 503
                ? {
                    'message': 'Provider unavailable.',
                    'checkout': cardCheckout(details: false),
                  }
                : result,
          ),
          checkoutHttp,
        );
      }
      expect(request.body, isEmpty);
      expect(request.url.queryParameters, isEmpty);
      if (request.url.path == '/api/memberships/12/card-payment') {
        return http.Response(jsonEncode(cardCheckout()), 200);
      }
      if (request.url.path == '/api/memberships/12/complete-card') {
        active = completionStatus == 'Completed' && completionHttp == 200;
        final result = cardCheckout(status: completionStatus, details: false);
        return http.Response(
          jsonEncode(
            completionHttp >= 400
                ? {
                    'message': 'Payment could not be verified.',
                    'checkout': result,
                  }
                : result,
          ),
          completionHttp,
        );
      }
      throw StateError('Unexpected payment fixture request.');
    }),
  );
}

Future<void> showPayment(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(430, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(theme: IronBookMobileTheme.theme, home: child),
  );
  await tester.pumpAndSettle();
}

Widget checkoutScreen(PaymentFixture f) => MembershipCheckoutScreen(
  centerId: 3,
  centerName: 'Ilidza',
  plan: const MembershipPlan(id: 4, name: 'Monthly', monthlyPrice: 65.5),
  centerApiService: f.api,
  stripeClient: f.stripe,
);

Future<void> tapLabel(WidgetTester tester, String label) async {
  final target = find.text(label).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'Card checkout parses IDs and SDK data without treating pending as paid',
    () {
      final result = MembershipCheckoutResult.fromJson(cardCheckout());
      expect(result.membershipId, 12);
      expect(result.cardPayment!.clientSecret, 'pi_fixture_secret_fixture');
      expect(result.cardPayment!.paymentIntentId, 'pi_fixture');
      expect(result.cardPayment!.currency, 'eur');
      expect(result.cardPayment!.status, 'requires_payment_method');
      expect(result.isCardCompleted, isFalse);
    },
  );

  for (final nullable in [false, true]) {
    test('Optional Stripe details are safe (explicit null=$nullable)', () {
      final json = cardCheckout(details: false);
      if (nullable) json['cardPayment'] = null;
      expect(MembershipCheckoutResult.fromJson(json).cardPayment, isNull);
    });
  }
  test('Malformed Stripe details fail safely', () {
    expect(
      () => MembershipCheckoutResult.fromJson({
        ...cardCheckout(),
        'cardPayment': {'clientSecret': 1},
      }),
      throwsFormatException,
    );
  });
  test(
    'Missing publishable key fails without platform initialization',
    () async {
      await expectLater(
        NativeStripePaymentClient(publishableKey: '').ensureReady(),
        throwsA(
          isA<CardPaymentException>().having(
            (e) => e.message,
            'message',
            contains('STRIPE_PUBLISHABLE_KEY'),
          ),
        ),
      );
    },
  );
  test(
    'Secret/live keys are not accepted as sandbox publishable configuration',
    () async {
      for (final key in ['sk_test_fixture', 'pk_live_fixture']) {
        await expectLater(
          NativeStripePaymentClient(publishableKey: key).ensureReady(),
          throwsA(isA<CardPaymentException>()),
        );
      }
    },
  );

  for (final action in ['card-payment', 'complete-card']) {
    test('$action uses exact bodyless authenticated route', () async {
      final f = PaymentFixture();
      if (action == 'card-payment') {
        await f.api.resumeCardPayment(12);
      } else {
        await f.api.completeCardPayment(12);
      }
      expect(f.requests.single.url.path, '/api/memberships/12/$action');
      expect(f.requests.single.method, 'POST');
      expect(f.requests.single.bodyBytes, isEmpty);
    });
    for (final token in <String?>[null, 'invalid token']) {
      test(
        '$action rejects missing/malformed token before network ($token)',
        () async {
          var calls = 0;
          final api = CenterApiService(
            apiBaseUrl: 'http://localhost',
            accessTokenProvider: FakeAccessTokenProvider(token),
            client: MockClient((_) async {
              calls++;
              return http.Response('', 200);
            }),
          );
          await expectLater(
            action == 'card-payment'
                ? api.resumeCardPayment(12)
                : api.completeCardPayment(12),
            throwsA(
              isA<CenterApiException>().having(
                (e) => e.statusCode,
                'status',
                401,
              ),
            ),
          );
          expect(calls, 0);
        },
      );
    }
    for (final status in [401, 403, 404, 409, 503]) {
      test('$action preserves HTTP $status without automatic retry', () async {
        var calls = 0;
        final tokens = FakeAccessTokenProvider();
        final api = CenterApiService(
          apiBaseUrl: 'http://localhost',
          accessTokenProvider: tokens,
          client: MockClient((_) async {
            calls++;
            return http.Response('{"message":"Safe failure."}', status);
          }),
        );
        await expectLater(
          action == 'card-payment'
              ? api.resumeCardPayment(12)
              : api.completeCardPayment(12),
          throwsA(
            isA<CenterApiException>().having(
              (e) => e.statusCode,
              'status',
              status,
            ),
          ),
        );
        expect(calls, 1);
        expect(tokens.token, 'fixture-access-token');
      });
    }
  }

  test(
    'Provider initiation failure preserves reservation identity for recovery',
    () async {
      final f = PaymentFixture()..checkoutHttp = 503;
      await expectLater(
        f.api.checkoutMembership(
          centerId: 3,
          membershipPlanId: 4,
          paymentMethod: MembershipCheckoutPaymentMethod.card,
        ),
        throwsA(
          isA<CenterApiException>()
              .having((e) => e.checkout?.membershipId, 'recoverable ID', 12)
              .having(
                (e) => e.checkout?.cardPayment,
                'no secret on error',
                isNull,
              ),
        ),
      );
    },
  );

  testWidgets(
    'Card sends selected business fields, confirms, verifies, refreshes, and opens Membership',
    (tester) async {
      final f = PaymentFixture();
      await showPayment(tester, checkoutScreen(f));
      await tapLabel(tester, 'Confirm Membership');
      expect(f.creates, 1);
      expect(f.seenMethod, 'Card');
      expect(f.stripe.secrets, ['pi_fixture_secret_fixture']);
      expect(f.completes, 1);
      expect(
        f.reads,
        2,
      ); // Preflight and authoritative post-verification refresh.
      expect(find.byType(MembershipConfirmationScreen), findsOneWidget);
      await tapLabel(tester, 'View My Membership');
      expect(find.byType(MyMembershipScreen), findsOneWidget);
      expect(f.reads, 3);
      expect(find.text('Active'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Absent Card configuration does not reserve or call Stripe', (
    tester,
  ) async {
    final f = PaymentFixture();
    f.stripe.configured = false;
    await showPayment(tester, checkoutScreen(f));
    await tapLabel(tester, 'Confirm Membership');
    expect(find.text('Card payment is not configured.'), findsOneWidget);
    expect(f.requests, isEmpty);
    expect(f.stripe.secrets, isEmpty);
  });

  for (final failure in [
    'Payment sheet closed.',
    'Card confirmation failed.',
  ]) {
    testWidgets('$failure never activates an unverified membership', (
      tester,
    ) async {
      final f = PaymentFixture()
        ..completionStatus = 'PendingCard'
        ..completionHttp = 202;
      f.stripe.failure = failure;
      await showPayment(tester, checkoutScreen(f));
      await tapLabel(tester, 'Confirm Membership');
      expect(find.byType(MembershipConfirmationScreen), findsNothing);
      expect(find.textContaining(failure), findsOneWidget);
      expect(f.active, isFalse);
      expect(f.completes, 1);
      await tapLabel(tester, 'Continue Card Payment');
      expect(f.creates, 1);
      expect(f.resumes, 1);
    });
  }

  for (final status in ['PendingCard', 'Cancelled', 'Failed']) {
    testWidgets('Backend $status remains non-success after SDK returns', (
      tester,
    ) async {
      final f = PaymentFixture()
        ..completionStatus = status
        ..completionHttp = status == 'Failed'
            ? 409
            : status == 'PendingCard'
            ? 202
            : 200;
      await showPayment(tester, checkoutScreen(f));
      await tapLabel(tester, 'Confirm Membership');
      expect(find.byType(MembershipConfirmationScreen), findsNothing);
      expect(f.active, isFalse);
      expect(f.completes, 1);
      if (status == 'Cancelled') {
        expect(find.text('Continue Card Payment'), findsNothing);
      }
    });
  }

  testWidgets(
    'My Membership pending purchase resumes without a second checkout',
    (tester) async {
      final f = PaymentFixture()..hasMembership = true;
      await showPayment(
        tester,
        MyMembershipScreen(centerApiService: f.api, stripeClient: f.stripe),
      );
      await tapLabel(tester, 'Continue Card Payment');
      expect(f.resumes, 1);
      expect(f.creates, 0);
      expect(f.completes, 1);
      expect(find.byType(MembershipConfirmationScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Checkout reuses an existing same Center/Plan pending Card membership',
    (tester) async {
      final f = PaymentFixture()..hasMembership = true;
      await showPayment(tester, checkoutScreen(f));
      await tapLabel(tester, 'Confirm Membership');
      expect(f.creates, 0);
      expect(f.resumes, 1);
    },
  );

  testWidgets(
    'Lost initiation response recovers the committed purchase instead of creating twice',
    (tester) async {
      final f = PaymentFixture()..loseCheckoutResponse = true;
      await showPayment(tester, checkoutScreen(f));
      await tapLabel(tester, 'Confirm Membership');
      expect(f.creates, 1);
      await tapLabel(tester, 'Confirm Membership');
      expect(f.creates, 1);
      expect(f.resumes, 1);
      expect(find.byType(MembershipConfirmationScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Reception is unchanged and does not initialize Stripe even without configuration',
    (tester) async {
      final f = PaymentFixture();
      f.stripe.configured = false;
      await showPayment(tester, checkoutScreen(f));
      await tapLabel(tester, 'Pay at Reception');
      await tapLabel(tester, 'Confirm Membership');
      expect(f.stripe.readyCalls, 0);
      expect(f.stripe.secrets, isEmpty);
      expect(f.completes, 0);
      expect(f.seenMethod, 'Reception');
      expect(
        find.text(
          'Your membership is pending until reception payment is completed.',
        ),
        findsOneWidget,
      );
      await tapLabel(tester, 'View My Membership');
      expect(find.byType(MyMembershipScreen), findsOneWidget);
      expect(find.text('Pending'), findsWidgets);
    },
  );

  testWidgets(
    'Rapid taps cannot create duplicate checkout or PaymentSheet navigation',
    (tester) async {
      final f = PaymentFixture();
      f.stripe.confirmation = Completer<void>();
      await showPayment(tester, checkoutScreen(f));
      final button = find.text('Confirm Membership');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(f.creates, 1);
      expect(f.stripe.secrets.length, 1);
      expect(find.byType(CardPaymentScreen), findsOneWidget);
      f.stripe.confirmation!.complete();
      await tester.pumpAndSettle();
      expect(f.completes, 1);
    },
  );

  testWidgets(
    'Verified payment refresh failure retries the read without another charge',
    (tester) async {
      final f = PaymentFixture()..failMembershipRefresh = true;
      await showPayment(tester, checkoutScreen(f));
      await tapLabel(tester, 'Confirm Membership');
      expect(find.textContaining('Payment is verified'), findsOneWidget);
      expect(find.byType(MembershipConfirmationScreen), findsNothing);
      f.failMembershipRefresh = false;
      await tapLabel(tester, 'Reload Membership');
      expect(f.completes, 1);
      expect(f.stripe.secrets.length, 1);
      expect(find.byType(MembershipConfirmationScreen), findsOneWidget);
    },
  );

  testWidgets('Disposal during Stripe does not navigate or complete payment', (
    tester,
  ) async {
    final f = PaymentFixture();
    f.stripe.confirmation = Completer<void>();
    await showPayment(tester, checkoutScreen(f));
    await tester.tap(find.text('Confirm Membership'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(
      MaterialApp(key: UniqueKey(), home: const SizedBox()),
    );
    f.stripe.confirmation!.complete();
    await tester.pumpAndSettle();
    expect(f.completes, 0);
    expect(tester.takeException(), isNull);
  });
}
