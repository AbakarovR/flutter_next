import '../../../core/database/app_database.dart';
import 'orders_repository.dart';
import 'work_extras.dart';

extension EngineExtras on OrdersRepository {
  /// Добавляет всё из окна «Двигатель» одной транзакцией:
  /// масло, фильтры (по 1 шт), другие товары и работы.
  /// Добавится всё или ничего.
  Future<void> addEngineJob(
    String orderId, {
    Product? oil,
    int oilQtyMilli = 0,
    List<Product> filters = const [],
    List<(Product, int)> extras = const [],
    List<(String, int)> works = const [],
  }) {
    final uniqueFilterIds = filters.map((filter) => filter.id).toSet();
    if (uniqueFilterIds.length != filters.length) {
      throw ArgumentError('One filter cannot be added more than once.');
    }

    return db.transaction(() async {
      if (oil != null) {
        await addProductItem(
          orderId,
          oil,
          qtyMilli: oilQtyMilli,
          priceKopecks: oil.priceKopecks,
        );
      }
      for (final f in filters) {
        await addProductItem(
          orderId,
          f,
          qtyMilli: 1000,
          priceKopecks: f.priceKopecks,
        );
      }
      for (final (p, qty) in extras) {
        await addProductItem(
          orderId,
          p,
          qtyMilli: qty,
          priceKopecks: p.priceKopecks,
        );
      }
      if (works.isNotEmpty) {
        await addWorkItems(orderId, works);
      }
    });
  }
}
