import 'package:flutter/material.dart';

import '../models/membership_plan.dart';
import '../services/center_api_service.dart';
import '../theme/ironbook_mobile_colors.dart';
import '../widgets/ironbook_mobile_components.dart';

class MembershipPlanDetailsScreen extends StatefulWidget {
  const MembershipPlanDetailsScreen({
    super.key,
    required this.centerId,
    required this.centerName,
    required this.planId,
    this.initialName,
    required this.centerApiService,
  });

  final int centerId;
  final String centerName;
  final int planId;
  final String? initialName;
  final CenterApiService centerApiService;

  @override
  State<MembershipPlanDetailsScreen> createState() =>
      _MembershipPlanDetailsScreenState();
}

class _MembershipPlanDetailsScreenState
    extends State<MembershipPlanDetailsScreen> {
  late Future<MembershipPlan> _planFuture;

  @override
  void initState() {
    super.initState();
    _planFuture = widget.centerApiService.getMembershipPlanForCenter(
      widget.centerId,
      widget.planId,
    );
  }

  void _retry() {
    setState(() {
      _planFuture = widget.centerApiService.getMembershipPlanForCenter(
        widget.centerId,
        widget.planId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return IronBookMobileShell(
      bottomNav: const IronBookBottomNav(),
      children: [
        FutureBuilder<MembershipPlan>(
          future: _planFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _DetailsScaffold(
                title: widget.initialName ?? 'Membership plan',
                centerName: widget.centerName,
                children: const [_DetailsLoading()],
              );
            }

            if (snapshot.hasError) {
              return _DetailsScaffold(
                title: widget.initialName ?? 'Membership plan',
                centerName: widget.centerName,
                children: [
                  _DetailsMessage(
                    title: 'Plan details are unavailable',
                    message: snapshot.error.toString(),
                    action: IronBookMobileButton.primary(
                      onPressed: _retry,
                      label: 'Retry',
                      icon: Icons.refresh,
                    ),
                  ),
                ],
              );
            }

            final plan = snapshot.data;
            if (plan == null) {
              return _DetailsScaffold(
                title: widget.initialName ?? 'Membership plan',
                centerName: widget.centerName,
                children: const [
                  _DetailsMessage(
                    title: 'Plan details are unavailable',
                    message: 'No membership plan data was returned.',
                  ),
                ],
              );
            }

            return _DetailsScaffold(
              title: plan.name,
              centerName: widget.centerName,
              children: [
                _PlanSummary(plan: plan),
                if (_hasText(plan.description))
                  _InfoSection(
                    title: 'Description',
                    icon: Icons.description_outlined,
                    body: plan.description!.trim(),
                  ),
                if (plan.benefitItems.isNotEmpty)
                  _BenefitsSection(benefits: plan.benefitItems),
                const _UnavailableActionCard(),
              ],
            );
          },
        ),
      ],
    );
  }

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
}

class _DetailsScaffold extends StatelessWidget {
  const _DetailsScaffold({
    required this.title,
    required this.centerName,
    required this.children,
  });

  final String title;
  final String centerName;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IronBookMobileHeader(
          title: title,
          subtitle: centerName,
          onBack: () => Navigator.of(context).pop(),
          trailing: const IronBookTag(label: 'Plan Details'),
        ),
        const SizedBox(height: 10),
        ..._withSpacing(children),
      ],
    );
  }

  static List<Widget> _withSpacing(List<Widget> children) {
    final spaced = <Widget>[];
    for (var index = 0; index < children.length; index += 1) {
      if (index > 0) {
        spaced.add(const SizedBox(height: 10));
      }
      spaced.add(children[index]);
    }

    return spaced;
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.plan});

  final MembershipPlan plan;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: const TextStyle(
                    color: IronBookMobileColors.slate800,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
              const IronBookTag(
                label: 'Active',
                variant: IronBookTagVariant.success,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'EUR ${plan.monthlyPrice.toStringAsFixed(2)} / month',
            style: const TextStyle(
              color: IronBookMobileColors.slate900,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitsSection extends StatelessWidget {
  const _BenefitsSection({required this.benefits});

  final List<String> benefits;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      muted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Benefits',
            style: TextStyle(
              color: IronBookMobileColors.slate800,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          for (final benefit in benefits) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: IronBookMobileColors.emerald700,
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    benefit,
                    style: const TextStyle(
                      color: IronBookMobileColors.slate600,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            if (benefit != benefits.last) const SizedBox(height: 7),
          ],
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.title,
    required this.icon,
    required this.body,
  });

  final String title;
  final IconData icon;
  final String body;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: IronBookMobileColors.slate600, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: IronBookMobileColors.slate800,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    color: IronBookMobileColors.slate600,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnavailableActionCard extends StatelessWidget {
  const _UnavailableActionCard();

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      muted: true,
      child: Row(
        children: const [
          Icon(
            Icons.payments_outlined,
            color: IronBookMobileColors.slate500,
            size: 18,
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Review & Payment will be available after the purchase flow is implemented.',
              style: TextStyle(
                color: IronBookMobileColors.slate500,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
          IronBookTag(label: 'Later'),
        ],
      ),
    );
  }
}

class _DetailsLoading extends StatelessWidget {
  const _DetailsLoading();

  @override
  Widget build(BuildContext context) {
    return const IronBookMobileSection(
      muted: true,
      child: Column(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(height: 12),
          Text(
            'Loading membership plan...',
            style: TextStyle(
              color: IronBookMobileColors.slate600,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsMessage extends StatelessWidget {
  const _DetailsMessage({
    required this.title,
    required this.message,
    this.action,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      muted: true,
      child: Column(
        children: [
          const Icon(
            Icons.error_outline,
            color: IronBookMobileColors.slate600,
            size: 34,
          ),
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
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}
