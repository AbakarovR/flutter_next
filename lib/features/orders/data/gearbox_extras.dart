import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'orders_repository.dart';
import 'work_extras.dart';

/// Что заливали в коробку в прошлый раз: товар и литры.
class LastGear {
  const LastGear(this.productId, this.qtyMilli);
  final String productId;
  final int qtyMilli;
}

extension GearboxExtras on OrdersRepository {
  /// Последнее масло КПП этого типа у этой машины (из проведённых заказов,
  /// кроме текущего). null, если замен ещё не было.
  Future<LastGear?> lastGearOil(String orderId, GearboxType type) async {
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
                    db.products.deletedAt.isNull() &
                    db.products.kind.equalsValue(ProductKind.gearOil) &
                    db.products.gearbox.equalsValue(type),
              )
              ..orderBy([OrderingTerm.desc(db.orders.completedAt)])
              ..limit(1))
            .get();

    if (rows.isEmpty) return null;
    final p = rows.first.readTable(db.products);
    final i = rows.first.readTable(db.orderItems);
    return LastGear(p.id, i.qtyMilli);
  }

  /// Добавляет всё из окна «Коробка» одной транзакцией:
  /// масло, другие товары и работу. Добавится всё или ничего.
  Future<void> addGearboxJob(
    String orderId, {
    Product? oil,
    int oilQtyMilli = 0,
    List<(Product, int)> extras = const [],
    List<(String, int)> works = const [],
  }) => db.transaction(() async {
    if (oil != null) {
      await addProductItem(
        orderId,
        oil,
        qtyMilli: oilQtyMilli,
        priceKopecks: oil.priceKopecks,
      );
    }
    for (final (p, qty) in extras) {
      await addProductItem(
        orderId,
        p,
        qtyMilli: qty,
        priceKopecks: p.priceKopecks,
      );
    }
    if (works.isNotEmpty) {
      await addWorkItems(orderId, works);
    }
  });
}
