import 'dart:async';

import 'package:flutter/widgets.dart';

/// Foreground refresh scheduling only; notification requests stay in their screens.
class MemberNotificationPoller with WidgetsBindingObserver {
  MemberNotificationPoller({required this.onPoll, required this.onResume}) {
    WidgetsBinding.instance.addObserver(this);
  }

  static const interval = Duration(seconds: 30);
  VoidCallback onPoll;
  VoidCallback onResume;
  Timer? _timer;
  bool _enabled = false;
  bool _disposed = false;
  bool get isDisposed => _disposed;

  bool get isForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return !_disposed && (state == null || state == AppLifecycleState.resumed);
  }

  void start() {
    if (_disposed) return;
    _enabled = true;
    _startTimer();
  }

  void _startTimer() {
    if (!isForeground || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => onPoll());
  }

  void stop() {
    _enabled = false;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _timer?.cancel();
    _timer = null;
    if (_enabled && state == AppLifecycleState.resumed) {
      _startTimer();
      onResume();
    }
  }

  void dispose() {
    _disposed = true;
    stop();
    WidgetsBinding.instance.removeObserver(this);
  }
}
