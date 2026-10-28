import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';

/// Нарушение складского ограничения. Остаток товара не может стать
/// отрицательным при любом движении, независимо от того, какой экран его
/// инициировал.
class StockShortage {
  const StockShortage({
    required this.productName,
    required this.availableMilli,
    required this.requiredMilli,
    required this.unit,
  });

  final String productName;
  final int availableMilli;
  final int requiredMilli;
  final String unit;

  @override
  String toString() =>
      '$productName: нужно ${formatQty(requiredMilli)} $unit, '
      'есть ${formatQty(availableMilli)}';
}

class InsufficientStockException implements Exception {
  const InsufficientStockException(this.shortages);

  final List<StockShortage> shortages;

  @override
  String toString() => shortages.join('\n');
}

class InventoryRepository {
  InventoryRepository(this.db);
  final AppDatabase db;

  // ───────────── Чтение ─────────────

  Stream<List<Product>> watchProducts() {
    return (db.select(
      db.products,
    )..where((p) => p.deletedAt.isNull())).watch().map(
      (list) => [...list]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    );
  }

  Stream<Product?> watchProduct(String id) {
    return (db.select(db.products)
          ..where((p) => p.id.equals(id) & p.deletedAt.isNull()))
        .watchSingleOrNull();
  }

  /// Последние 50 движений по товару, новые сверху.
  Stream<List<StockMovement>> watchMovements(String productId) {
    return (db.select(db.stockMovements)
          ..where((m) => m.productId.equals(productId) & m.deletedAt.isNull())
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
          ..limit(50))
        .watch();
  }

  // ───────────── Товары ─────────────

  Future<void> addProduct({
    required String name,
    required ProductKind kind,
    required String unit,
    required int priceKopecks,
    required int costKopecks,
    required int minStockMilli,
    GearboxType? gearbox,
    int initialStockMilli = 0,
  }) {
    return db.transaction(() async {
      final id = newId();
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: Value(id),
              name: name.trim(),
              kind: kind,
              unit: Value(unit),
              priceKopecks: Value(priceKopecks),
              costKopecks: Value(costKopecks),
              minStockMilli: Value(minStockMilli),
              gearbox: Value(gearbox),
            ),
          );
      // Начальный остаток это тоже приход, поэтому идёт через журнал.
      if (initialStockMilli > 0) {
        await applyMovement(
          productId: id,
          kind: MovementKind.receipt,
          deltaMilli: initialStockMilli,
          costKopecks: costKopecks,
          note: 'Начальный остаток',
        );
      }
    });
  }

  /// Обновляет описание товара. Остаток здесь НЕ трогаем:
  /// он меняется только через журнал (приход, корректировка, продажа).
  Future<void> updateProduct(
    String id, {
    required String name,
    required ProductKind kind,
    required String unit,
    required int priceKopecks,
    required int costKopecks,
    required int minStockMilli,
    GearboxType? gearbox,
  }) {
    return (db.update(db.products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(
        name: Value(name.trim()),
        kind: Value(kind),
        unit: Value(unit),
        priceKopecks: Value(priceKopecks),
        costKopecks: Value(costKopecks),
        minStockMilli: Value(minStockMilli),
        gearbox: Value(gearbox),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Старые заказы не пострадают: в строках заказа хранится
  /// снимок названия и цены.
  Future<void> softDeleteProduct(String id) {
    final now = DateTime.now();
    return (db.update(db.products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  // ───────────── Движения склада ─────────────

  /// Приход товара.
  Future<void> receive(
    String productId, {
    required int qtyMilli,
    int? costKopecks,
    String? note,
  }) {
    return applyMovement(
      productId: productId,
      kind: MovementKind.receipt,
      deltaMilli: qtyMilli,
      costKopecks: costKopecks,
      note: note,
    );
  }

  /// «Пересчитать»: на полке на самом деле X. Разницу записываем как пересчёт.
  Future<void> adjustTo(String productId, int actualMilli, {String? note}) {
    return db.transaction(() async {
      final p = await _getProduct(productId);
      final delta = actualMilli - p.stockMilli;
      if (delta == 0) return; // ничего не изменилось, журнал не засоряем
      await applyMovement(
        productId: productId,
        kind: MovementKind.adjustment,
        deltaMilli: delta,
        note: note,
      );
    });
  }

  /// ЕДИНСТВЕННОЕ место, где меняется остаток.
  Future<void> applyMovement({
    required String productId,
    required MovementKind kind,
    required int deltaMilli,
    int? costKopecks,
    String? note,
    String? orderId,
  }) {
    // Запись в журнале и новый остаток: либо оба, либо ни одного.
    return db.transaction(() async {
      final p = await _getProduct(productId);
      final nextStock = p.stockMilli + deltaMilli;
      if (nextStock < 0) {
        throw InsufficientStockException([
          StockShortage(
            productName: p.name,
            availableMilli: p.stockMilli,
            requiredMilli: -deltaMilli,
            unit: p.unit,
          ),
        ]);
      }
      final now = DateTime.now();

      await db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              productId: productId,
              kind: kind,
              deltaMilli: deltaMilli,
              costKopecks: Value(costKopecks),
              note: Value(
                (note == null || note.trim().isEmpty) ? null : note.trim(),
              ),
              orderId: Value(orderId),
            ),
          );

      await (db.update(
        db.products,
      )..where((t) => t.id.equals(productId))).write(
        ProductsCompanion(
          stockMilli: Value(nextStock),
          // При приходе запоминаем последнюю закупочную цену.
          costKopecks: costKopecks != null
              ? Value(costKopecks)
              : const Value.absent(),
          updatedAt: Value(now),
        ),
      );
    });
  }

  Future<Product> _getProduct(String id) =>
      (db.select(db.products)..where((p) => p.id.equals(id))).getSingle();
}
