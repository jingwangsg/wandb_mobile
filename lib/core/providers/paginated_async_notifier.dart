import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/paginated.dart';

abstract class PaginatedAsyncNotifier<T>
    extends StateNotifier<AsyncValue<PaginatedResult<T>>> {
  PaginatedAsyncNotifier() : super(const AsyncValue.loading());

  Future<PaginatedResult<T>> loadPage({String? cursor});
  int _generation = 0;
  bool _loadingMore = false;

  Future<void> load({bool retainPages = false}) async {
    if (retainPages && (state.isLoading || _loadingMore)) return;
    final retainedCount =
        retainPages ? state.valueOrNull?.items.length ?? 0 : 0;
    final generation = ++_generation;
    state = AsyncValue<PaginatedResult<T>>.loading().copyWithPrevious(state);
    try {
      var page = await loadPage();
      while (mounted &&
          generation == _generation &&
          page.items.length < retainedCount &&
          page.hasNextPage) {
        final next = await loadPage(cursor: page.endCursor);
        if (next.hasNextPage && next.endCursor == page.endCursor)
          throw StateError(
            'The server returned a page without advancing its cursor',
          );
        page = page.appendPage(next);
      }
      if (mounted && generation == _generation) state = AsyncValue.data(page);
    } catch (error, stackTrace) {
      if (mounted && generation == _generation) {
        state = AsyncValue<PaginatedResult<T>>.error(
          error,
          stackTrace,
        ).copyWithPrevious(state);
      }
    }
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (_loadingMore ||
        state.isLoading ||
        current == null ||
        !current.hasNextPage) {
      return;
    }
    final generation = _generation;
    _loadingMore = true;
    try {
      final nextPage = await loadPage(cursor: current.endCursor);
      if (!mounted || generation != _generation) return;
      if (nextPage.hasNextPage && nextPage.endCursor == current.endCursor) {
        throw StateError(
          'The server returned a page without advancing its cursor',
        );
      }
      state = AsyncValue.data(current.appendPage(nextPage));
    } catch (error, stackTrace) {
      if (mounted && generation == _generation) {
        state = AsyncValue<PaginatedResult<T>>.error(
          error,
          stackTrace,
        ).copyWithPrevious(state);
      }
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> refresh() => load();
  Future<void> refreshRetainingPages() => load(retainPages: true);
}
