import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../app_config.dart';

abstract interface class StripePaymentClient {
  Future<void> ensureReady();
  Future<void> confirmPayment(
    String clientSecret, {
    required bool Function() canPresent,
  });
}

class CardPaymentException implements Exception {
  const CardPaymentException(this.message);
  final String message;
}

/// Only the native PaymentSheet handles card details. Initialization is lazy so
/// missing sandbox configuration never prevents startup or Reception checkout.
class NativeStripePaymentClient implements StripePaymentClient {
  NativeStripePaymentClient({String? publishableKey})
    : _publishableKey = publishableKey ?? AppConfig.stripePublishableKey;

  final String _publishableKey;
  bool _ready = false;

  @override
  Future<void> ensureReady() async {
    if (!RegExp(r'^pk_test_[A-Za-z0-9]+$').hasMatch(_publishableKey)) {
      throw const CardPaymentException(
        'Card payment is not configured. Supply STRIPE_PUBLISHABLE_KEY with a sandbox publishable key. You can still pay at reception.',
      );
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const CardPaymentException(
        'Card payment is supported on Android in this version.',
      );
    }
    if (_ready) return;
    try {
      Stripe.publishableKey = _publishableKey;
      await Stripe.instance.applySettings();
      _ready = true;
    } catch (_) {
      throw const CardPaymentException(
        'Card payment could not start. Please try again.',
      );
    }
  }

  @override
  Future<void> confirmPayment(
    String clientSecret, {
    required bool Function() canPresent,
  }) async {
    await ensureReady();
    if (!canPresent()) return;
    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Iron Core Fitness',
        ),
      );
      // Native preparation is asynchronous too. Do not open a sheet after the
      // owning screen has been removed while initialization was in progress.
      if (canPresent()) await Stripe.instance.presentPaymentSheet();
    } on StripeException catch (error) {
      throw CardPaymentException(
        error.error.code == FailureCode.Canceled
            ? 'Payment sheet closed. Your payment will be checked before continuing.'
            : 'Card confirmation failed. Your payment will be checked before continuing.',
      );
    } catch (_) {
      throw const CardPaymentException(
        'Card confirmation was interrupted. Your payment will be checked before continuing.',
      );
    }
  }
}
