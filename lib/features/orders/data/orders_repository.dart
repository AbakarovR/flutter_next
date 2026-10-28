import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';
import '../../inventory/data/inventory_repository.dart';
import '../order_ext.dart';

/// Заказ вместе с клиентом и автомобилем: так экраны получают всё одним запросом.
class OrderListItem {
  OrderListItem(this.order, this.client, this.vehicle);
  final Order order;
  final Client client;
  final Vehicle vehicle;
}

class OrdersRepository {
  OrdersRepository(this.db, this.inventory);
  final AppDatabase db;

  /// Склад нужен, чтобы списывать товар через единую точку applyMovement.
  final InventoryRepository inventory;

  // ───────────── Чтение ─────────────

  /// Заказы + клиент + авто. Удалённость клиента и авто НЕ фильтруем:
  /// старый заказ должен показываться, даже если машину потом убрали.
  JoinedSelectStatement _base() => db.select(db.orders).join([
    innerJoin(db.clients, db.clients.id.equalsExp(db.orders.clientId)),
    innerJoin(db.vehicles, db.vehicles.id.equalsExp(db.orders.vehicleId)),
  ]);

  OrderListItem _toItem(TypedResult r) => OrderListItem(
    r.readTable(db.orders),
    r.readTable(db.clients),
    r.readTable(db.vehicles),
  );

  Stream<List<OrderListItem>> watchList() =>
      (_base()
            ..where(db.orders.deletedAt.isNull())
            ..orderBy([OrderingTerm.desc(db.orders.createdAt)]))
          .map(_toItem)
          .watch();

  Stream<OrderListItem?> watchOrder(String id) =>
      (_base()..where(db.orders.id.equals(id) & db.orders.deletedAt.isNull()))
          .map(_toItem)
          .watchSingleOrNull();

  Stream<List<OrderItem>> watchItems(String orderId) =>
      (db.select(db.orderItems)
            ..where((i) => i.orderId.equals(orderId) & i.deletedAt.isNull())
            ..orderBy([(i) => OrderingTerm.asc(i.createdAt)]))
          .watch();

  Future<List<OrderItem>> _activeItems(String orderId) => (db.select(
    db.orderItems,
  )..where((i) => i.orderId.equals(orderId) & i.deletedAt.isNull())).get();

  Future<Order> _getOrder(String id) =>
      (db.select(db.orders)..where((o) => o.id.equals(id))).getSingle();

  // ───────────── Создание и состав ─────────────

  /// Новый заказ в статусе «В работе». Возвращает его id.
  Future<String> createDraft({
    required String clientId,
    required String vehicleId,
    required int mileage,
  }) async {
    final id = newId();
    await db
        .into(db.orders)
        .insert(
          OrdersCompanion.insert(
            id: Value(id),
            clientId: clientId,
            vehicleId: vehicleId,
            mileage: mileage,
          ),
        );
    return id;
  }

  /// Пересчитывает итог заказа. Вызывается после каждого изменения состава.
  Future<void> _recalc(String orderId) async {
    final items = await _activeItems(orderId);
    final total = items.fold<int>(0, (sum, i) => sum + i.sumKopecks);
    await (db.update(db.orders)..where((o) => o.id.equals(orderId))).write(
      OrdersCompanion(
        totalKopecks: Value(total),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Добавить товар. Если такой уже есть в заказе, увеличиваем количество.
  Future<void> addProductItem(
    String orderId,
    Product p, {
    required int qtyMilli,
    required int priceKopecks,
  }) => db.transaction(() async {
    final existing =
        (await (db.select(db.orderItems)..where(
                  (i) =>
                      i.orderId.equals(orderId) &
                      i.productId.equals(p.id) &
                      i.deletedAt.isNull(),
                ))
                .get())
            .firstOrNull;

    if (existing != null) {
      await (db.update(
        db.orderItems,
      )..where((i) => i.id.equals(existing.id))).write(
        OrderItemsCompanion(
          qtyMilli: Value(existing.qtyMilli + qtyMilli),
          priceKopecks: Value(priceKopecks),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      await db
          .into(db.orderItems)
          .insert(
            OrderItemsCompanion.insert(
              orderId: orderId,
              productId: Value(p.id),
              kind: ItemKind.product,
              title: p.name, // снимок названия
              priceKopecks: priceKopecks, // снимок цены
              qtyMilli: Value(qtyMilli),
            ),
          );
    }
    await _recalc(orderId);
  });

  /// Добавить работу (услугу). Товара на складе у неё нет.
  Future<void> addWorkItem(
    String orderId, {
    required String title,
    required int qtyMilli,
    required int priceKopecks,
  }) => db.transaction(() async {
    await db
        .into(db.orderItems)
        .insert(
          OrderItemsCompanion.insert(
            orderId: orderId,
            kind: ItemKind.work,
            title: title.trim(),
            priceKopecks: priceKopecks,
            qtyMilli: Value(qtyMilli),
          ),
        );
    await _recalc(orderId);
  });

  Future<void> updateItem(
    OrderItem item, {
    required String title,
    required int qtyMilli,
    required int priceKopecks,
  }) => db.transaction(() async {
    await (db.update(db.orderItems)..where((i) => i.id.equals(item.id))).write(
      OrderItemsCompanion(
        title: Value(title.trim()),
        qtyMilli: Value(qtyMilli),
        priceKopecks: Value(priceKopecks),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _recalc(item.orderId);
  });

  Future<void> removeItem(OrderItem item) => db.transaction(() async {
    final now = DateTime.now();
    await (db.update(db.orderItems)..where((i) => i.id.equals(item.id))).write(
      OrderItemsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await _recalc(item.orderId);
  });

  Future<void> setMileage(String orderId, int km) =>
      (db.update(db.orders)..where((o) => o.id.equals(orderId))).write(
        OrdersCompanion(mileage: Value(km), updatedAt: Value(DateTime.now())),
      );

  /// Удалять можно только заказ «В работе»: проведённый сначала возвращаем.
  Future<void> softDeleteOrder(String id) => db.transaction(() async {
    if ((await _getOrder(id)).status != OrderStatus.draft) return;
    final now = DateTime.now();
    await (db.update(db.orderItems)..where((i) => i.orderId.equals(id))).write(
      OrderItemsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await (db.update(db.orders)..where((o) => o.id.equals(id))).write(
      OrdersCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  });

  // ───────────── Проведение ─────────────

  /// Каких товаров не хватает на складе. Пустой список = всё есть.
  Future<List<String>> shortages(String orderId) async {
    final result = <String>[];
    final items = await _activeItems(orderId);
    for (final i in items.where((i) => i.productId != null)) {
      final p = await (db.select(
        db.products,
      )..where((t) => t.id.equals(i.productId!))).getSingle();
      if (p.stockMilli < i.qtyMilli) {
        result.add(
          '${p.name}: нужно ${formatQty(i.qtyMilli)} ${p.unit}, '
          'есть ${formatQty(p.stockMilli)}',
        );
      }
    }
    return result;
  }

  /// Провести заказ: списать товары, записать снимок закупки, сменить статус,
  /// обновить пробег авто. Всё в одной транзакции.
  Future<void> complete(String orderId) => db.transaction(() async {
    final order = await _getOrder(orderId);
    if (order.status == OrderStatus.completed) return;
    final items = await _activeItems(orderId);
    if (items.isEmpty) return;

    // Сначала сверяем весь заказ по свежим остаткам в рамках транзакции.
    // Суммирование по товару также защищает от повторяющихся строк заказа.
    final requiredByProduct = <String, int>{};
    for (final item in items) {
      final productId = item.productId;
      if (productId != null) {
        requiredByProduct.update(
          productId,
          (qty) => qty + item.qtyMilli,
          ifAbsent: () => item.qtyMilli,
        );
      }
    }
    final shortages = <StockShortage>[];
    for (final entry in requiredByProduct.entries) {
      final product = await (db.select(
        db.products,
      )..where((p) => p.id.equals(entry.key))).getSingle();
      if (product.stockMilli < entry.value) {
        shortages.add(
          StockShortage(
            productName: product.name,
            availableMilli: product.stockMilli,
            requiredMilli: entry.value,
            unit: product.unit,
          ),
        );
      }
    }
    if (shortages.isNotEmpty) {
      throw InsufficientStockException(shortages);
    }

    for (final i in items.where((i) => i.productId != null)) {
      final p = await (db.select(
        db.products,
      )..where((t) => t.id.equals(i.productId!))).getSingle();

      await inventory.applyMovement(
        productId: i.productId!,
        kind: MovementKind.sale,
        deltaMilli: -i.qtyMilli, // минус = уходит со склада
        note: 'Заказ-наряд',
        orderId: orderId,
      );

      // Снимок закупочной цены: по нему считается прибыль в отчёте.
      await (db.update(db.orderItems)..where((t) => t.id.equals(i.id))).write(
        OrderItemsCompanion(costKopecks: Value(p.costKopecks)),
      );
    }

    final completedAt = DateTime.now();
    await (db.update(db.orders)..where((o) => o.id.equals(orderId))).write(
      OrdersCompanion(
        status: const Value(OrderStatus.completed),
        completedAt: Value(completedAt),
        totalKopecks: Value(items.fold<int>(0, (s, i) => s + i.sumKopecks)),
        updatedAt: Value(completedAt),
      ),
    );

    // Пробег в карточке авто только растёт: меньшее значение не пишем.
    final v = await (db.select(
      db.vehicles,
    )..where((t) => t.id.equals(order.vehicleId))).getSingle();
    if (order.mileage > v.mileage) {
      await (db.update(db.vehicles)..where((t) => t.id.equals(v.id))).write(
        VehiclesCompanion(
          mileage: Value(order.mileage),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  });

  /// Вернуть заказ в работу. Товары возвращаются на склад.
  ///
  /// Считаем ИТОГ всех движений по этому заказу и гасим его. Так выходит
  /// правильно, даже если заказ уже проводили и возвращали раньше.
  Future<void> reopen(String orderId) => db.transaction(() async {
    final moves = await (db.select(
      db.stockMovements,
    )..where((m) => m.orderId.equals(orderId) & m.deletedAt.isNull())).get();

    final net = <String, int>{}; // товар → общее изменение
    for (final m in moves) {
      net[m.productId] = (net[m.productId] ?? 0) + m.deltaMilli;
    }
    for (final e in net.entries.where((e) => e.value != 0)) {
      await inventory.applyMovement(
        productId: e.key,
        kind: MovementKind.adjustment,
        deltaMilli: -e.value,
        note: 'Отмена заказа',
        orderId: orderId,
      );
    }

    await (db.update(db.orders)..where((o) => o.id.equals(orderId))).write(
      OrdersCompanion(
        status: const Value(OrderStatus.draft),
        completedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  });
}
