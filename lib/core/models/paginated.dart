/// Generic paginated result from GraphQL cursor-based pagination.
class PaginatedResult<T> {
  const PaginatedResult({
    required this.items,
    this.endCursor,
    this.hasNextPage = false,
    this.totalCount,
  });

  final List<T> items;
  final String? endCursor;
  final bool hasNextPage;
  final int? totalCount;

  PaginatedResult<T> appendPage(PaginatedResult<T> next) {
    return PaginatedResult(
      items: [...items, ...next.items],
      endCursor: next.endCursor,
      hasNextPage: next.hasNextPage,
      totalCount: next.totalCount ?? totalCount,
    );
  }
}
