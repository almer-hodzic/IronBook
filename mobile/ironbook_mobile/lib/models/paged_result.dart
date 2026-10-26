class PagedResult<T> {
  const PagedResult({
    required this.items,
    required this.pageNumber,
    required this.pageSize,
    required this.totalCount,
    required this.totalPages,
  });

  final List<T> items;
  final int pageNumber;
  final int pageSize;
  final int totalCount;
  final int totalPages;

  factory PagedResult.fromJson(
    Object? value,
    T Function(Map<String, dynamic>) parseItem,
  ) {
    if (value is! Map<String, dynamic> || value['items'] is! List) {
      throw const FormatException('Invalid paged response.');
    }
    int read(String key, int minimum) {
      final field = value[key];
      if (field is! int || field < minimum) {
        throw const FormatException('Invalid pagination metadata.');
      }
      return field;
    }

    return PagedResult(
      items: (value['items'] as List)
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('Invalid paged item.');
            }
            return parseItem(item);
          })
          .toList(growable: false),
      pageNumber: read('pageNumber', 1),
      pageSize: read('pageSize', 1),
      totalCount: read('totalCount', 0),
      totalPages: read('totalPages', 0),
    );
  }
}

// A mutation or concurrent deletion can remove the last page.
Future<PagedResult<T>> loadAvailablePage<T>(
  int number,
  Future<PagedResult<T>> Function(int) load,
) async {
  final page = await load(number);
  if (number > 1 && number > page.totalPages) {
    return load(page.totalPages > 0 ? page.totalPages : 1);
  }
  return page;
}
