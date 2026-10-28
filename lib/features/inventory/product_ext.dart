import 'package:flutter/cupertino.dart';

import '../../core/database/app_database.dart';

/// Русские названия, единицы, иконки и цвета типов товара.
extension ProductKindX on ProductKind {
  String get label => switch (this) {
    ProductKind.oil => 'Моторное масло',
    ProductKind.filter || ProductKind.oilFilter => 'Масляный фильтр',
    ProductKind.airFilter => 'Воздушный фильтр',
    ProductKind.cabinFilter => 'Салонный фильтр',
    ProductKind.fluid || ProductKind.antifreeze => 'Антифриз',
    ProductKind.tosol => 'Тосол',
    ProductKind.distilledWater => 'Дистиллированная вода',
    ProductKind.washerFluid => 'Стеклоомывающая жидкость',
    ProductKind.brakeFluid => 'Тормозная жидкость',
    ProductKind.gearOil => 'Масло КПП',
    ProductKind.other || ProductKind.sparkPlug => 'Свечи зажигания',
    ProductKind.ignitionCoil => 'Катушка зажигания',
    ProductKind.ignitionModule => 'Модуль зажигания',
  };

  /// Масло, масло КПП и жидкости считаем в литрах, остальное в штуках.
  bool get isLiquid =>
      this == ProductKind.oil ||
      this == ProductKind.fluid ||
      this == ProductKind.antifreeze ||
      this == ProductKind.tosol ||
      this == ProductKind.distilledWater ||
      this == ProductKind.washerFluid ||
      this == ProductKind.brakeFluid ||
      this == ProductKind.gearOil;

  bool get isFilter =>
      this == ProductKind.filter ||
      this == ProductKind.oilFilter ||
      this == ProductKind.airFilter ||
      this == ProductKind.cabinFilter;

  bool get isFluid =>
      this == ProductKind.fluid ||
      this == ProductKind.antifreeze ||
      this == ProductKind.tosol ||
      this == ProductKind.distilledWater ||
      this == ProductKind.washerFluid ||
      this == ProductKind.brakeFluid;

  bool get isOther =>
      this == ProductKind.other ||
      this == ProductKind.sparkPlug ||
      this == ProductKind.ignitionCoil ||
      this == ProductKind.ignitionModule;

  String get defaultUnit => isLiquid ? 'л' : 'шт';

  IconData get icon => switch (this) {
    ProductKind.oil => CupertinoIcons.drop_fill,
    ProductKind.filter ||
    ProductKind.oilFilter ||
    ProductKind.airFilter ||
    ProductKind.cabinFilter => CupertinoIcons.circle_grid_3x3_fill,
    ProductKind.fluid ||
    ProductKind.antifreeze ||
    ProductKind.tosol ||
    ProductKind.distilledWater ||
    ProductKind.washerFluid ||
    ProductKind.brakeFluid => CupertinoIcons.drop_triangle_fill,
    ProductKind.gearOil => CupertinoIcons.gear_alt_fill,
    ProductKind.other ||
    ProductKind.sparkPlug ||
    ProductKind.ignitionCoil ||
    ProductKind.ignitionModule => CupertinoIcons.cube_box_fill,
  };

  Color get color => switch (this) {
    ProductKind.oil => const Color(0xFFC98A00), // цвет моторного масла
    ProductKind.filter ||
    ProductKind.oilFilter ||
    ProductKind.airFilter ||
    ProductKind.cabinFilter => CupertinoColors.systemTeal,
    ProductKind.fluid ||
    ProductKind.antifreeze ||
    ProductKind.tosol ||
    ProductKind.distilledWater ||
    ProductKind.washerFluid ||
    ProductKind.brakeFluid => CupertinoColors.systemBlue,
    ProductKind.gearOil => CupertinoColors.systemBrown,
    ProductKind.other ||
    ProductKind.sparkPlug ||
    ProductKind.ignitionCoil ||
    ProductKind.ignitionModule => CupertinoColors.systemIndigo,
  };
}

/// Типы коробок: подписи, название работы и быстрые литры.
extension GearboxTypeX on GearboxType {
  String get label => switch (this) {
    GearboxType.auto => 'АКПП',
    GearboxType.manual => 'МКПП',
    GearboxType.robot => 'РКПП',
  };

  String get fullName => switch (this) {
    GearboxType.auto => 'Автоматическая коробка (АКПП)',
    GearboxType.manual => 'Механическая коробка (МКПП)',
    GearboxType.robot => 'Роботизированная коробка (РКПП)',
  };

  /// Название работы в заказе. В нём есть «КПП», поэтому напоминания
  /// о замене масла двигателя такую работу не считают.
  String get workTitle => switch (this) {
    GearboxType.auto => 'Замена масла в АКПП',
    GearboxType.manual => 'Замена масла в МКПП',
    GearboxType.robot => 'Замена масла в РКПП',
  };

  List<String> get chips => switch (this) {
    GearboxType.auto => const ['4', '6', '8', '10'],
    GearboxType.manual => const ['1,5', '2', '2,5', '3'],
    GearboxType.robot => const ['5', '6', '7'],
  };
}

extension MovementKindX on MovementKind {
  String get label => switch (this) {
    MovementKind.receipt => 'Пополнение',
    MovementKind.sale => 'Продано',
    MovementKind.adjustment => 'Пересчёт',
  };

  IconData get icon => switch (this) {
    MovementKind.receipt => CupertinoIcons.arrow_down_circle_fill,
    MovementKind.sale => CupertinoIcons.cart_fill,
    MovementKind.adjustment => CupertinoIcons.arrow_2_circlepath,
  };

  Color get color => switch (this) {
    MovementKind.receipt => CupertinoColors.systemGreen,
    MovementKind.sale => CupertinoColors.systemBlue,
    MovementKind.adjustment => CupertinoColors.systemGrey,
  };
}

extension ProductX on Product {
  bool get isOut => stockMilli <= 0;

  /// Заканчивается: ещё есть, но не больше порога (порог 0 = не следить).
  bool get isLow => !isOut && minStockMilli > 0 && stockMilli <= minStockMilli;

  bool get needsAttention => isOut || isLow;

  /// Слово статуса: понятно даже без цвета.
  String get statusText =>
      isOut ? 'Нет в наличии' : (isLow ? 'Заканчивается' : 'В наличии');

  Color get statusColor => isOut
      ? CupertinoColors.systemRed
      : (isLow ? CupertinoColors.systemOrange : CupertinoColors.systemGreen);

  /// Цвет только для проблемных позиций, обычные остаются обычными.
  Color? get stockColor => needsAttention ? statusColor : null;

  /// Сколько стоит остаток по закупочной цене (в копейках).
  int get valueKopecks => stockMilli * costKopecks ~/ 1000;

  /// Заполненность полоски от 0 до 1. Полная полоска = в 3 раза больше порога.
  /// Если порог не задан, полоска не нужна, и возвращаем null.
  double? get level {
    if (minStockMilli <= 0) return null;
    return (stockMilli / (minStockMilli * 3)).clamp(0.0, 1.0).toDouble();
  }
}
