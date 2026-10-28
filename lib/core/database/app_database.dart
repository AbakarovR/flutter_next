import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Clients,
    Vehicles,
    Products,
    Orders,
    OrderItems,
    StockMovements,
    Sales,
    Expenses,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _connect());

  /// Открывает SQLite с настройками для Web; на мобильных и десктопе
  /// drift_flutter продолжает использовать нативную базу данных.
  static QueryExecutor _connect() => driftDatabase(
    name: 'oilpro',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );

  /// 1 → 2: журнал склада. 2 → 3: тип коробки у товара.
  /// 3 → 4: продажи без заказа, расходы и снимок закупки в строках заказа.
  /// 4 → 5: отдельная дата проведения заказа.
  /// 5 → 6: очистить дату проведения у возвращённых в работу заказов.
  /// 6 → 7: уточнить категории складских товаров.
  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(stockMovements);
      }
      if (from < 3) {
        await m.addColumn(products, products.gearbox);
      }
      if (from < 4) {
        await m.createTable(sales);
        await m.createTable(expenses);
        await m.addColumn(orderItems, orderItems.costKopecks);
      }
      if (from < 5) {
        await m.addColumn(orders, orders.completedAt);
        // Для прежних проведённых заказов время последнего изменения —
        // единственная доступная дата проведения.
        await customStatement(
          "UPDATE orders SET completed_at = updated_at "
          "WHERE status = 'completed' AND completed_at IS NULL",
        );
      }
      if (from < 6) {
        await customStatement(
          "UPDATE orders SET completed_at = NULL WHERE status = 'draft'",
        );
      }
      if (from < 7) {
        final rows = await customSelect(
          'SELECT id, kind, name FROM products',
        ).get();
        for (final row in rows) {
          final oldKind = row.read<String>('kind');
          final name = row.read<String>('name').toLowerCase();
          final kind = switch (oldKind) {
            'filter' =>
              name.contains('возд')
                  ? 'airFilter'
                  : (name.contains('салон') ? 'cabinFilter' : 'oilFilter'),
            'fluid' =>
              name.contains('тосол')
                  ? 'tosol'
                  : (name.contains('дист')
                        ? 'distilledWater'
                        : (name.contains('омы') || name.contains('стекло')
                              ? 'washerFluid'
                              : (name.contains('торм')
                                    ? 'brakeFluid'
                                    : 'antifreeze'))),
            'other' =>
              name.contains('катуш')
                  ? 'ignitionCoil'
                  : (name.contains('модул') ? 'ignitionModule' : 'sparkPlug'),
            _ => oldKind,
          };
          if (kind != oldKind) {
            await customStatement('UPDATE products SET kind = ? WHERE id = ?', [
              kind,
              row.read<String>('id'),
            ]);
          }
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('''
        CREATE TABLE IF NOT EXISTS sync_clock (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          version INTEGER NOT NULL,
          suppress_outbox INTEGER NOT NULL DEFAULT 0 CHECK (suppress_outbox IN (0, 1)),
          trigger_version INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await customStatement('''
        CREATE TABLE IF NOT EXISTS sync_outbox (
          table_name TEXT NOT NULL,
          record_id TEXT NOT NULL,
          operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
          change_version INTEGER NOT NULL,
          PRIMARY KEY (table_name, record_id)
        )
      ''');
      await customStatement(
        'INSERT OR IGNORE INTO sync_clock (id, version) VALUES (1, 0)',
      );
      final clockColumns = await customSelect(
        'PRAGMA table_info(sync_clock)',
      ).get();
      final columnNames = {
        for (final column in clockColumns) column.read<String>('name'),
      };
      if (!columnNames.contains('suppress_outbox')) {
        await customStatement(
          'ALTER TABLE sync_clock ADD COLUMN suppress_outbox '
          'INTEGER NOT NULL DEFAULT 0 CHECK (suppress_outbox IN (0, 1))',
        );
      }
      if (!columnNames.contains('trigger_version')) {
        await customStatement(
          'ALTER TABLE sync_clock ADD COLUMN trigger_version '
          'INTEGER NOT NULL DEFAULT 0',
        );
      }
      final clock = await customSelect(
        'SELECT trigger_version FROM sync_clock WHERE id = 1',
      ).getSingle();
      if (clock.read<int>('trigger_version') < 1) {
        await _installSyncTriggers();
        await customStatement(
          'UPDATE sync_clock SET trigger_version = 1 WHERE id = 1',
        );
      }
    },
  );

  /// Триггеры фиксируют все изменения независимо от экрана и связи с сетью.
  /// Повторные изменения одной строки сворачиваются в один пункт очереди.
  Future<void> _installSyncTriggers() async {
    const tables = [
      'clients',
      'vehicles',
      'products',
      'orders',
      'order_items',
      'stock_movements',
      'sales',
      'expenses',
    ];

    for (final table in tables) {
      for (final (suffix, event, record) in [
        ('insert', 'upsert', 'NEW'),
        ('update', 'upsert', 'NEW'),
        ('delete', 'delete', 'OLD'),
      ]) {
        await customStatement('''
          DROP TRIGGER IF EXISTS "${table}_sync_$suffix"
        ''');
        await customStatement('''
          CREATE TRIGGER "${table}_sync_$suffix"
          AFTER ${suffix.toUpperCase()} ON "$table"
          WHEN (SELECT suppress_outbox FROM sync_clock WHERE id = 1) = 0
          BEGIN
            UPDATE sync_clock SET version = version + 1 WHERE id = 1;
            INSERT INTO sync_outbox
              (table_name, record_id, operation, change_version)
            VALUES (
              '$table', $record.id, '$event',
              (SELECT version FROM sync_clock WHERE id = 1)
            )
            ON CONFLICT(table_name, record_id) DO UPDATE SET
              operation = excluded.operation,
              change_version = excluded.change_version;
          END
        ''');
      }
    }
  }

  /// Применяет данные, полученные с сервера, не добавляя их обратно
  /// в локальную очередь на отправку.
  Future<T> applyRemoteChanges<T>(Future<T> Function() apply) =>
      transaction(() async {
        await customStatement(
          'UPDATE sync_clock SET suppress_outbox = 1 WHERE id = 1',
        );
        try {
          return await apply();
        } finally {
          await customStatement(
            'UPDATE sync_clock SET suppress_outbox = 0 WHERE id = 1',
          );
        }
      });
}
