import 'package:flutter/material.dart';

import '../models/paged_result.dart';
import 'admin_primitives.dart';

class AdminPagingControls extends StatelessWidget {
  const AdminPagingControls({
    super.key,
    required this.page,
    required this.onPageChanged,
    this.enabled = true,
  });
  final PagedResult<dynamic> page;
  final ValueChanged<int> onPageChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      AdminButton.secondary(
        label: 'Previous',
        onPressed: enabled && page.pageNumber > 1
            ? () => onPageChanged(page.pageNumber - 1)
            : null,
      ),
      const SizedBox(width: 12),
      Text(
        'Page ${page.totalPages == 0 ? 0 : page.pageNumber} of ${page.totalPages}',
      ),
      const SizedBox(width: 12),
      AdminButton.secondary(
        label: 'Next',
        onPressed: enabled && page.pageNumber < page.totalPages
            ? () => onPageChanged(page.pageNumber + 1)
            : null,
      ),
    ],
  );
}
