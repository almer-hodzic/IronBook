class AdminReportSummary {
  const AdminReportSummary(this.asOfUtc, this.metrics);

  final DateTime asOfUtc;
  final Map<String, num> metrics;

  static const labels = {
    'totalActiveMembers': 'Active members (all centers)',
    'activeMemberships': 'Active memberships',
    'pendingMemberships': 'Pending memberships',
    'completedPaymentsCount': 'Completed payments',
    'completedPaymentsTotalAmount': 'Completed payment amount',
    'pendingReceptionPaymentsCount': 'Pending reception payments',
    'pendingReceptionPaymentsTotalAmount': 'Pending reception amount',
    'totalCheckIns': 'Check-ins',
    'upcomingGroupTrainings': 'Upcoming group trainings',
    'pendingCoachingRequests': 'Pending coaching requests',
    'approvedCoachingRequests': 'Approved coaching requests',
    'completedTrainingReports': 'Completed training reports',
  };

  factory AdminReportSummary.fromJson(Map<String, dynamic> json) {
    final metrics = <String, num>{};
    for (final key in labels.keys) {
      final value = json[key];
      if (value is! num ||
          !value.isFinite ||
          value < 0 ||
          (!key.endsWith('Amount') && value is! int)) {
        throw FormatException('Invalid report metric "$key".');
      }
      metrics[key] = value;
    }
    if (json['asOfUtc'] is! String) {
      throw const FormatException('Missing report date.');
    }
    return AdminReportSummary(
      DateTime.parse(json['asOfUtc'] as String),
      Map.unmodifiable(metrics),
    );
  }
}

class AdminCenterActivity {
  const AdminCenterActivity(
    this.centerId,
    this.centerName,
    this.activeMemberships,
    this.checkIns,
    this.upcomingGroupTrainings,
    this.pendingCoachingRequests,
  );
  final int centerId;
  final String centerName;
  final int activeMemberships;
  final int checkIns;
  final int upcomingGroupTrainings;
  final int pendingCoachingRequests;

  factory AdminCenterActivity.fromJson(Map<String, dynamic> json) {
    int count(String key) {
      final value = json[key];
      if (value is! int || value < 0) {
        throw FormatException('Invalid center activity field "$key".');
      }
      return value;
    }

    if (json['centerName'] is! String) {
      throw const FormatException('Missing center name.');
    }
    return AdminCenterActivity(
      count('centerId'),
      json['centerName'] as String,
      count('activeMemberships'),
      count('checkIns'),
      count('upcomingGroupTrainings'),
      count('pendingCoachingRequests'),
    );
  }
}

class AdminReportFilter {
  const AdminReportFilter({this.fromDate, this.toDate, this.centerId});
  final String? fromDate;
  final String? toDate;
  final int? centerId;

  Map<String, String> get query => {
    'fromDate': ?fromDate,
    'toDate': ?toDate,
    if (centerId != null) 'centerId': centerId.toString(),
  };
}
