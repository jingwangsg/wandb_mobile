import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/paginated.dart';
import '../../../core/models/sweep.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/sweeps_repository.dart';

final sweepsRepositoryProvider = Provider<SweepsRepository>((ref) {
  final client = ref.watch(graphqlClientProvider);
  return SweepsRepository(client);
});

/// Provider key: "entity/project"
final sweepsProvider = FutureProvider.family<PaginatedResult<WandbSweep>, String>(
  (ref, projectPath) async {
    final parts = projectPath.split('/');
    final repo = ref.watch(sweepsRepositoryProvider);
    return repo.getSweeps(entity: parts[0], project: parts[1]);
  },
);
