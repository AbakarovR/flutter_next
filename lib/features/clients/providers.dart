import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import 'data/clients_repository.dart';

/// Репозиторий. Создаётся один раз, внутри использует нашу базу.
final clientsRepositoryProvider = Provider<ClientsRepository>(
  (ref) => ClientsRepository(ref.watch(databaseProvider)),
);

/// Поток списка клиентов. Экран подпишется и будет обновляться сам.
final clientsListProvider = StreamProvider<List<ClientListItem>>(
  (ref) => ref.watch(clientsRepositoryProvider).watchList(),
);

/// .family = провайдер с параметром. Один клиент по его id.
final clientProvider = StreamProvider.family<Client?, String>(
  (ref, id) => ref.watch(clientsRepositoryProvider).watchClient(id),
);

/// Автомобили конкретного клиента.
final clientVehiclesProvider = StreamProvider.family<List<Vehicle>, String>(
  (ref, clientId) =>
      ref.watch(clientsRepositoryProvider).watchVehicles(clientId),
);
