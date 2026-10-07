import 'package:flutter/material.dart';

import '../models/membership_checkout.dart';
import '../services/center_api_service.dart';
import '../theme/ironbook_mobile_colors.dart';
import '../widgets/ironbook_mobile_components.dart';
import 'my_membership_screen.dart';

class MembershipConfirmationScreen extends StatelessWidget {
  const MembershipConfirmationScreen({
    super.key,
    required this.checkout,
    required this.centerApiService,
  });

  final MembershipCheckoutResult checkout;
  final CenterApiService centerApiService;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileShell(
      bottomNav: const IronBookBottomNav(),
      children: [
        IronBookMobileHeader(
          title: 'Membership Confirmed',
          subtitle: checkout.centerName,
          onBack: () => Navigator.of(context).pop(),
          trailing: IronBookTag(
            label: checkout.membershipStatus,
            variant: checkout.membershipStatus == 'Active'
                ? IronBookTagVariant.success
                : IronBookTagVariant.warning,
          ),
        ),
        IronBookMobileSection(
          child: Column(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: IronBookMobileColors.emerald700,
                size: 44,
              ),
              const SizedBox(height: 12),
              const Text(
                'Confirmation Successful',
                style: TextStyle(
                  color: IronBookMobileColors.slate800,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                checkout.paymentStatus == 'Completed'
                    ? 'Your membership is active for this center.'
                    : 'Your membership is pending until reception payment is completed.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: IronBookMobileColors.slate500,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        IronBookMobileSection(
          muted: true,
          child: Column(
            children: [
              _DetailRow(label: 'Membership Plan', value: checkout.planName),
              _DetailRow(label: 'Center', value: checkout.centerName),
              _DetailRow(
                label: 'Payment Method',
                value: _formatCamel(checkout.paymentMethod),
              ),
              _DetailRow(
                label: 'Payment Status',
                value: _formatCamel(checkout.paymentStatus),
              ),
              _DetailRow(
                label: 'Amount',
                value: 'EUR ${checkout.amount.toStringAsFixed(2)}',
              ),
              _DetailRow(
                label: 'Valid From',
                value: _formatDate(checkout.startDate),
              ),
              _DetailRow(
                label: 'Valid Until',
                value: _formatDate(checkout.endDate),
              ),
            ],
          ),
        ),
        IronBookMobileButton.primary(
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (context) => MyMembershipScreen(
                  centerApiService: centerApiService,
                  initialCenterId: checkout.centerId,
                  initialCenterName: checkout.centerName,
                ),
              ),
            );
          },
          label: 'View My Membership',
          icon: Icons.qr_code_2,
        ),
        IronBookMobileButton.secondary(
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          label: 'Back to Home',
          icon: Icons.home_outlined,
        ),
      ],
    );
  }

  static String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }

  static String _formatCamel(String value) {
    return value.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

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
