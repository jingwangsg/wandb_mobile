import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/models/paginated.dart';
import 'package:wandb_mobile/core/providers/paginated_async_notifier.dart';

class FakePaginatedNotifier extends PaginatedAsyncNotifier<int> {
  FakePaginatedNotifier(this.responses);

  final Map<String?, Object> responses;
  final List<String?> requestedCursors = <String?>[];

  @override
  Future<PaginatedResult<int>> loadPage({String? cursor}) async {
    requestedCursors.add(cursor);
    final response = responses[cursor];
    if (response is Exception) {
      throw response;
    }
    return response as PaginatedResult<int>;
  }
}

void main() {
  test('automatic refresh keeps the previously loaded page extent', () async {
    final notifier = FakePaginatedNotifier({
      null: const PaginatedResult(
        items: [1, 2],
        hasNextPage: true,
        endCursor: 'c1',
      ),
      'c1': const PaginatedResult(
        items: [3, 4],
        hasNextPage: true,
        endCursor: 'c2',
      ),
      'c2': const PaginatedResult(items: [5, 6]),
    });
    addTearDown(notifier.dispose);
    await notifier.load();
    await notifier.loadMore();
    await notifier.loadMore();
    notifier.responses[null] = const PaginatedResult(
      items: [10, 2],
      hasNextPage: true,
      endCursor: 'c1',
    );
    await notifier.refreshRetainingPages();
    expect(notifier.state.valueOrNull!.items, [10, 2, 3, 4, 5, 6]);
    expect(notifier.requestedCursors, [null, 'c1', 'c2', null, 'c1', 'c2']);
    await notifier.refresh();
    expect(notifier.state.valueOrNull!.items, [10, 2]);
  });

  test('load stores first page data', () async {
    final notifier = FakePaginatedNotifier({
      null: const PaginatedResult(
        items: [1, 2],
        hasNextPage: true,
        endCursor: 'c1',
      ),
    });
    addTearDown(notifier.dispose);

    await notifier.load();

    expect(notifier.requestedCursors, [null]);
    expect(notifier.state.valueOrNull?.items, [1, 2]);
  });

  test('loadMore appends next page when available', () async {
    final notifier = FakePaginatedNotifier({
      null: const PaginatedResult(
        items: [1, 2],
        hasNextPage: true,
        endCursor: 'c1',
      ),
      'c1': const PaginatedResult(items: [3], hasNextPage: false),
    });
    addTearDown(notifier.dispose);

    await notifier.load();
    await notifier.loadMore();

    expect(notifier.requestedCursors, [null, 'c1']);
    expect(notifier.state.valueOrNull?.items, [1, 2, 3]);
  });

  test('loadMore is a no-op without next page', () async {
    final notifier = FakePaginatedNotifier({
      null: const PaginatedResult(items: [1], hasNextPage: false),
    });
    addTearDown(notifier.dispose);

    await notifier.load();
    await notifier.loadMore();

    expect(notifier.requestedCursors, [null]);
    expect(notifier.state.valueOrNull?.items, [1]);
  });

  test('load surfaces errors', () async {
    final notifier = FakePaginatedNotifier({null: Exception('boom')});
    addTearDown(notifier.dispose);

    await notifier.load();

    expect(notifier.state.hasError, isTrue);
  });
}
