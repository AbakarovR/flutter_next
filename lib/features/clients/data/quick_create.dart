import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/plate.dart';
import 'clients_repository.dart';

extension QuickCreate on ClientsRepository {
  /// Новый клиент вместе с автомобилем. Возвращает id обоих.
  Future<({String clientId, String vehicleId})> addClientWithVehicle({
    required String name,
    String? phone,
    required String plate,
    required String brand,
    required String model,
    int mileage = 0,
  }) => db.transaction(() async {
    final clientId = newId();
    final vehicleId = newId();
    final p = phone?.trim() ?? '';

    await db
        .into(db.clients)
        .insert(
          ClientsCompanion.insert(
            id: Value(clientId),
            name: name.trim(),
            phone: Value(p.isEmpty ? null : p),
          ),
        );
    await db
        .into(db.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: Value(vehicleId),
            clientId: clientId,
            plate: normalizePlate(plate),
            brand: brand.trim(),
            model: model.trim(),
            mileage: Value(mileage),
          ),
        );
    return (clientId: clientId, vehicleId: vehicleId);
  });
}
