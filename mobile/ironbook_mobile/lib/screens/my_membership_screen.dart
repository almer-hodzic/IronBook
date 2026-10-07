import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/my_membership.dart';
import '../services/center_api_service.dart';
import '../theme/ironbook_mobile_colors.dart';
import '../widgets/ironbook_mobile_components.dart';
import 'membership_plans_screen.dart';

class MyMembershipScreen extends StatefulWidget {
  const MyMembershipScreen({
    super.key,
    required this.centerApiService,
    this.initialCenterId,
    this.initialCenterName,
  });

  final CenterApiService centerApiService;
  final int? initialCenterId;
  final String? initialCenterName;

  @override
  State<MyMembershipScreen> createState() => _MyMembershipScreenState();
}

class _MyMembershipScreenState extends State<MyMembershipScreen> {
  late Future<MyMembership?> _membershipFuture;

  @override
  void initState() {
    super.initState();
    _membershipFuture = widget.centerApiService.getMyMembership();
  }

  void _retry() {
    setState(() {
      _membershipFuture = widget.centerApiService.getMyMembership();
    });
  }

  void _openMembershipOptions(MyMembership membership) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MembershipPlansScreen(
          centerId: membership.centerId,
          centerName: membership.centerName,
          centerApiService: widget.centerApiService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IronBookMobileShell(
      bottomNav: const IronBookBottomNav(activeLabel: 'Profile'),
      children: [
        FutureBuilder<MyMembership?>(
          future: _membershipFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _MembershipScaffold(
                title: 'My Membership',
                subtitle: 'Loading your membership details.',
                onBack: () => Navigator.of(context).pop(),
                trailing: const IronBookTag(label: 'Loading'),
                children: const [_MembershipLoading()],
              );
            }

            if (snapshot.hasError) {
              return _MembershipScaffold(
                title: 'My Membership',
                subtitle:
                    widget.initialCenterName ??
                    'Review your active membership in the IronBook chain.',
                onBack: () => Navigator.of(context).pop(),
                trailing: const IronBookTag(
                  label: 'Unavailable',
                  variant: IronBookTagVariant.warning,
                ),
                children: [
                  _MembershipMessage(
                    icon: Icons.cloud_off_outlined,
                    title: 'Membership could not be loaded',
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

            final membership = snapshot.data;
            if (membership == null) {
              return _MembershipScaffold(
                title: 'My Membership',
                subtitle:
                    widget.initialCenterName ??
                    'Review your active membership in the IronBook chain.',
                onBack: () => Navigator.of(context).pop(),
                trailing: const IronBookTag(label: 'No Plan'),
                children: [
                  _MembershipMessage(
                    icon: Icons.card_membership_outlined,
                    title: 'No current membership',
                    message: 'There is no active or pending membership for the development member yet.',
                    action:
                        widget.initialCenterId != null &&
                            widget.initialCenterName != null
                        ? IronBookMobileButton.primary(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (context) => MembershipPlansScreen(
                                    centerId: widget.initialCenterId!,
                                    centerName: widget.initialCenterName!,
                                    centerApiService: widget.centerApiService,
                                  ),
                                ),
                              );
                            },
                            label: 'View Membership Options',
                            icon: Icons.event_available_outlined,
                          )
                        : null,
                  ),
                ],
              );
            }

            return _MembershipScaffold(
              title: 'My Membership',
              subtitle:
                  'Review your membership at ${membership.centerName} in the IronBook chain.',
              onBack: () => Navigator.of(context).pop(),
              trailing: IronBookTag(
                label: membership.isActive
                    ? 'Active'
                    : membership.isPending
                    ? 'Pending'
                    : membership.membershipStatus,
                variant: membership.hasQrAccess
                    ? IronBookTagVariant.success
                    : IronBookTagVariant.warning,
              ),
              children: [
                _MembershipSummaryCard(membership: membership),
                _EntryPassCard(membership: membership),
                if (membership.hasQrAccess)
                  const _IncludedBenefitsCard()
                else
                  _UnavailableAccessCard(membership: membership),
                _BillingTermsCard(membership: membership),
                IronBookMobileButton.primary(
                  onPressed: () => _openMembershipOptions(membership),
                  label: 'Manage Plan',
                  icon: Icons.tune,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MembershipScaffold extends StatelessWidget {
  const _MembershipScaffold({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.trailing,
    required this.children,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final Widget trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IronBookMobileHeader(
          title: title,
          subtitle: subtitle,
          onBack: onBack,
          trailing: trailing,
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

class _MembershipSummaryCard extends StatelessWidget {
  const _MembershipSummaryCard({required this.membership});

  final MyMembership membership;

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      membership.planName,
                      style: const TextStyle(
                        color: IronBookMobileColors.slate800,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (membership.paymentAmount != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'EUR ${membership.paymentAmount!.toStringAsFixed(2)} / month',
                        style: const TextStyle(
                          color: IronBookMobileColors.slate500,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const IronBookTag(label: 'Center Plan'),
            ],
          ),
          const SizedBox(height: 12),
          _DetailLine(label: 'Center', value: membership.centerName),
          _DetailLine(
            label: 'Status',
            value: _formatCamel(membership.membershipStatus),
          ),
          _DetailLine(
            label: 'Valid From',
            value: _formatDate(membership.startDate),
          ),
          _DetailLine(
            label: 'Valid Until',
            value: _formatDate(membership.endDate),
          ),
        ],
      ),
    );
  }
}

class _EntryPassCard extends StatelessWidget {
  const _EntryPassCard({required this.membership});

  final MyMembership membership;

  @override
  Widget build(BuildContext context) {
    final token = membership.qrAccessToken;

    return IronBookMobileSection(
      muted: !membership.hasQrAccess,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Center Entry Pass',
                  style: TextStyle(
                    color: IronBookMobileColors.slate800,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IronBookTag(
                label: membership.hasQrAccess
                    ? 'Entry Enabled'
                    : 'Entry Disabled',
                variant: membership.hasQrAccess
                    ? IronBookTagVariant.success
                    : IronBookTagVariant.warning,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (membership.hasQrAccess && token != null)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: IronBookMobileColors.slate200),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Show this code at center entry',
                                style: TextStyle(
                                  color: IronBookMobileColors.slate700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Access is validated by the IronBook API.',
                                style: TextStyle(
                                  color: IronBookMobileColors.slate500,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.qr_code_2,
                          color: IronBookMobileColors.slate600,
                          size: 26,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: IronBookMobileColors.surfaceMuted,
                        border: Border.all(
                          color: IronBookMobileColors.slate200,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: QrImageView(
                          data: token,
                          version: QrVersions.auto,
                          size: 148,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: IronBookMobileColors.slate900,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: IronBookMobileColors.slate900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'IB-ENTRY-${membership.membershipId}-${membership.centerId}',
                      style: const TextStyle(
                        color: IronBookMobileColors.slate500,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: IronBookMobileColors.rose100),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_outlined,
                      color: IronBookMobileColors.rose700,
                      size: 20,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        membership.accessMessage,
                        style: const TextStyle(
                          color: IronBookMobileColors.slate600,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IncludedBenefitsCard extends StatelessWidget {
  const _IncludedBenefitsCard();

  @override
  Widget build(BuildContext context) {
    return const IronBookMobileSection(
      muted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Included Benefits',
            style: TextStyle(
              color: IronBookMobileColors.slate800,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 10),
          _BenefitLine('Open gym access within your plan hours'),
          SizedBox(height: 6),
          _BenefitLine('Center entry validation through the real API'),
          SizedBox(height: 6),
          _BenefitLine('Membership terms apply to every center visit'),
        ],
      ),
    );
  }
}

class _UnavailableAccessCard extends StatelessWidget {
  const _UnavailableAccessCard({required this.membership});

  final MyMembership membership;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      muted: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lock_outline,
            color: IronBookMobileColors.slate600,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              membership.isPending
                  ? 'This membership is pending reception payment. QR access will appear after it becomes active.'
                  : 'This membership cannot currently grant center access.',
              style: const TextStyle(
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

class _BillingTermsCard extends StatelessWidget {
  const _BillingTermsCard({required this.membership});

  final MyMembership membership;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Billing & Terms',
            style: TextStyle(
              color: IronBookMobileColors.slate800,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          _TermLine(
            icon: Icons.payments_outlined,
            text: membership.paymentStatus == null
                ? 'Payment information is not available.'
                : 'Payment status: ${_formatCamel(membership.paymentStatus!)}',
          ),
          const SizedBox(height: 7),
          _TermLine(
            icon: Icons.calendar_month_outlined,
            text:
                'Current monthly period ends ${_formatDate(membership.endDate)}.',
          ),
          const SizedBox(height: 7),
          const _TermLine(
            icon: Icons.verified_user_outlined,
            text: 'Center rules and membership terms apply to each check-in.',
          ),
        ],
      ),
    );
  }
}

class _BenefitLine extends StatelessWidget {
  const _BenefitLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.check_circle_outline,
          color: IronBookMobileColors.emerald700,
          size: 16,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
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

class _TermLine extends StatelessWidget {
  const _TermLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: IronBookMobileColors.slate500, size: 16),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
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

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: IronBookMobileColors.slate500,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: IronBookMobileColors.slate700,
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

class _MembershipLoading extends StatelessWidget {
  const _MembershipLoading();

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
            'Loading membership...',
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

class _MembershipMessage extends StatelessWidget {
  const _MembershipMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      muted: true,
      child: Column(
        children: [
          Icon(icon, color: IronBookMobileColors.slate600, size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: IronBookMobileColors.slate800,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: IronBookMobileColors.slate500,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}

String _formatCamel(String value) {
  return value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
}
