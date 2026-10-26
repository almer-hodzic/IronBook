import 'package:flutter/material.dart';

import 'ironbook_mobile_components.dart';

class PagingControls extends StatelessWidget {
  const PagingControls({
    super.key,
    required this.pageNumber,
    required this.totalPages,
    required this.onPageChanged,
    this.busy = false,
  });

  final int pageNumber;
  final int totalPages;
  final ValueChanged<int> onPageChanged;
  final bool busy;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    alignment: WrapAlignment.center,
    children: [
      IronBookMobileButton.secondary(
        label: 'Previous',
        onPressed: busy || pageNumber <= 1
            ? null
            : () => onPageChanged(pageNumber - 1),
      ),
      Text('Page $pageNumber of ${totalPages > 0 ? totalPages : 1}'),
      IronBookMobileButton.secondary(
        label: 'Next',
        onPressed: busy || pageNumber >= totalPages
            ? null
            : () => onPageChanged(pageNumber + 1),
      ),
    ],
  );
}
