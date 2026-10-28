import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'orders_repository.dart';

/// Дополнительные методы для работ. extension добавляет их к
/// OrdersRepository, не меняя сам файл репозитория.
extension WorkExtras on OrdersRepository {
  /// Последняя цена каждой работы: «Замена масла» → 80000 (копейки).
  /// Берём из прошлых заказов, новые строки перекрывают старые.
  Future<Map<String, int>> lastWorkPrices() async {
    final rows =
        await (db.select(db.orderItems)
              ..where(
                (i) => i.kind.equalsValue(ItemKind.work) & i.deletedAt.isNull(),
              )
              ..orderBy([(i) => OrderingTerm.desc(i.createdAt)]))
            .get();

    final prices = <String, int>{};
    for (final r in rows) {
      if (r.priceKopecks > 0) prices.putIfAbsent(r.title, () => r.priceKopecks);
    }
    return prices;
  }

  /// Добавляет несколько работ одним действием (название, цена в копейках).
  /// Транзакция: либо добавились все, либо ни одной.
  Future<void> addWorkItems(String orderId, List<(String, int)> works) =>
      db.transaction(() async {
        for (final (title, price) in works) {
          await addWorkItem(
            orderId,
            title: title,
            qtyMilli: 1000,
            priceKopecks: price,
          );
        }
      });
}
