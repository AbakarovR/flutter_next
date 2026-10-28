import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Публичная функция генерации UUID.
/// Должна быть БЕЗ подчёркивания: сгенерированный код Drift
/// вызывает её из другого файла (app_database.g.dart).
String newId() => _uuid.v4();

// ───────────── Перечисления ─────────────
// Храним в базе как текст, поэтому порядок значений можно менять безопасно.

/// Вид товара для точного учёта и фильтрации склада.
/// Старые общие значения filter/fluid/other сохранены для совместимости
/// с записями, которые не удалось автоматически распознать при миграции.
enum ProductKind {
  oil,
  filter,
  fluid,
  gearOil,
  other,
  oilFilter,
  airFilter,
  cabinFilter,
  antifreeze,
  tosol,
  distilledWater,
  washerFluid,
  brakeFluid,
  sparkPlug,
  ignitionCoil,
  ignitionModule,
}

/// Тип коробки передач (для масла КПП).
enum GearboxType { auto, manual, robot }

enum OrderStatus { draft, completed }

/// Строка заказа: либо товар со склада, либо работа (услуга).
enum ItemKind { product, work }

/// Тип движения склада.
enum MovementKind { receipt, sale, adjustment }

// ───────────── Общие колонки ─────────────

/// Колонки, которые есть в КАЖДОЙ таблице: UUID, updatedAt, deletedAt.
mixin SyncColumns on Table {
  TextColumn get id => text().clientDefault(newId)();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();

  /// Время последнего изменения. Обновлять вручную при каждом изменении!
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  /// null = запись живая. Если дата есть, запись удалена.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ───────────── Таблицы ─────────────

class Clients extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get note => text().nullable()();
}

@TableIndex(name: 'vehicles_plate_idx', columns: {#plate})
class Vehicles extends Table with SyncColumns {
  TextColumn get clientId => text().references(Clients, #id)();
  TextColumn get plate => text()(); // госномер
  TextColumn get vin => text().nullable()();
  TextColumn get brand => text()();
  TextColumn get model => text()();
  IntColumn get year => integer().nullable()();

  /// Последний известный пробег, км.
  IntColumn get mileage => integer().withDefault(const Constant(0))();
}

class Products extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get kind => textEnum<ProductKind>()();
  TextColumn get unit => text().withDefault(const Constant('шт'))();

  /// Цена продажи в копейках.
  IntColumn get priceKopecks => integer().withDefault(const Constant(0))();

  /// Закупочная цена в копейках.
  IntColumn get costKopecks => integer().withDefault(const Constant(0))();

  /// Остаток в тысячных долях: 4,5 л = 4500.
  IntColumn get stockMilli => integer().withDefault(const Constant(0))();

  /// Порог «заканчивается».
  IntColumn get minStockMilli => integer().withDefault(const Constant(0))();

  /// Для масла КПП: для какой коробки оно подходит. У остальных null.
  TextColumn get gearbox => textEnum<GearboxType>().nullable()();
}

class Orders extends Table with SyncColumns {
  TextColumn get clientId => text().references(Clients, #id)();
  TextColumn get vehicleId => text().references(Vehicles, #id)();

  /// Пробег на момент обслуживания.
  IntColumn get mileage => integer()();

  TextColumn get status =>
      textEnum<OrderStatus>().withDefault(const Constant('draft'))();

  /// Когда заказ был проведён. Не меняется при обычном редактировании записи.
  DateTimeColumn get completedAt => dateTime().nullable()();

  IntColumn get totalKopecks => integer().withDefault(const Constant(0))();

  TextColumn get note => text().nullable()();
}

class OrderItems extends Table with SyncColumns {
  TextColumn get orderId => text().references(Orders, #id)();

  /// Для работ null: товара на складе нет.
  TextColumn get productId => text().nullable().references(Products, #id)();

  TextColumn get kind => textEnum<ItemKind>()();

  /// Снимок названия и цены на момент продажи.
  TextColumn get title => text()();
  IntColumn get qtyMilli => integer().withDefault(const Constant(1000))();
  IntColumn get priceKopecks => integer()();

  /// Снимок закупочной цены за единицу. Записывается при проведении заказа.
  /// 0 = снимка нет (старые заказы).
  IntColumn get costKopecks => integer().withDefault(const Constant(0))();
}

/// Журнал движений склада. Каждая запись это одно изменение остатка.
class StockMovements extends Table with SyncColumns {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get kind => textEnum<MovementKind>()();

  /// Изменение остатка в тысячных долях: приход +20000, продажа −4500.
  IntColumn get deltaMilli => integer()();

  /// Закупочная цена за единицу (копейки). Заполняется только при приходе.
  IntColumn get costKopecks => integer().nullable()();

  TextColumn get note => text().nullable()();

  /// Если движение вызвано заказом, здесь его id.
  TextColumn get orderId => text().nullable().references(Orders, #id)();
}

/// Продажа товара без заказа (розница). Одна запись = одна позиция.
class Sales extends Table with SyncColumns {
  TextColumn get productId => text().references(Products, #id)();

  /// Снимок названия, цены и закупки на момент продажи.
  TextColumn get title => text()();
  IntColumn get qtyMilli => integer()();
  IntColumn get priceKopecks => integer()();
  IntColumn get costKopecks => integer().withDefault(const Constant(0))();

  TextColumn get note => text().nullable()();
}

/// Расходы мастерской: аренда, зарплата и т.д.
class Expenses extends Table with SyncColumns {
  TextColumn get title => text()();
  IntColumn get amountKopecks => integer()();
}
