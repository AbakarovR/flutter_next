import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/plate.dart';

/// Клиент + его автомобили. Нужен для списка: в каждой строке
/// мы показываем госномера, и по ним же работает поиск.
class ClientListItem {
  ClientListItem(this.client, this.vehicles);
  final Client client;
  final List<Vehicle> vehicles;
}

class ClientsRepository {
  ClientsRepository(this.db);
  final AppDatabase db;

  // ───────────── Чтение (потоки) ─────────────
  // Stream = экран подписывается один раз и сам обновляется
  // при любом изменении в таблицах.

  /// Все живые клиенты с их живыми авто, отсортированные по имени.
  Stream<List<ClientListItem>> watchList() {
    // LEFT JOIN: клиент попадёт в список, даже если у него нет авто.
    final query = db.select(db.clients).join([
      leftOuterJoin(
        db.vehicles,
        db.vehicles.clientId.equalsExp(db.clients.id) &
            db.vehicles.deletedAt.isNull(),
      ),
    ])..where(db.clients.deletedAt.isNull());

    return query.watch().map((rows) {
      // JOIN возвращает строку на каждую пару «клиент-авто».
      // Склеиваем обратно: один клиент = один элемент со списком авто.
      final byId = <String, ClientListItem>{};
      for (final row in rows) {
        final client = row.readTable(db.clients);
        final vehicle = row.readTableOrNull(db.vehicles);
        final item = byId.putIfAbsent(
          client.id,
          () => ClientListItem(client, []),
        );
        if (vehicle != null) item.vehicles.add(vehicle);
      }
      // Сортируем в Dart, а не в SQL: SQLite плохо сортирует кириллицу
      // без учёта регистра.
      return byId.values.toList()..sort(
        (a, b) =>
            a.client.name.toLowerCase().compareTo(b.client.name.toLowerCase()),
      );
    });
  }

  Stream<Client?> watchClient(String id) {
    return (db.select(db.clients)
          ..where((c) => c.id.equals(id) & c.deletedAt.isNull()))
        .watchSingleOrNull();
  }

  Stream<List<Vehicle>> watchVehicles(String clientId) {
    return (db.select(db.vehicles)
          ..where((v) => v.clientId.equals(clientId) & v.deletedAt.isNull())
          ..orderBy([(v) => OrderingTerm.asc(v.createdAt)]))
        .watch();
  }

  // ───────────── Клиенты ─────────────

  Future<void> addClient({required String name, String? phone, String? note}) {
    return db
        .into(db.clients)
        .insert(
          ClientsCompanion.insert(
            name: name.trim(),
            phone: Value(_nullIfEmpty(phone)),
            note: Value(_nullIfEmpty(note)),
          ),
        );
  }

  Future<void> updateClient(
    String id, {
    required String name,
    String? phone,
    String? note,
  }) {
    return (db.update(db.clients)..where((c) => c.id.equals(id))).write(
      ClientsCompanion(
        name: Value(name.trim()),
        phone: Value(_nullIfEmpty(phone)),
        note: Value(_nullIfEmpty(note)),
        updatedAt: Value(DateTime.now()), // правило №2: всегда обновляем
      ),
    );
  }

  /// Мягкое удаление клиента вместе с его авто (в одной транзакции:
  /// либо удалилось всё, либо ничего).
  Future<void> softDeleteClient(String id) {
    final now = DateTime.now();
    return db.transaction(() async {
      await (db.update(db.vehicles)..where((v) => v.clientId.equals(id))).write(
        VehiclesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await (db.update(db.clients)..where((c) => c.id.equals(id))).write(
        ClientsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
    });
  }

  // ───────────── Автомобили ─────────────

  Future<void> addVehicle({
    required String clientId,
    required String plate,
    required String brand,
    required String model,
    int? year,
    String? vin,
    int mileage = 0,
  }) {
    return db
        .into(db.vehicles)
        .insert(
          VehiclesCompanion.insert(
            clientId: clientId,
            plate: normalizePlate(plate),
            brand: brand.trim(),
            model: model.trim(),
            year: Value(year),
            vin: Value(_nullIfEmpty(vin?.toUpperCase())),
            mileage: Value(mileage),
          ),
        );
  }

  /// Изменение автомобиля. Как и везде, обновляем updatedAt.
  Future<void> updateVehicle(
    String id, {
    required String plate,
    required String brand,
    required String model,
    int? year,
    String? vin,
    required int mileage,
  }) {
    return (db.update(db.vehicles)..where((v) => v.id.equals(id))).write(
      VehiclesCompanion(
        plate: Value(normalizePlate(plate)),
        brand: Value(brand.trim()),
        model: Value(model.trim()),
        year: Value(year),
        vin: Value(_nullIfEmpty(vin?.toUpperCase())),
        mileage: Value(mileage),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Госномер должен быть уникальным среди активных автомобилей.
  Future<bool> vehiclePlateExists(
    String plate, {
    String? exceptVehicleId,
  }) async {
    final normalized = normalizePlate(plate);
    final rows = await (db.select(
      db.vehicles,
    )..where((v) => v.plate.equals(normalized) & v.deletedAt.isNull())).get();
    return rows.any((vehicle) => vehicle.id != exceptVehicleId);
  }

  Future<void> softDeleteVehicle(String id) {
    final now = DateTime.now();
    return (db.update(db.vehicles)..where((v) => v.id.equals(id))).write(
      VehiclesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  /// Пустая строка → null, чтобы в базе не копились «пустые» значения.
  String? _nullIfEmpty(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
