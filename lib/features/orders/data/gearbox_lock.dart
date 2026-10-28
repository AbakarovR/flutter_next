import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../order_ext.dart';
import 'orders_repository.dart';

/// Какая коробка у машины и что в неё заливали в последний раз.
class VehicleGearbox {
  const VehicleGearbox(this.type, this.productName, this.qtyMilli, this.date);
  final GearboxType type;
  final String productName;
  final int qtyMilli;
  final DateTime date;
}

extension GearboxLock on OrdersRepository {
  /// Последняя заливка масла в коробку этой машины (проведённые заказы,
  /// кроме текущего). null, если коробку ещё не обслуживали.
  Future<VehicleGearbox?> vehicleGearbox(String orderId) async {
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
                    db.products.kind.equalsValue(ProductKind.gearOil),
              )
              ..orderBy([OrderingTerm.desc(db.orders.completedAt)])
              ..limit(1))
            .get();

    if (rows.isEmpty) return null;
    final p = rows.first.readTable(db.products);
    final i = rows.first.readTable(db.orderItems);
    final o = rows.first.readTable(db.orders);
    final type = p.gearbox;
    if (type == null) return null;
    return VehicleGearbox(type, i.title, i.qtyMilli, o.completionDate);
  }
}
