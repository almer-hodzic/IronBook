import 'package:flutter/material.dart';

import '../models/center.dart';
import '../services/center_api_service.dart';
import '../theme/ironbook_mobile_colors.dart';
import '../widgets/ironbook_mobile_components.dart';
import 'center_details_screen.dart';
import 'trainer_dashboard_screen.dart';

class CenterListScreen extends StatefulWidget {
  const CenterListScreen({super.key, required this.centerApiService});

  final CenterApiService centerApiService;

  @override
  State<CenterListScreen> createState() => _CenterListScreenState();
}

class _CenterListScreenState extends State<CenterListScreen> {
  late Future<List<FitnessCenter>> _centersFuture;
  final _searchController = TextEditingController();
  int? _selectedCenterId;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _centersFuture = widget.centerApiService.getCenters();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _centersFuture = widget.centerApiService.getCenters();
    });
  }

  Future<void> _openCenter(FitnessCenter center) async {
    setState(() {
      _selectedCenterId = center.id;
    });

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CenterDetailsScreen(
          centerId: center.id,
          initialName: center.name,
          centerApiService: widget.centerApiService,
        ),
      ),
    );
  }

  void _openTrainerDashboard() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TrainerDashboardScreen(
          centerApiService: widget.centerApiService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IronBookMobileShell(
      bottomNav: IronBookBottomNav(onDashboardTap: _openTrainerDashboard),
      children: [
        IronBookMobileHeader(
          title: 'Choose Your Center',
          subtitle: 'Pick your active location in the IronBook center chain.',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconBadgeButton(
                icon: Icons.notifications_none,
                dot: true,
                onPressed: null,
              ),
              const SizedBox(width: 8),
              const _AvatarBadge(),
            ],
          ),
        ),
        _SearchField(
          controller: _searchController,
          onChanged: (value) {
            setState(() {
              _searchQuery = value.trim().toLowerCase();
            });
          },
        ),
        const _MemberAccessCard(),
        FutureBuilder<List<FitnessCenter>>(
          future: _centersFuture,
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

            final centers = snapshot.data ?? const <FitnessCenter>[];
            final filteredCenters = _filterCenters(centers);

            if (centers.isEmpty) {
              return _StateCard.empty(
                title: 'No active centers',
                message:
                    'There are no active IronBook centers available right now.',
                onRetry: _retry,
              );
            }

            return _CentersSection(
              centers: filteredCenters,
              totalCount: centers.length,
              selectedCenterId: _selectedCenterId,
              onSelect: _openCenter,
              onClearSearch: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                });
              },
            );
          },
        ),
        const _ContinueHintCard(),
      ],
    );
  }

  List<FitnessCenter> _filterCenters(List<FitnessCenter> centers) {
    if (_searchQuery.isEmpty) {
      return centers;
    }

    return centers
        .where((center) {
          return '${center.name} ${center.location}'.toLowerCase().contains(
            _searchQuery,
          );
        })
        .toList(growable: false);
  }
}

class _IconBadgeButton extends StatelessWidget {
  const _IconBadgeButton({
    required this.icon,
    this.dot = false,
    this.onPressed,
  });

  final IconData icon;
  final bool dot;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              side: const BorderSide(color: IronBookMobileColors.slate200),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: Colors.white,
              foregroundColor: IronBookMobileColors.slate500,
              disabledForegroundColor: IronBookMobileColors.slate500,
            ),
            child: Icon(icon, size: 18),
          ),
        ),
        if (dot)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: IronBookMobileColors.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: IronBookMobileColors.slate900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IronBookMobileColors.slate900),
      ),
      child: const Text(
        'AL',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: 'Search centers or neighborhoods',
        hintStyle: const TextStyle(
          color: IronBookMobileColors.slate500,
          fontSize: 13,
        ),
        prefixIcon: const Icon(
          Icons.search,
          color: IronBookMobileColors.slate400,
          size: 20,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: IronBookMobileColors.slate200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: IronBookMobileColors.slate300),
        ),
      ),
    );
  }
}

class _MemberAccessCard extends StatelessWidget {
  const _MemberAccessCard();

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      muted: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IronBookTag(label: 'Member Access'),
                SizedBox(height: 8),
                Text(
                  'Active center selection controls pricing and available classes.',
                  style: TextStyle(
                    color: IronBookMobileColors.slate700,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'You can switch centers any time from this screen.',
                  style: TextStyle(
                    color: IronBookMobileColors.slate500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(
            Icons.verified_user_outlined,
            color: IronBookMobileColors.slate600,
            size: 22,
          ),
        ],
      ),
    );
  }
}

class _CentersSection extends StatelessWidget {
  const _CentersSection({
    required this.centers,
    required this.totalCount,
    required this.selectedCenterId,
    required this.onSelect,
    required this.onClearSearch,
  });

  final List<FitnessCenter> centers;
  final int totalCount;
  final int? selectedCenterId;
  final ValueChanged<FitnessCenter> onSelect;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available Centers',
                    style: TextStyle(
                      color: IronBookMobileColors.slate800,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Tap a center to continue',
                    style: TextStyle(
                      color: IronBookMobileColors.slate500,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IronBookTag(label: '$totalCount locations'),
          ],
        ),
        const SizedBox(height: 10),
        if (centers.isEmpty)
          _StateCard.empty(
            title: 'No matching centers',
            message: 'No centers matched your search.',
            onRetry: onClearSearch,
            actionLabel: 'Clear Search',
          )
        else
          for (final center in centers) ...[
            _CenterCard(
              center: center,
              selected: center.id == selectedCenterId,
              onTap: () => onSelect(center),
            ),
            if (center != centers.last) const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _CenterCard extends StatelessWidget {
  const _CenterCard({
    required this.center,
    required this.selected,
    required this.onTap,
  });

  final FitnessCenter center;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: selected
                ? IronBookMobileColors.amber100.withValues(alpha: 0.55)
                : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? IronBookMobileColors.accent
                  : IronBookMobileColors.slate200,
            ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? IronBookMobileColors.accent.withValues(alpha: 0.16)
                    : IronBookMobileColors.slate900.withValues(alpha: 0.05),
                blurRadius: selected ? 24 : 14,
                offset: const Offset(0, 8),
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
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: selected
                            ? IronBookMobileColors.accent.withValues(
                                alpha: 0.20,
                              )
                            : IronBookMobileColors.slate100,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.apartment,
                        size: 18,
                        color: IronBookMobileColors.slate700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            center.name,
                            style: const TextStyle(
                              color: IronBookMobileColors.slate800,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 15,
                                color: IronBookMobileColors.slate500,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  center.location,
                                  style: const TextStyle(
                                    color: IronBookMobileColors.slate500,
                                    fontSize: 12,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      const IronBookTag(
                        label: 'Active',
                        variant: IronBookTagVariant.accent,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const IronBookTag(label: 'Active Center'),
                    const Spacer(),
                    IronBookMobileButton.secondary(
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
}

class _ContinueHintCard extends StatelessWidget {
  const _ContinueHintCard();

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      muted: true,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: IronBookMobileColors.slate200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 18,
              color: IronBookMobileColors.slate700,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ready to Continue',
                  style: TextStyle(
                    color: IronBookMobileColors.slate700,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Open a center to review its available details.',
                  style: TextStyle(
                    color: IronBookMobileColors.slate500,
                    fontSize: 12,
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

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
    this.actionLabel = 'Retry',
  }) : loading = false;

  const _StateCard.loading()
    : icon = Icons.hourglass_empty,
      title = 'Loading centers',
      message = 'Please wait while centers are loaded.',
      onRetry = null,
      actionLabel = 'Retry',
      loading = true;

  factory _StateCard.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return _StateCard(
      icon: Icons.cloud_off_outlined,
      title: 'Centers could not be loaded',
      message: message,
      onRetry: onRetry,
    );
  }

  factory _StateCard.empty({
    required String title,
    required String message,
    required VoidCallback onRetry,
    String actionLabel = 'Refresh',
  }) {
    return _StateCard(
      icon: Icons.location_off_outlined,
      title: title,
      message: message,
      onRetry: onRetry,
      actionLabel: actionLabel,
    );
  }

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String actionLabel;
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
              label: actionLabel,
              icon: Icons.refresh,
            ),
          ],
        ],
      ),
    );
  }
}
