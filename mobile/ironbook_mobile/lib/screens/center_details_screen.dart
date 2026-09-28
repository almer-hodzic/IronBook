import 'package:flutter/material.dart';

import '../models/center.dart';
import '../services/center_api_service.dart';
import '../theme/ironbook_mobile_colors.dart';
import '../widgets/ironbook_mobile_components.dart';

class CenterDetailsScreen extends StatefulWidget {
  const CenterDetailsScreen({
    super.key,
    required this.centerId,
    this.initialName,
    required this.centerApiService,
  });

  final int centerId;
  final String? initialName;
  final CenterApiService centerApiService;

  @override
  State<CenterDetailsScreen> createState() => _CenterDetailsScreenState();
}

class _CenterDetailsScreenState extends State<CenterDetailsScreen> {
  static const _galleryImages = [
    'assets/images/centers/fitness_1.jpg',
    'assets/images/centers/fitness_2.jpg',
  ];

  late Future<FitnessCenter> _centerFuture;
  int _activeSlide = 0;

  @override
  void initState() {
    super.initState();
    _centerFuture = widget.centerApiService.getCenter(widget.centerId);
  }

  void _retry() {
    setState(() {
      _centerFuture = widget.centerApiService.getCenter(widget.centerId);
    });
  }

  void _previousSlide() {
    setState(() {
      _activeSlide = _activeSlide == 0
          ? _galleryImages.length - 1
          : _activeSlide - 1;
    });
  }

  void _nextSlide() {
    setState(() {
      _activeSlide = (_activeSlide + 1) % _galleryImages.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return IronBookMobileShell(
      bottomNav: const IronBookBottomNav(),
      children: [
        FutureBuilder<FitnessCenter>(
          future: _centerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _DetailsScaffold(
                initialName: widget.initialName,
                children: const [_DetailsLoading()],
              );
            }

            if (snapshot.hasError) {
              return _DetailsScaffold(
                initialName: widget.initialName,
                children: [
                  _DetailsMessage(
                    title: 'Center details are unavailable',
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

            final center = snapshot.data;
            if (center == null) {
              return _DetailsScaffold(
                initialName: widget.initialName,
                children: const [
                  _DetailsMessage(
                    title: 'Center details are unavailable',
                    message: 'No center data was returned.',
                  ),
                ],
              );
            }

            return _DetailsScaffold(
              center: center,
              initialName: widget.initialName,
              children: [
                _CenterGallery(
                  images: _galleryImages,
                  activeSlide: _activeSlide,
                  onPrevious: _previousSlide,
                  onNext: _nextSlide,
                  onSelect: (index) => setState(() => _activeSlide = index),
                ),
                _CenterSummary(center: center),
                if (center.capacity != null && center.capacity! > 0)
                  _InfoSection(
                    title: 'Capacity',
                    icon: Icons.groups_outlined,
                    body: '${center.capacity} members',
                  ),
                if (_hasText(center.amenities))
                  _InfoSection(
                    title: 'Amenities',
                    icon: Icons.check_circle_outline,
                    body: center.amenities!.trim(),
                    muted: true,
                  ),
                if (_hasText(center.notes))
                  _InfoSection(
                    title: 'Notes',
                    icon: Icons.notes_outlined,
                    body: center.notes!.trim(),
                  ),
                const _DeferredPreviewSection(),
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
    required this.children,
    this.center,
    this.initialName,
  });

  final FitnessCenter? center;
  final String? initialName;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final title = center?.name ?? initialName ?? 'Center details';
    final subtitle = center?.location ?? 'Loading location';

    return Column(
      children: [
        IronBookMobileHeader(
          title: title,
          subtitle: subtitle,
          onBack: () => Navigator.of(context).pop(),
          trailing: const IronBookTag(label: 'Center Details'),
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

class _CenterGallery extends StatelessWidget {
  const _CenterGallery({
    required this.images,
    required this.activeSlide,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  final List<String> images;
  final int activeSlide;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1.44,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: IronBookMobileColors.slate200),
                boxShadow: [
                  BoxShadow(
                    color: IronBookMobileColors.slate900.withValues(
                      alpha: 0.08,
                    ),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(images[activeSlide], fit: BoxFit.cover),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Color(0x660F172A),
                          Color(0x0D0F172A),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  const Positioned(left: 12, top: 12, child: _ImageLabel()),
                  Positioned(
                    left: 8,
                    top: 0,
                    bottom: 0,
                    child: _GalleryArrow(
                      icon: Icons.chevron_left,
                      onPressed: onPrevious,
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 0,
                    bottom: 0,
                    child: _GalleryArrow(
                      icon: Icons.chevron_right,
                      onPressed: onNext,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < images.length; index += 1)
              GestureDetector(
                onTap: () => onSelect(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: index == activeSlide ? 20 : 10,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: index == activeSlide
                        ? IronBookMobileColors.slate800
                        : IronBookMobileColors.slate300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ImageLabel extends StatelessWidget {
  const _ImageLabel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          'Center preview',
          style: TextStyle(
            color: IronBookMobileColors.slate700,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _GalleryArrow extends StatelessWidget {
  const _GalleryArrow({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.9),
            foregroundColor: IronBookMobileColors.slate700,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.85)),
          ),
          icon: Icon(icon, size: 20),
        ),
      ),
    );
  }
}

class _CenterSummary extends StatelessWidget {
  const _CenterSummary({required this.center});

  final FitnessCenter center;

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
                      center.name,
                      style: const TextStyle(
                        color: IronBookMobileColors.slate800,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
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
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const IronBookTag(label: 'Active'),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'This location is loaded from the IronBook API and controls member center-first browsing.',
            style: TextStyle(
              color: IronBookMobileColors.slate600,
              fontSize: 13,
              height: 1.45,
            ),
          ),
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
    this.muted = false,
  });

  final String title;
  final IconData icon;
  final String body;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      muted: muted,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: IronBookMobileColors.emerald700, size: 18),
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

class _DeferredPreviewSection extends StatelessWidget {
  const _DeferredPreviewSection();

  @override
  Widget build(BuildContext context) {
    return IronBookMobileSection(
      muted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Expanded(
                child: Text(
                  'Membership & Access',
                  style: TextStyle(
                    color: IronBookMobileColors.slate800,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IronBookTag(label: 'Later'),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Memberships, trainers, and group sessions will appear here after those real backend features are implemented.',
            style: TextStyle(
              color: IronBookMobileColors.slate500,
              fontSize: 12,
              height: 1.45,
            ),
          ),
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
            'Loading center details...',
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
