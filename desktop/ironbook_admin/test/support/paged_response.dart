Map<String, Object> pagedResponse(
  List<Object?> items, {
  int page = 1,
  int pageSize = 20,
  int? totalCount,
}) {
  final total = totalCount ?? items.length;
  return {
    'items': items,
    'pageNumber': page,
    'pageSize': pageSize,
    'totalCount': total,
    'totalPages': (total / pageSize).ceil(),
  };
}
