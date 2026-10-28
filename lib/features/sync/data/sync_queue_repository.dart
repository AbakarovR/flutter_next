import '../../../core/database/app_database.dart';

enum SyncOperation { upsert, delete }

/// Указатель на последнюю локальную версию изменённой записи.
class SyncChange {
  const SyncChange({
    required this.tableName,
    required this.recordId,
    required this.operation,
    required this.changeVersion,
  });

  final String tableName;
  final String recordId;
  final SyncOperation operation;
  final int changeVersion;
}

/// Читает локальную очередь и подтверждает только отправленную версию.
class SyncQueueRepository {
  SyncQueueRepository(this.db);

  final AppDatabase db;

  Future<List<SyncChange>> pendingChanges() => db
      .customSelect(
        'SELECT table_name, record_id, operation, change_version '
        'FROM sync_outbox ORDER BY change_version ASC',
      )
      .map(
        (row) => SyncChange(
          tableName: row.read<String>('table_name'),
          recordId: row.read<String>('record_id'),
          operation: SyncOperation.values.byName(row.read<String>('operation')),
          changeVersion: row.read<int>('change_version'),
        ),
      )
      .get();

  Future<int> pendingCount() async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS count FROM sync_outbox')
        .getSingle();
    return row.read<int>('count');
  }

  /// Удаляет очередь только если она всё ещё на той же версии.
  /// Если запись менялась во время отправки, её новая версия останется.
  Future<void> acknowledge(SyncChange change) => db.customStatement(
    'DELETE FROM sync_outbox '
    'WHERE table_name = ? AND record_id = ? AND change_version = ?',
    [change.tableName, change.recordId, change.changeVersion],
  );
}
