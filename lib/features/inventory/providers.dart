import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import 'data/inventory_repository.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepository(ref.watch(databaseProvider)),
);

final productsProvider = StreamProvider<List<Product>>(
  (ref) => ref.watch(inventoryRepositoryProvider).watchProducts(),
);

final productProvider = StreamProvider.family<Product?, String>(
  (ref, id) => ref.watch(inventoryRepositoryProvider).watchProduct(id),
);

final productMovementsProvider =
    StreamProvider.family<List<StockMovement>, String>(
      (ref, id) => ref.watch(inventoryRepositoryProvider).watchMovements(id),
    );
