import 'package:flutter/material.dart';

import '../models/member_notification.dart';
import '../models/paged_result.dart';
import '../widgets/paging_controls.dart';
import '../services/center_api_service.dart';
import '../widgets/ironbook_mobile_components.dart';

class MemberNotificationsScreen extends StatefulWidget {
  const MemberNotificationsScreen({super.key, required this.centerApiService});

  final CenterApiService centerApiService;

  @override
  State<MemberNotificationsScreen> createState() =>
      _MemberNotificationsScreenState();
}

class _MemberNotificationsScreenState extends State<MemberNotificationsScreen> {
  List<MemberNotification>? _notifications;
  PagedResult<MemberNotification>? _page;
  int _pageNumber = 1;
  final Set<int> _markingRead = {};
  final Map<int, String> _readErrors = {};
  bool _loading = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading || _markingRead.isNotEmpty) return;
    setState(() {
      _loading = true;
      _loadError = null;
      _readErrors.clear();
    });
    try {
      final page = await loadAvailablePage(
        _pageNumber,
        (number) =>
            widget.centerApiService.getMemberNotifications(pageNumber: number),
      );
      if (!mounted) return;
      setState(() {
        _notifications = page.items;
        _page = page;
        _pageNumber = page.pageNumber;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  void _changePage(int number) {
    if (_loading || _markingRead.isNotEmpty) return;
    _pageNumber = number;
    _load();
  }

  Future<void> _markRead(MemberNotification notification) async {
    if (notification.isRead ||
        _markingRead.contains(notification.id) ||
        _loading) {
      return;
    }
    setState(() {
      _markingRead.add(notification.id);
      _readErrors.remove(notification.id);
    });
    try {
      final updated = await widget.centerApiService.markNotificationRead(
        notification.id,
      );
      if (!mounted) return;
      setState(() {
        _notifications = _notifications!
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
        _markingRead.remove(notification.id);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _markingRead.remove(notification.id);
        _readErrors[notification.id] = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifications = _notifications;
    return IronBookMobileShell(
      children: [
        IronBookMobileHeader(
          title: 'Notifications',
          subtitle: 'Your member updates, newest first.',
          onBack: () => Navigator.of(context).pop(),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!_loading && _loadError == null && notifications != null)
              Semantics(
                liveRegion: true,
                child: IronBookTag(
                  label:
                      '${notifications.where((item) => !item.isRead).length} unread${(_page?.totalPages ?? 0) > 1 ? ' on this page' : ''}',
                  variant: IronBookTagVariant.accent,
                ),
              ),
            IronBookMobileButton.secondary(
              onPressed: _loading || _markingRead.isNotEmpty ? null : _load,
              label: _loadError == null ? 'Refresh' : 'Retry',
              icon: Icons.refresh,
            ),
          ],
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_loadError != null)
          IronBookMobileSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications unavailable',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(_loadError!),
              ],
            ),
          )
        else if (notifications != null && notifications.isEmpty)
          const IronBookMobileSection(child: Text('No notifications yet.'))
        else if (notifications != null)
          for (final notification in notifications)
            Semantics(
              button: !notification.isRead,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap:
                      notification.isRead ||
                          _markingRead.contains(notification.id)
                      ? null
                      : () => _markRead(notification),
                  borderRadius: BorderRadius.circular(18),
                  child: IronBookMobileSection(
                    muted: notification.isRead,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              notification.isRead
                                  ? Icons.drafts_outlined
                                  : Icons.mark_email_unread_outlined,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                notification.title,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontWeight: notification.isRead
                                          ? FontWeight.w500
                                          : FontWeight.w800,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IronBookTag(
                              label: notification.isRead ? 'Read' : 'Unread',
                              variant: notification.isRead
                                  ? IronBookTagVariant.neutral
                                  : IronBookTagVariant.accent,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(notification.message),
                        const SizedBox(height: 8),
                        Text(
                          _dateLabel(context, notification.createdAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_markingRead.contains(notification.id)) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(),
                        ],
                        if (_readErrors[notification.id]
                            case final String error) ...[
                          const SizedBox(height: 8),
                          Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        if (!notification.isRead &&
                            !_markingRead.contains(notification.id)) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Tap to mark as read',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        if (!_loading && _loadError == null && _page != null)
          PagingControls(
            pageNumber: _page!.pageNumber,
            totalPages: _page!.totalPages,
            busy: _markingRead.isNotEmpty,
            onPageChanged: _changePage,
          ),
      ],
    );
  }
}

String _dateLabel(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final labels = MaterialLocalizations.of(context);
  return '${labels.formatMediumDate(local)} ${local.year}, '
      '${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
}
