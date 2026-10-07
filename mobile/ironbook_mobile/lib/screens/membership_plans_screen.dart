import 'package:flutter/material.dart';

import '../models/membership_plan.dart';
import '../services/center_api_service.dart';
import '../theme/ironbook_mobile_colors.dart';
import '../widgets/ironbook_mobile_components.dart';
import 'membership_plan_details_screen.dart';

class MembershipPlansScreen extends StatefulWidget {
  const MembershipPlansScreen({
    super.key,
    required this.centerId,
    required this.centerName,
    required this.centerApiService,
  });

  final int centerId;
  final String centerName;
  final CenterApiService centerApiService;

  @override
  State<MembershipPlansScreen> createState() => _MembershipPlansScreenState();
}

class _MembershipPlansScreenState extends State<MembershipPlansScreen> {
  late Future<List<MembershipPlan>> _plansFuture;

  @override
  void initState() {
    super.initState();
    _plansFuture = widget.centerApiService.getMembershipPlansForCenter(
      widget.centerId,
    );
  }

  void _retry() {
    setState(() {
      _plansFuture = widget.centerApiService.getMembershipPlansForCenter(
        widget.centerId,
      );
    });
  }

  Future<void> _openPlan(MembershipPlan plan) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MembershipPlanDetailsScreen(
          centerId: widget.centerId,
          centerName: widget.centerName,
          planId: plan.id,
          initialName: plan.name,
          centerApiService: widget.centerApiService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IronBookMobileShell(
      bottomNav: const IronBookBottomNav(),
      children: [
        IronBookMobileHeader(
          title: 'Membership Options',
          subtitle:
              'Choose the best fit for training at ${widget.centerName}.',
          onBack: () => Navigator.of(context).pop(),
          trailing: const IronBookTag(label: 'Center Plans'),
        ),
        const _AccessInfoCard(),
        FutureBuilder<List<MembershipPlan>>(
          future: _plansFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _StateCard.loading();
            }

            if (snapshot.hasError) {
              return _StateCard.error(
                message: snapshot.error.toString(),
                onRetry: _retry,
              );
            }

            final plans = snapshot.data ?? const <MembershipPlan>[];
            if (plans.isEmpty) {
              return _StateCard.empty(onRetry: _retry);
            }

            return Column(
              children: [
                for (final plan in plans) ...[
                  _PlanCard(plan: plan, onTap: () => _openPlan(plan)),
                  if (plan != plans.last) const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
        IronBookMobileSection(
          muted: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Icon(
                Icons.lock_outline,
                color: IronBookMobileColors.slate500,
                size: 18,
              ),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Purchase, payment, and active membership QR are unavailable until their real backend features are implemented.',
                  style: TextStyle(
                    color: IronBookMobileColors.slate500,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccessInfoCard extends StatelessWidget {
  const _AccessInfoCard();

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
            size: 20,
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Your active center filters available membership packages, access terms, and future class availability.',
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

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onTap});

  final MembershipPlan plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final benefits = plan.benefitItems.take(3).toList(growable: false);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: IronBookMobileColors.slate200),
            boxShadow: [
              BoxShadow(
                color: IronBookMobileColors.slate900.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.name,
                            style: const TextStyle(
                              color: IronBookMobileColors.slate800,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatPrice(plan.monthlyPrice),
                            style: const TextStyle(
                              color: IronBookMobileColors.slate900,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const IronBookTag(label: 'Center Plan'),
                  ],
                ),
                if (_hasText(plan.description)) ...[
                  const SizedBox(height: 9),
                  Text(
                    plan.description!.trim(),
                    style: const TextStyle(
                      color: IronBookMobileColors.slate600,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
                if (benefits.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final benefit in benefits) ...[
                    _BenefitLine(benefit),
                    if (benefit != benefits.last) const SizedBox(height: 5),
                  ],
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    const IronBookTag(
                      label: 'Active',
                      variant: IronBookTagVariant.success,
                    ),
                    const Spacer(),
                    IronBookMobileButton.primary(
                      onPressed: onTap,
                      label: 'View Details',
                      icon: Icons.arrow_forward,
                      compact: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatPrice(double price) => 'EUR ${price.toStringAsFixed(2)} / month';

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
}

class _BenefitLine extends StatelessWidget {
  const _BenefitLine(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.check_circle_outline,
          color: IronBookMobileColors.slate500,
          size: 16,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: IronBookMobileColors.slate600,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  }) : loading = false;

  const _StateCard.loading()
    : icon = Icons.hourglass_empty,
      title = 'Loading membership plans',
      message = 'Please wait while center plans are loaded.',
      onRetry = null,
      loading = true;

  factory _StateCard.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _StateCard(
      icon: Icons.cloud_off_outlined,
      title: 'Membership plans could not be loaded',
      message: message,
      onRetry: onRetry,
    );
  }

  factory _StateCard.empty({required VoidCallback onRetry}) {
    return _StateCard(
      icon: Icons.event_available_outlined,
      title: 'No active plans for this center',
      message: 'This center has no active membership plans assigned yet.',
      onRetry: onRetry,
    );
  }

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      muted: true,
      child: Column(
        children: [
          if (loading)
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          else
            Icon(icon, color: IronBookMobileColors.slate600, size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: IronBookMobileColors.slate800,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: IronBookMobileColors.slate500,
              fontSize: 12,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            IronBookMobileButton.primary(
              onPressed: onRetry,
              label: 'Retry',
              icon: Icons.refresh,
            ),
          ],
        ],
      ),
    );
  }
}
