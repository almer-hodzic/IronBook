import 'package:flutter/material.dart';

import '../models/membership_checkout.dart';
import '../services/center_api_service.dart';
import '../services/stripe_payment_client.dart';
import '../widgets/ironbook_mobile_components.dart';
import 'membership_confirmation_screen.dart';
import 'my_membership_screen.dart';

/// A small continuation step shared by checkout and an existing pending purchase.
class CardPaymentScreen extends StatefulWidget {
  const CardPaymentScreen({
    super.key,
    required this.membershipId,
    required this.centerApiService,
    this.initialCheckout,
    this.stripeClient,
  });

  final int membershipId;
  final CenterApiService centerApiService;
  final MembershipCheckoutResult? initialCheckout;
  final StripePaymentClient? stripeClient;

  @override
  State<CardPaymentScreen> createState() => _CardPaymentScreenState();
}

class _CardPaymentScreenState extends State<CardPaymentScreen> {
  late final StripePaymentClient _stripe =
      widget.stripeClient ?? NativeStripePaymentClient();
  bool _busy = false;
  bool _firstAttempt = true;
  bool _cancelled = false;
  String _message = 'Preparing payment...';
  MembershipCheckoutResult? _verifiedCheckout;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pay();
    });
  }

  void _phase(String text) {
    if (mounted) setState(() => _message = text);
  }

  Future<void> _finish(MembershipCheckoutResult checkout) async {
    _verifiedCheckout = checkout;
    _phase('Payment verified. Refreshing membership...');
    await widget.centerApiService.getMyMembership();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => MembershipConfirmationScreen(
          checkout: checkout,
          centerApiService: widget.centerApiService,
        ),
      ),
    );
  }

  Future<void> _pay() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = 'Preparing payment...';
    });
    try {
      if (_verifiedCheckout != null) {
        await _finish(_verifiedCheckout!);
        return;
      }
      await _stripe.ensureReady();
      if (!mounted) return;
      final checkout = _firstAttempt && widget.initialCheckout != null
          ? widget.initialCheckout!
          : await widget.centerApiService.resumeCardPayment(
              widget.membershipId,
            );
      _firstAttempt = false;
      if (!mounted) return;
      if (checkout.isCardCompleted) {
        await _finish(checkout);
        return;
      }
      if (checkout.paymentStatus == 'Cancelled') {
        _cancelled = true;
        _phase('This Card payment was cancelled. No membership was activated.');
        return;
      }
      final card = checkout.cardPayment;
      if (card == null) {
        throw const CardPaymentException(
          'Payment details are unavailable. Continue the existing payment to try again.',
        );
      }
      String? confirmationMessage;
      if (card.status != 'succeeded' && card.status != 'processing') {
        _phase('Confirm your Card payment in Stripe...');
        try {
          await _stripe.confirmPayment(
            card.clientSecret,
            canPresent: () => mounted,
          );
        } on CardPaymentException catch (error) {
          confirmationMessage = error.message;
        }
      }
      if (!mounted) return;
      _phase('Verifying payment with IronBook...');
      final verified = await widget.centerApiService.completeCardPayment(
        widget.membershipId,
      );
      if (!mounted) return;
      if (verified.isCardCompleted) {
        await _finish(verified);
      } else {
        _cancelled = verified.paymentStatus == 'Cancelled';
        _phase(
          _cancelled
              ? 'This Card payment was cancelled. No membership was activated.'
              : '${confirmationMessage == null ? '' : '$confirmationMessage '}Payment is still pending. Membership has not been activated. Continue the same payment to try again.',
        );
      }
    } on CenterApiException catch (error) {
      if (_verifiedCheckout != null) {
        _phase(
          'Payment is verified, but membership could not be reloaded. Retry the membership refresh.',
        );
      } else {
        _phase(error.message);
      }
    } on CardPaymentException catch (error) {
      _phase(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: IronBookMobileShell(
      children: [
        IronBookMobileHeader(
          title: 'Card Payment',
          subtitle: 'Membership checkout',
          onBack: _busy ? null : () => Navigator.of(context).pop(),
        ),
        IronBookMobileSection(
          child: Column(
            children: [
              if (_busy) const CircularProgressIndicator(),
              if (_busy) const SizedBox(height: 12),
              Text(_message, textAlign: TextAlign.center),
            ],
          ),
        ),
        if (!_cancelled)
          IronBookMobileButton.primary(
            onPressed: _busy ? null : _pay,
            label: _busy
                ? 'Processing...'
                : _verifiedCheckout != null
                ? 'Reload Membership'
                : 'Continue Card Payment',
          ),
        IronBookMobileButton.secondary(
          onPressed: _busy
              ? null
              : () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => MyMembershipScreen(
                        centerApiService: widget.centerApiService,
                      ),
                    ),
                  );
                },
          label: 'View My Membership',
        ),
      ],
    ),
  );
}
