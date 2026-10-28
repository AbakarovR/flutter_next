import 'dart:convert';

import '../../../core/database/app_database.dart';

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackupSummary {
  const BackupSummary({
    required this.clients,
    required this.vehicles,
    required this.products,
    required this.orders,
  });

  final int clients;
  final int vehicles;
  final int products;
  final int orders;
}

/// Создаёт и восстанавливает полные JSON-копии локальной базы.
class BackupService {
  BackupService(this.db);

  static const _format = 'oilpro-backup';
  static const _version = 1;

  final AppDatabase db;

  /// Формирует согласованный снимок всех таблиц в одной транзакции чтения.
  Future<String> createBackup() => db.transaction(() async {
    final data = <String, Object?>{
      'clients': [
        for (final row in await db.select(db.clients).get()) row.toJson(),
      ],
      'vehicles': [
        for (final row in await db.select(db.vehicles).get()) row.toJson(),
      ],
      'products': [
        for (final row in await db.select(db.products).get()) row.toJson(),
      ],
      'orders': [
        for (final row in await db.select(db.orders).get()) row.toJson(),
      ],
      'orderItems': [
        for (final row in await db.select(db.orderItems).get()) row.toJson(),
      ],
      'stockMovements': [
        for (final row in await db.select(db.stockMovements).get())
          row.toJson(),
      ],
      'sales': [
        for (final row in await db.select(db.sales).get()) row.toJson(),
      ],
      'expenses': [
        for (final row in await db.select(db.expenses).get()) row.toJson(),
      ],
    };

    return const JsonEncoder.withIndent('  ').convert({
      'format': _format,
      'version': _version,
      'exportedAt': DateTime.now().toIso8601String(),
      'data': data,
    });
  });

  /// Проверяет структуру и версии резервной копии до подтверждения замены БД.
  BackupSummary inspectBackup(String contents) {
    final rows = _decode(contents);
    return BackupSummary(
      clients: rows.clients.length,
      vehicles: rows.vehicles.length,
      products: rows.products.length,
      orders: rows.orders.length,
    );
  }

  /// Полностью заменяет текущие данные. Внешние ключи требуют порядка:
  /// сначала зависимые записи удаляются, а при вставке сначала создаются
  /// клиенты, автомобили и товары.
  Future<void> restoreBackup(String contents) async {
    final rows = _decode(contents);
    await db.transaction(() async {
      await db.delete(db.orderItems).go();
      await db.delete(db.stockMovements).go();
      await db.delete(db.sales).go();
      await db.delete(db.expenses).go();
      await db.delete(db.orders).go();
      await db.delete(db.vehicles).go();
      await db.delete(db.clients).go();
      await db.delete(db.products).go();

      await db.batch((batch) {
        if (rows.clients.isNotEmpty) {
          batch.insertAll(db.clients, rows.clients);
        }
        if (rows.vehicles.isNotEmpty) {
          batch.insertAll(db.vehicles, rows.vehicles);
        }
        if (rows.products.isNotEmpty) {
          batch.insertAll(db.products, rows.products);
        }
        if (rows.orders.isNotEmpty) {
          batch.insertAll(db.orders, rows.orders);
        }
        if (rows.orderItems.isNotEmpty) {
          batch.insertAll(db.orderItems, rows.orderItems);
        }
        if (rows.stockMovements.isNotEmpty) {
          batch.insertAll(db.stockMovements, rows.stockMovements);
        }
        if (rows.sales.isNotEmpty) {
          batch.insertAll(db.sales, rows.sales);
        }
        if (rows.expenses.isNotEmpty) {
          batch.insertAll(db.expenses, rows.expenses);
        }
      });
    });
  }

  _BackupRows _decode(String contents) {
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      throw const BackupFormatException('Файл не содержит корректный JSON.');
    }
    if (decoded is! Map) {
      throw const BackupFormatException('Неверный формат резервной копии.');
    }
    final root = Map<String, dynamic>.from(decoded);
    if (root['format'] != _format || root['version'] != _version) {
      throw const BackupFormatException(
        'Формат копии не поддерживается этой версией приложения.',
      );
    }
    if (root['data'] is! Map) {
      throw const BackupFormatException('В резервной копии нет данных.');
    }
    final data = Map<String, dynamic>.from(root['data'] as Map);

    try {
      return _BackupRows(
        clients: _readRows(
          data,
          'clients',
          Client.fromJson,
          (r) => r.toCompanion(true),
        ),
        vehicles: _readRows(
          data,
          'vehicles',
          Vehicle.fromJson,
          (r) => r.toCompanion(true),
        ),
        products: _readRows(
          data,
          'products',
          Product.fromJson,
          (r) => r.toCompanion(true),
        ),
        orders: _readRows(
          data,
          'orders',
          Order.fromJson,
          (r) => r.toCompanion(true),
        ),
        orderItems: _readRows(
          data,
          'orderItems',
          OrderItem.fromJson,
          (r) => r.toCompanion(true),
        ),
        stockMovements: _readRows(
          data,
          'stockMovements',
          StockMovement.fromJson,
          (r) => r.toCompanion(true),
        ),
        sales: _readRows(
          data,
          'sales',
          Sale.fromJson,
          (r) => r.toCompanion(true),
        ),
        expenses: _readRows(
          data,
          'expenses',
          Expense.fromJson,
          (r) => r.toCompanion(true),
        ),
      );
    } on BackupFormatException {
      rethrow;
    } catch (_) {
      throw const BackupFormatException(
        'Структура резервной копии повреждена или неполна.',
      );
    }
  }

  List<T> _readRows<T, R>(
    Map<String, dynamic> data,
    String key,
    R Function(Map<String, dynamic>) decode,
    T Function(R) toCompanion,
  ) {
    final value = data[key];
    if (value is! List) {
      throw BackupFormatException('В копии отсутствует таблица $key.');
    }
    return [
      for (final row in value)
        if (row is Map)
          toCompanion(decode(Map<String, dynamic>.from(row)))
        else
          throw BackupFormatException('Повреждена запись в таблице $key.'),
    ];
  }
}

class _BackupRows {
  const _BackupRows({
    required this.clients,
    required this.vehicles,
    required this.products,
    required this.orders,
    required this.orderItems,
    required this.stockMovements,
    required this.sales,
    required this.expenses,
  });

  final List<ClientsCompanion> clients;
  final List<VehiclesCompanion> vehicles;
  final List<ProductsCompanion> products;
  final List<OrdersCompanion> orders;
  final List<OrderItemsCompanion> orderItems;
  final List<StockMovementsCompanion> stockMovements;
  final List<SalesCompanion> sales;
  final List<ExpensesCompanion> expenses;
}
