import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../inventory/product_ext.dart';
import 'orders_repository.dart';
import 'work_extras.dart';

/// Что использовали в прошлый раз: товар и количество.
class LastUsed {
  const LastUsed(this.productId, this.qtyMilli);
  final String productId;
  final int qtyMilli;
}

/// Последнее масло и все фильтры из последней замены этой машины.
class LastKit {
  const LastKit({this.oil, this.filterIds = const []});
  final LastUsed? oil;
  final List<String> filterIds;
}

extension KitExtras on OrdersRepository {
  /// Ищем в ПРОВЕДЁННЫХ заказах той же машины (кроме текущего заказа),
  /// самые свежие сверху. Удалённые товары пропускаем.
  Future<LastKit> lastKit(String orderId) async {
    final order = await (db.select(
      db.orders,
    )..where((o) => o.id.equals(orderId))).getSingle();

    final rows =
        await (db.select(db.orderItems).join([
                innerJoin(
                  db.orders,
                  db.orders.id.equalsExp(db.orderItems.orderId),
                ),
                innerJoin(
                  db.products,
                  db.products.id.equalsExp(db.orderItems.productId),
                ),
              ])
              ..where(
                db.orders.vehicleId.equals(order.vehicleId) &
                    db.orders.id.equals(orderId).not() &
                    db.orders.deletedAt.isNull() &
                    db.orders.status.equalsValue(OrderStatus.completed) &
                    db.orderItems.deletedAt.isNull() &
                    db.products.deletedAt.isNull(),
              )
              ..orderBy([OrderingTerm.desc(db.orders.completedAt)]))
            .get();

    LastUsed? oil;
    String? filterOrderId; // заказ, из которого берём фильтры
    final filterIds = <String>[];
    for (final r in rows) {
      final p = r.readTable(db.products);
      final i = r.readTable(db.orderItems);
      final o = r.readTable(db.orders);
      if (p.kind == ProductKind.oil && oil == null) {
        oil = LastUsed(p.id, i.qtyMilli);
      } else if (p.kind.isFilter) {
        filterOrderId ??= o.id;
        if (o.id == filterOrderId && !filterIds.contains(p.id)) {
          filterIds.add(p.id);
        }
      }
    }
    return LastKit(oil: oil, filterIds: filterIds);
  }

  /// Добавляет комплект: масло, фильтры (по 1 шт) и работы.
  /// Одна транзакция: добавится всё или ничего.
  Future<void> addKit(
    String orderId, {
    required Product oil,
    required int oilQtyMilli,
    List<Product> filters = const [],
    List<(String, int)> works = const [],
  }) => db.transaction(() async {
    await addProductItem(
      orderId,
      oil,
      qtyMilli: oilQtyMilli,
      priceKopecks: oil.priceKopecks,
    );
    for (final f in filters) {
      await addProductItem(
        orderId,
        f,
        qtyMilli: 1000,
        priceKopecks: f.priceKopecks,
      );
    }
    if (works.isNotEmpty) {
      await addWorkItems(orderId, works);
    }
  });
}
