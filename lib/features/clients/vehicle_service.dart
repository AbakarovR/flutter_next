import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../orders/order_ext.dart';
import 'data/clients_repository.dart';
import 'providers.dart';

/// Одна заливка масла: что, сколько, когда и при каком пробеге.
class ServiceEntry {
  const ServiceEntry({
    required this.title,
    required this.qtyMilli,
    required this.unit,
    required this.date,
    required this.mileage,
    this.gearbox,
  });

  final String title;
  final int qtyMilli;
  final String unit;
  final DateTime date;
  final int mileage;
  final GearboxType? gearbox; // только для масла коробки
}

/// Последняя замена масла в двигателе и в коробке у машины.
class VehicleService {
  const VehicleService({this.engine, this.gearbox});
  final ServiceEntry? engine;
  final ServiceEntry? gearbox;

  bool get isEmpty => engine == null && gearbox == null;
}

/// Одна позиция из завершённого заказ-наряда в истории автомобиля.
class VehicleServiceLine {
  const VehicleServiceLine(this.item, this.unit);

  final OrderItem item;
  final String unit;
}

/// Визит автомобиля с позициями заказ-наряда.
class VehicleServiceVisit {
  VehicleServiceVisit(this.order, this.lines);

  final Order order;
  final List<VehicleServiceLine> lines;
}

extension VehicleServiceX on ClientsRepository {
  /// Следит за проведёнными заказами машины. Обновляется само.
  Stream<VehicleService> watchService(String vehicleId) {
    final query =
        db.select(db.orderItems).join([
          innerJoin(db.orders, db.orders.id.equalsExp(db.orderItems.orderId)),
          innerJoin(
            db.products,
            db.products.id.equalsExp(db.orderItems.productId),
          ),
        ])..where(
          db.orders.vehicleId.equals(vehicleId) &
              db.orders.status.equalsValue(OrderStatus.completed) &
              db.orders.deletedAt.isNull() &
              db.orderItems.deletedAt.isNull(),
        );

    return query.watch().map((rows) {
      ServiceEntry? engine;
      ServiceEntry? gear;
      for (final r in rows) {
        final p = r.readTable(db.products);
        final i = r.readTable(db.orderItems);
        final o = r.readTable(db.orders);
        if (p.kind != ProductKind.oil && p.kind != ProductKind.gearOil) {
          continue;
        }
        final e = ServiceEntry(
          title: i.title,
          qtyMilli: i.qtyMilli,
          unit: p.unit,
          date: o.completionDate,
          mileage: o.mileage,
          gearbox: p.gearbox,
        );
        // Оставляем самую свежую заливку каждого вида.
        if (p.kind == ProductKind.oil) {
          if (engine == null || e.date.isAfter(engine.date)) engine = e;
        } else {
          if (gear == null || e.date.isAfter(gear.date)) gear = e;
        }
      }
      return VehicleService(engine: engine, gearbox: gear);
    });
  }

  /// Полная история завершённых заказов автомобиля, новые сверху.
  Stream<List<VehicleServiceVisit>> watchHistory(String vehicleId) {
    final query =
        db.select(db.orderItems).join([
            innerJoin(db.orders, db.orders.id.equalsExp(db.orderItems.orderId)),
            leftOuterJoin(
              db.products,
              db.products.id.equalsExp(db.orderItems.productId),
            ),
          ])
          ..where(
            db.orders.vehicleId.equals(vehicleId) &
                db.orders.status.equalsValue(OrderStatus.completed) &
                db.orders.deletedAt.isNull() &
                db.orderItems.deletedAt.isNull(),
          )
          ..orderBy([
            OrderingTerm.desc(db.orders.completedAt),
            OrderingTerm.asc(db.orderItems.createdAt),
          ]);

    return query.watch().map((rows) {
      final visits = <String, VehicleServiceVisit>{};
      for (final row in rows) {
        final order = row.readTable(db.orders);
        final item = row.readTable(db.orderItems);
        final product = row.readTableOrNull(db.products);
        final visit = visits.putIfAbsent(
          order.id,
          () => VehicleServiceVisit(order, []),
        );
        visit.lines.add(VehicleServiceLine(item, product?.unit ?? ''));
      }
      return visits.values.toList();
    });
  }
}

final vehicleServiceProvider = StreamProvider.family<VehicleService, String>(
  (ref, vehicleId) =>
      ref.watch(clientsRepositoryProvider).watchService(vehicleId),
);

final vehicleHistoryProvider =
    StreamProvider.family<List<VehicleServiceVisit>, String>(
      (ref, vehicleId) =>
          ref.watch(clientsRepositoryProvider).watchHistory(vehicleId),
    );
