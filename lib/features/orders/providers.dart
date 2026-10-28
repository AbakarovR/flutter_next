import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../inventory/providers.dart';
import 'data/orders_repository.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(
    ref.watch(databaseProvider),
    ref.watch(inventoryRepositoryProvider),
  ),
);

final ordersListProvider = StreamProvider<List<OrderListItem>>(
  (ref) => ref.watch(ordersRepositoryProvider).watchList(),
);

final orderProvider = StreamProvider.family<OrderListItem?, String>(
  (ref, id) => ref.watch(ordersRepositoryProvider).watchOrder(id),
);

final orderItemsProvider = StreamProvider.family<List<OrderItem>, String>(
  (ref, id) => ref.watch(ordersRepositoryProvider).watchItems(id),
);
