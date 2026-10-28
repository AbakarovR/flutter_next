import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../orders/data/orders_repository.dart';
import '../../orders/order_ext.dart';

/// Одна строка проведённого заказа с товаром (для расчёта прибыли).
class OrderLine {
  const OrderLine(this.order, this.item, this.product);
  final Order order;
  final OrderItem item;
  final Product? product;

  /// Выручка по строке.
  int get revenue => item.sumKopecks;

  /// Себестоимость: у работ 0. Берём снимок закупки, а если его нет
  /// (старые заказы), текущую закупочную цену товара.
  int get cost {
    if (item.kind != ItemKind.product) return 0;
    final unit = item.costKopecks > 0
        ? item.costKopecks
        : (product?.costKopecks ?? 0);
    return (item.qtyMilli * unit + 500) ~/ 1000;
  }
}

class ReportsRepository {
  ReportsRepository(this.db, this.inventory);
  final AppDatabase db;
  final InventoryRepository inventory;

  // ───────────── Чтение за период [from, to) ─────────────

  Stream<List<OrderLine>> watchOrderLines(DateTime from, DateTime to) {
    final q =
        db.select(db.orderItems).join([
          innerJoin(db.orders, db.orders.id.equalsExp(db.orderItems.orderId)),
          leftOuterJoin(
            db.products,
            db.products.id.equalsExp(db.orderItems.productId),
          ),
        ])..where(
          db.orders.status.equalsValue(OrderStatus.completed) &
              db.orders.deletedAt.isNull() &
              db.orderItems.deletedAt.isNull() &
              db.orders.completedAt.isBiggerOrEqualValue(from) &
              db.orders.completedAt.isSmallerThanValue(to),
        );
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          OrderLine(
            r.readTable(db.orders),
            r.readTable(db.orderItems),
            r.readTableOrNull(db.products),
          ),
      ],
    );
  }

  Stream<List<OrderListItem>> watchOrders(DateTime from, DateTime to) {
    final q =
        db.select(db.orders).join([
            innerJoin(db.clients, db.clients.id.equalsExp(db.orders.clientId)),
            innerJoin(
              db.vehicles,
              db.vehicles.id.equalsExp(db.orders.vehicleId),
            ),
          ])
          ..where(
            db.orders.status.equalsValue(OrderStatus.completed) &
                db.orders.deletedAt.isNull() &
                db.orders.completedAt.isBiggerOrEqualValue(from) &
                db.orders.completedAt.isSmallerThanValue(to),
          )
          ..orderBy([OrderingTerm.desc(db.orders.completedAt)]);
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          OrderListItem(
            r.readTable(db.orders),
            r.readTable(db.clients),
            r.readTable(db.vehicles),
          ),
      ],
    );
  }

  Stream<List<Sale>> watchSales(DateTime from, DateTime to) =>
      (db.select(db.sales)
            ..where(
              (s) =>
                  s.deletedAt.isNull() &
                  s.createdAt.isBiggerOrEqualValue(from) &
                  s.createdAt.isSmallerThanValue(to),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
          .watch();

  Stream<List<Expense>> watchExpenses(DateTime from, DateTime to) =>
      (db.select(db.expenses)
            ..where(
              (e) =>
                  e.deletedAt.isNull() &
                  e.createdAt.isBiggerOrEqualValue(from) &
                  e.createdAt.isSmallerThanValue(to),
            )
            ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
          .watch();

  // ───────────── Продажи без заказа ─────────────

  String? _clean(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// Продаёт товар и сразу списывает его со склада (одна транзакция).
  /// Возвращает false, если на складе меньше, чем нужно.
  Future<bool> sell(
    Product p, {
    required int qtyMilli,
    required int priceKopecks,
    String? note,
  }) => db.transaction(() async {
    final fresh = await (db.select(
      db.products,
    )..where((t) => t.id.equals(p.id))).getSingle();
    if (qtyMilli <= 0 || fresh.stockMilli < qtyMilli) return false;

    await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            productId: p.id,
            title: fresh.name, // снимок названия
            qtyMilli: qtyMilli,
            priceKopecks: priceKopecks, // снимок цены
            costKopecks: Value(fresh.costKopecks), // снимок закупки
            note: Value(_clean(note)),
          ),
        );
    await inventory.applyMovement(
      productId: p.id,
      kind: MovementKind.sale,
      deltaMilli: -qtyMilli,
      note: 'Продажа без заказа',
    );
    return true;
  });

  /// Отменяет продажу: запись помечается удалённой, товар возвращается.
  Future<void> cancelSale(Sale s) => db.transaction(() async {
    final now = DateTime.now();
    await (db.update(db.sales)..where((t) => t.id.equals(s.id))).write(
      SalesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await inventory.applyMovement(
      productId: s.productId,
      kind: MovementKind.adjustment,
      deltaMilli: s.qtyMilli,
      note: 'Отмена продажи',
    );
  });

  // ───────────── Расходы ─────────────

  Future<void> addExpense(String title, int amountKopecks) => db
      .into(db.expenses)
      .insert(
        ExpensesCompanion.insert(
          title: title.trim().isEmpty ? 'Расход' : title.trim(),
          amountKopecks: amountKopecks,
        ),
      );

  Future<void> deleteExpense(Expense e) {
    final now = DateTime.now();
    return (db.update(db.expenses)..where((t) => t.id.equals(e.id))).write(
      ExpensesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
