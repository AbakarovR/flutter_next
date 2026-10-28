import 'package:flutter/cupertino.dart';

import '../../core/database/app_database.dart';

extension OrderX on Order {
  /// Дата проведения. Fallback нужен только для данных до миграции.
  DateTime get completionDate => completedAt ?? updatedAt;
}

extension OrderItemX on OrderItem {
  /// Сумма строки в копейках: количество (в тысячных) × цена / 1000.
  /// «+ 500» это округление до ближайшей копейки, и всё в целых числах.
  int get sumKopecks => (qtyMilli * priceKopecks + 500) ~/ 1000;
}

extension OrderStatusX on OrderStatus {
  String get label => this == OrderStatus.draft ? 'В работе' : 'Проведён';

  Color get color => this == OrderStatus.draft
      ? CupertinoColors.systemOrange
      : CupertinoColors.systemGreen;
}
