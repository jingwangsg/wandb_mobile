import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/paginated.dart';
import '../../../core/models/resource_refs.dart';
import '../../../core/models/sweep.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/sweeps_repository.dart';

final sweepsRepositoryProvider = Provider<SweepsRepository>((ref) {
  final client = ref.watch(graphqlClientProvider);
  return SweepsRepository(client);
});

final sweepsProvider =
    FutureProvider.family<PaginatedResult<WandbSweep>, ProjectRef>(
  (ref, projectRef) async {
    final repo = ref.watch(sweepsRepositoryProvider);
    return repo.getSweeps(
      entity: projectRef.entity,
      project: projectRef.project,
    );
  },
);
