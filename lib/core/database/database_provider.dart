import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// Единственный экземпляр базы на всё приложение.
/// Любой экран получает её через ref.watch(databaseProvider).
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  // Когда приложение закрывается, корректно закрываем файл базы.
  ref.onDispose(db.close);
  return db;
});
