import 'dart:convert';

import 'package:http/http.dart' as http;

Map<String, Object?> paged(
  List<Object?> items, {
  int pageNumber = 1,
  int pageSize = 20,
  int? totalCount,
}) {
  final count = totalCount ?? items.length;
  return {
    'items': items,
    'pageNumber': pageNumber,
    'pageSize': pageSize,
    'totalCount': count,
    'totalPages': (count / pageSize).ceil(),
  };
}

String memberListBody(http.BaseRequest request, List<Object?> items) {
  final path = request.url.path;
  final isPaged =
      path == '/api/member/my-trainings' ||
      path == '/api/member/progress-log' ||
      path == '/api/member/notifications' ||
      RegExp(r'^/api/centers/\d+/group-trainings$').hasMatch(path);
  return jsonEncode(isPaged ? paged(items) : items);
}
