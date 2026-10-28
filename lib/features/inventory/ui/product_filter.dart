import 'package:flutter/cupertino.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/pill_tabs.dart';

enum TopTab { all, oil, filter, fluid, other }

enum OilGroup { engine, gearbox }

/// Что выбрано в фильтре товаров: вкладка, группа масел, тип коробки.
class ProductFilter {
  const ProductFilter({
    this.tab = TopTab.all,
    this.group = OilGroup.engine,
    this.gear = GearboxType.auto,
    this.filterKind = ProductKind.oilFilter,
    this.fluidKind = ProductKind.antifreeze,
    this.otherKind = ProductKind.sparkPlug,
  });

  final TopTab tab;
  final OilGroup group;
  final GearboxType? gear;
  final ProductKind filterKind;
  final ProductKind fluidKind;
  final ProductKind otherKind;

  bool matches(Product p) => switch (tab) {
    TopTab.all => true,
    TopTab.filter =>
      p.kind == filterKind ||
          (filterKind == ProductKind.oilFilter && p.kind == ProductKind.filter),
    TopTab.fluid =>
      p.kind == fluidKind ||
          (fluidKind == ProductKind.antifreeze && p.kind == ProductKind.fluid),
    TopTab.other =>
      p.kind == otherKind ||
          (otherKind == ProductKind.sparkPlug && p.kind == ProductKind.other),
    TopTab.oil => switch (group) {
      OilGroup.engine => p.kind == ProductKind.oil,
      OilGroup.gearbox => p.kind == ProductKind.gearOil && p.gearbox == gear,
    },
  };
}

/// Ряд вкладок и (для масел) вложенные переключатели. Используется
/// на складе и в окне «Добавить товар» в заказе.
class ProductFilterBar extends StatelessWidget {
  const ProductFilterBar({
    super.key,
    required this.filter,
    required this.onChanged,
    this.showAll = true,
  });

  final ProductFilter filter;
  final ValueChanged<ProductFilter> onChanged;
  final bool showAll;

  @override
  Widget build(BuildContext context) {
    final f = filter;
    return Column(
      children: [
        PillTabs<TopTab>(
          value: f.tab,
          items: {
            if (showAll) TopTab.all: 'Все',
            TopTab.oil: 'Масла',
            TopTab.filter: 'Фильтры',
            TopTab.fluid: 'Жидкости',
            TopTab.other: 'Прочее',
          },
          onChanged: (t) => onChanged(ProductFilter(tab: t)),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              if (f.tab == TopTab.oil)
                PillTabs<OilGroup>(
                  value: f.group,
                  items: const {
                    OilGroup.engine: 'Двигатель',
                    OilGroup.gearbox: 'Коробка передач',
                  },
                  onChanged: (g) =>
                      onChanged(ProductFilter(tab: f.tab, group: g)),
                ),
              if (f.tab == TopTab.oil && f.group == OilGroup.gearbox)
                PillTabs<int>(
                  value: (f.gear ?? GearboxType.auto).index,
                  items: const {0: 'АКПП', 1: 'МКПП', 2: 'РКПП'},
                  onChanged: (i) => onChanged(
                    ProductFilter(
                      tab: f.tab,
                      group: f.group,
                      gear: GearboxType.values[i],
                    ),
                  ),
                ),
              if (f.tab == TopTab.filter)
                PillTabs<ProductKind>(
                  value: f.filterKind,
                  items: const {
                    ProductKind.oilFilter: 'Масляный',
                    ProductKind.airFilter: 'Воздушный',
                    ProductKind.cabinFilter: 'Салонный',
                  },
                  onChanged: (kind) =>
                      onChanged(ProductFilter(tab: f.tab, filterKind: kind)),
                ),
              if (f.tab == TopTab.fluid)
                PillTabs<ProductKind>(
                  value: f.fluidKind,
                  items: const {
                    ProductKind.antifreeze: 'Антифриз',
                    ProductKind.tosol: 'Тосол',
                    ProductKind.distilledWater: 'Дист. вода',
                    ProductKind.washerFluid: 'Омывающая',
                    ProductKind.brakeFluid: 'Тормозная',
                  },
                  onChanged: (kind) =>
                      onChanged(ProductFilter(tab: f.tab, fluidKind: kind)),
                ),
              if (f.tab == TopTab.other)
                PillTabs<ProductKind>(
                  value: f.otherKind,
                  items: const {
                    ProductKind.sparkPlug: 'Свечи',
                    ProductKind.ignitionCoil: 'Катушка',
                    ProductKind.ignitionModule: 'Модуль',
                  },
                  onChanged: (kind) =>
                      onChanged(ProductFilter(tab: f.tab, otherKind: kind)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
