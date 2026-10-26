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
    T Function(Map<String, dynamic>) parse,
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
            return parse(item);
          })
          .toList(growable: false),
      pageNumber: read('pageNumber', 1),
      pageSize: read('pageSize', 1),
      totalCount: read('totalCount', 0),
      totalPages: read('totalPages', 0),
    );
  }
}

// A lookup either returns every page in backend order or fails as a whole.
Future<List<T>> loadAllPages<T>(
  Future<PagedResult<T>> Function(int page) load,
) async {
  final items = <T>[];
  var number = 1;
  while (true) {
    final page = await load(number);
    if (page.pageNumber != number) {
      throw const FormatException('Unexpected lookup page.');
    }
    items.addAll(page.items);
    if (number >= page.totalPages) return items;
    number++;
  }
}

// A mutation/filter may remove the last item on a page. Reload the last valid page.
Future<PagedResult<T>> loadAvailablePage<T>(
  int number,
  Future<PagedResult<T>> Function(int page) load,
) async {
  final page = await load(number);
  if (number > 1 && number > page.totalPages) {
    return load(page.totalPages > 0 ? page.totalPages : 1);
  }
  return page;
}
