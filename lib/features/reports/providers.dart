import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../inventory/providers.dart';
import '../orders/data/orders_repository.dart';
import 'data/reports_repository.dart';
import 'report_logic.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(
    ref.watch(databaseProvider),
    ref.watch(inventoryRepositoryProvider),
  ),
);

final reportLinesProvider = StreamProvider.family<List<OrderLine>, Range>(
  (ref, r) =>
      ref.watch(reportsRepositoryProvider).watchOrderLines(r.from, r.to),
);

final reportOrdersProvider = StreamProvider.family<List<OrderListItem>, Range>(
  (ref, r) => ref.watch(reportsRepositoryProvider).watchOrders(r.from, r.to),
);

final reportSalesProvider = StreamProvider.family<List<Sale>, Range>(
  (ref, r) => ref.watch(reportsRepositoryProvider).watchSales(r.from, r.to),
);

final reportExpensesProvider = StreamProvider.family<List<Expense>, Range>(
  (ref, r) => ref.watch(reportsRepositoryProvider).watchExpenses(r.from, r.to),
);
