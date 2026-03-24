import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/paginated.dart';

abstract class PaginatedAsyncNotifier<T>
    extends StateNotifier<AsyncValue<PaginatedResult<T>>> {
  PaginatedAsyncNotifier() : super(const AsyncValue.loading());

  Future<PaginatedResult<T>> loadPage({String? cursor});

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await loadPage());
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasNextPage) {
      return;
    }

    try {
      final nextPage = await loadPage(cursor: current.endCursor);
      state = AsyncValue.data(current.appendPage(nextPage));
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> refresh() => load();
}
