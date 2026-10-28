import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database_provider.dart';
import 'data/sync_queue_repository.dart';

final syncQueueRepositoryProvider = Provider<SyncQueueRepository>(
  (ref) => SyncQueueRepository(ref.watch(databaseProvider)),
);

final pendingSyncCountProvider = FutureProvider<int>(
  (ref) => ref.watch(syncQueueRepositoryProvider).pendingCount(),
);
