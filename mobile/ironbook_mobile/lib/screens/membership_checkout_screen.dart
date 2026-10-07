import 'package:flutter/material.dart';

import '../models/membership_checkout.dart';
import '../models/membership_plan.dart';
import '../services/center_api_service.dart';
import '../theme/ironbook_mobile_colors.dart';
import '../widgets/ironbook_mobile_components.dart';
import 'membership_confirmation_screen.dart';

class MembershipCheckoutScreen extends StatefulWidget {
  const MembershipCheckoutScreen({
    super.key,
    required this.centerId,
    required this.centerName,
    required this.plan,
    required this.centerApiService,
  });

  final int centerId;
  final String centerName;
  final MembershipPlan plan;
  final CenterApiService centerApiService;

  @override
  State<MembershipCheckoutScreen> createState() =>
      _MembershipCheckoutScreenState();
}

class _MembershipCheckoutScreenState extends State<MembershipCheckoutScreen> {
  MembershipCheckoutPaymentMethod _paymentMethod =
      MembershipCheckoutPaymentMethod.card;
  bool _isSubmitting = false;

  Future<void> _confirmMembership() async {
    if (_isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final result = await widget.centerApiService.checkoutMembership(
        centerId: widget.centerId,
        membershipPlanId: widget.plan.id,
        paymentMethod: _paymentMethod,
      );

      if (!mounted) {
        return;
      }

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => MembershipConfirmationScreen(
            checkout: result,
            centerApiService: widget.centerApiService,
          ),
        ),
      );
    } on CenterApiException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IronBookMobileShell(
      bottomNav: const IronBookBottomNav(),
      children: [
        IronBookMobileHeader(
          title: 'Review & Payment',
          subtitle: widget.centerName,
          onBack: () => Navigator.of(context).pop(),
          trailing: const IronBookTag(label: 'Checkout'),
        ),
        _SummarySection(plan: widget.plan, centerName: widget.centerName),
        _PaymentMethodSection(
          selected: _paymentMethod,
          onChanged: (method) {
            setState(() {
              _paymentMethod = method;
            });
          },
        ),
        const _TermsSection(),
        IronBookMobileButton.primary(
          onPressed: _isSubmitting ? null : _confirmMembership,
          label: _isSubmitting ? 'Confirming...' : 'Confirm Membership',
          icon: _isSubmitting ? Icons.hourglass_empty : Icons.lock_outline,
        ),
      ],
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.plan, required this.centerName});

  final MembershipPlan plan;
  final String centerName;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.receipt_long_outlined,
            title: 'Summary',
          ),
          const SizedBox(height: 12),
          _SummaryRow(label: 'Membership Plan', value: plan.name),
          _SummaryRow(label: 'Center', value: centerName),
          const _SummaryRow(label: 'Request Type', value: 'Monthly membership'),
          _SummaryRow(
            label: 'Estimated Plan Cost',
            value: 'EUR ${plan.monthlyPrice.toStringAsFixed(2)}',
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodSection extends StatelessWidget {
  const _PaymentMethodSection({
    required this.selected,
    required this.onChanged,
  });

  final MembershipCheckoutPaymentMethod selected;
  final ValueChanged<MembershipCheckoutPaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.payments_outlined,
            title: 'Payment Method',
          ),
          const SizedBox(height: 12),
          _PaymentMethodTile(
            method: MembershipCheckoutPaymentMethod.card,
            selected: selected == MembershipCheckoutPaymentMethod.card,
            icon: Icons.credit_card,
            description: 'Record card payment now.',
            onTap: onChanged,
          ),
          const SizedBox(height: 9),
          _PaymentMethodTile(
            method: MembershipCheckoutPaymentMethod.reception,
            selected: selected == MembershipCheckoutPaymentMethod.reception,
            icon: Icons.account_balance_outlined,
            description: 'Reserve membership and pay at the gym reception.',
            onTap: onChanged,
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.method,
    required this.selected,
    required this.icon,
    required this.description,
    required this.onTap,
  });

  final MembershipCheckoutPaymentMethod method;
  final bool selected;
  final IconData icon;
  final String description;
  final ValueChanged<MembershipCheckoutPaymentMethod> onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onTap(method),
        child: Ink(
          decoration: BoxDecoration(
            color: selected
                ? IronBookMobileColors.amber100.withValues(alpha: 0.55)
                : IronBookMobileColors.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? IronBookMobileColors.amber700
                  : IronBookMobileColors.slate200,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected
                      ? IronBookMobileColors.amber700
                      : IronBookMobileColors.slate600,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        method.label,
                        style: const TextStyle(
                          color: IronBookMobileColors.slate800,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: const TextStyle(
                          color: IronBookMobileColors.slate500,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? IronBookMobileColors.amber700
                      : IronBookMobileColors.slate400,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TermsSection extends StatelessWidget {
  const _TermsSection();

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      muted: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(
            Icons.verified_user_outlined,
            color: IronBookMobileColors.slate600,
            size: 18,
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'The selected method is recorded by IronBook. No external payment gateway or card details are used.',
              style: TextStyle(
                color: IronBookMobileColors.slate600,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: IronBookMobileColors.slate700, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: IronBookMobileColors.slate800,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: IronBookMobileColors.slate500,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: IronBookMobileColors.slate800,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
