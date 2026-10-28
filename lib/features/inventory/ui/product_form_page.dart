import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/form_row.dart';
import '../../../core/widgets/pill_tabs.dart';
import '../../../core/widgets/ui_kit.dart';
import '../product_ext.dart';
import '../providers.dart';
import 'inventory_widgets.dart';
import 'product_filter.dart';

/// Что выбирает пользователь первым рядом. «Масло КПП» отдельным пунктом
/// нет: оно выбирается внутри «Масла» как «Коробка передач».
enum _Type { oil, filter, fluid, other }

/// product == null: новый товар, иначе изменение.
class ProductFormPage extends ConsumerStatefulWidget {
  const ProductFormPage({super.key, this.product, this.initialFilter});
  final Product? product;
  final ProductFilter? initialFilter;

  @override
  ConsumerState<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends ConsumerState<ProductFormPage> {
  Product? get _p => widget.product;

  late _Type _type = switch (_p?.kind) {
    ProductKind.filter ||
    ProductKind.oilFilter ||
    ProductKind.airFilter ||
    ProductKind.cabinFilter => _Type.filter,
    ProductKind.fluid ||
    ProductKind.antifreeze ||
    ProductKind.tosol ||
    ProductKind.distilledWater ||
    ProductKind.washerFluid ||
    ProductKind.brakeFluid => _Type.fluid,
    ProductKind.other ||
    ProductKind.sparkPlug ||
    ProductKind.ignitionCoil ||
    ProductKind.ignitionModule => _Type.other,
    _ => switch (widget.initialFilter?.tab) {
      TopTab.filter => _Type.filter,
      TopTab.fluid => _Type.fluid,
      TopTab.other => _Type.other,
      _ => _Type.oil,
    },
  };

  /// Для масла: true = коробка передач, false = двигатель.
  late bool _forGearbox =
      _p?.kind == ProductKind.gearOil ||
      (_p == null && widget.initialFilter?.group == OilGroup.gearbox);
  late GearboxType _gear = _p?.gearbox ?? GearboxType.auto;
  late ProductKind _specific =
      _p?.kind ??
      switch (widget.initialFilter?.tab) {
        TopTab.filter => widget.initialFilter!.filterKind,
        TopTab.fluid => widget.initialFilter!.fluidKind,
        TopTab.other => widget.initialFilter!.otherKind,
        _ => ProductKind.oilFilter,
      };

  /// Итоговый тип товара в базе.
  ProductKind get _kind => switch (_type) {
    _Type.oil => _forGearbox ? ProductKind.gearOil : ProductKind.oil,
    _Type.filter => _specific,
    _Type.fluid => _specific,
    _Type.other => _specific,
  };

  /// Единица зависит только от типа, выбрать вручную нельзя.
  String get _unit => _kind.defaultUnit;
  String get _unitName => _unit == 'л' ? 'Литры' : 'Штук';

  late final _name = TextEditingController(text: _p?.name);
  late final _price = TextEditingController(
    text: _p == null ? null : kopecksToInput(_p!.priceKopecks),
  );
  late final _cost = TextEditingController(
    text: _p == null ? null : kopecksToInput(_p!.costKopecks),
  );
  late final _min = TextEditingController(
    text: _p == null ? null : formatQty(_p!.minStockMilli),
  );
  final _initial = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _price, _cost, _min, _initial]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _namePlaceholder => switch (_kind) {
    ProductKind.oil => 'Например: Mobil 1 5W-30',
    ProductKind.filter || ProductKind.oilFilter => 'Например: Mann W 712',
    ProductKind.airFilter => 'Например: Воздушный фильтр Mann',
    ProductKind.cabinFilter => 'Например: Салонный фильтр Mann',
    ProductKind.fluid ||
    ProductKind.antifreeze => 'Например: Антифриз Felix G12',
    ProductKind.tosol => 'Например: Тосол А-40',
    ProductKind.distilledWater => 'Например: Дистиллированная вода 5 л',
    ProductKind.washerFluid => 'Например: Стеклоомывающая жидкость −20°',
    ProductKind.brakeFluid => 'Например: Тормозная жидкость DOT-4',
    ProductKind.gearOil => 'Например: Castrol ATF Dex III',
    ProductKind.other || ProductKind.sparkPlug => 'Например: Свечи NGK',
    ProductKind.ignitionCoil => 'Например: Катушка зажигания Bosch',
    ProductKind.ignitionModule => 'Например: Модуль зажигания',
  };

  String get _nameHint => switch (_kind) {
    ProductKind.oil =>
      'Моторное масло: марка и вязкость, например Lukoil 10W-40.',
    ProductKind.filter || ProductKind.oilFilter => 'Масляный фильтр и артикул.',
    ProductKind.airFilter => 'Воздушный фильтр и артикул.',
    ProductKind.cabinFilter => 'Салонный фильтр и артикул.',
    ProductKind.fluid || ProductKind.antifreeze => 'Антифриз.',
    ProductKind.tosol => 'Тосол.',
    ProductKind.distilledWater => 'Дистиллированная вода.',
    ProductKind.washerFluid => 'Стеклоомывающая жидкость.',
    ProductKind.brakeFluid => 'Тормозная жидкость.',
    ProductKind.gearOil => 'Масло для коробки передач: ATF, 75W-90, DSG и т.д.',
    ProductKind.other || ProductKind.sparkPlug => 'Свечи зажигания.',
    ProductKind.ignitionCoil => 'Катушки зажигания.',
    ProductKind.ignitionModule => 'Модули зажигания.',
  };

  String get _unitHint => switch (_kind) {
    ProductKind.oil ||
    ProductKind.gearOil => 'Масло всегда считается в литрах.',
    ProductKind.fluid ||
    ProductKind.antifreeze ||
    ProductKind.tosol ||
    ProductKind.distilledWater ||
    ProductKind.washerFluid ||
    ProductKind.brakeFluid => 'Жидкости всегда считаются в литрах.',
    _ => 'Фильтры и прочие товары всегда считаются в штуках.',
  };

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Напишите название товара');
      return;
    }
    final repo = ref.read(inventoryRepositoryProvider);
    final price = parseMoney(_price.text);
    final cost = parseMoney(_cost.text);
    final min = parseQty(_min.text);
    final gearbox = _kind == ProductKind.gearOil ? _gear : null;

    if (_p == null) {
      await repo.addProduct(
        name: _name.text,
        kind: _kind,
        unit: _unit,
        priceKopecks: price,
        costKopecks: cost,
        minStockMilli: min,
        gearbox: gearbox,
        initialStockMilli: parseQty(_initial.text),
      );
    } else {
      await repo.updateProduct(
        _p!.id,
        name: _name.text,
        kind: _kind,
        unit: _unit,
        priceKopecks: price,
        costKopecks: cost,
        minStockMilli: min,
        gearbox: gearbox,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const decimal = TextInputType.numberWithOptions(decimal: true);

    return FormPage(
      title: _p == null ? 'Новый товар' : 'Изменить товар',
      onSave: _save,
      error: _error,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Center(child: ProductIcon(_kind, size: 64)),
        ),
        LiquidSection(
          header: const Text('Что это за товар'),
          footer: Text(_nameHint),
          children: [
            PillTabs<_Type>(
              value: _type,
              items: const {
                _Type.oil: 'Масло',
                _Type.filter: 'Фильтр',
                _Type.fluid: 'Жидкость',
                _Type.other: 'Прочее',
              },
              onChanged: (t) => setState(() {
                _type = t;
                _specific = switch (t) {
                  _Type.filter => ProductKind.oilFilter,
                  _Type.fluid => ProductKind.antifreeze,
                  _Type.other => ProductKind.sparkPlug,
                  _Type.oil => ProductKind.oil,
                };
                if (t == _Type.oil) _forGearbox = false;
              }),
            ),
            // Вложенные переключатели для масла, как на складе.
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                children: [
                  if (_type == _Type.oil)
                    PillTabs<bool>(
                      value: _forGearbox,
                      items: const {
                        false: 'Двигатель',
                        true: 'Коробка передач',
                      },
                      onChanged: (v) => setState(() => _forGearbox = v),
                    ),
                  if (_type == _Type.oil && _forGearbox)
                    PillTabs<GearboxType>(
                      value: _gear,
                      items: {for (final g in GearboxType.values) g: g.label},
                      onChanged: (g) => setState(() => _gear = g),
                    ),
                  if (_type == _Type.filter)
                    PillTabs<ProductKind>(
                      value: _specific,
                      items: const {
                        ProductKind.oilFilter: 'Масляный',
                        ProductKind.airFilter: 'Воздушный',
                        ProductKind.cabinFilter: 'Салонный',
                      },
                      onChanged: (kind) => setState(() => _specific = kind),
                    ),
                  if (_type == _Type.fluid)
                    PillTabs<ProductKind>(
                      value: _specific,
                      items: const {
                        ProductKind.antifreeze: 'Антифриз',
                        ProductKind.tosol: 'Тосол',
                        ProductKind.distilledWater: 'Дист. вода',
                        ProductKind.washerFluid: 'Омывающая',
                        ProductKind.brakeFluid: 'Тормозная',
                      },
                      onChanged: (kind) => setState(() => _specific = kind),
                    ),
                  if (_type == _Type.other)
                    PillTabs<ProductKind>(
                      value: _specific,
                      items: const {
                        ProductKind.sparkPlug: 'Свечи',
                        ProductKind.ignitionCoil: 'Катушка',
                        ProductKind.ignitionModule: 'Модуль',
                      },
                      onChanged: (kind) => setState(() => _specific = kind),
                    ),
                ],
              ),
            ),
            FormRow(
              label: 'Название',
              controller: _name,
              placeholder: _namePlaceholder,
              capitalization: TextCapitalization.sentences,
            ),
          ],
        ),
        // Единица измерения: только показываем, менять нельзя.
        LiquidSection(
          header: const Text('В чём считаем'),
          footer: Text(_unitHint),
          children: [
            CupertinoListTile(
              leading: const Icon(
                CupertinoIcons.lock_fill,
                size: 20,
                color: CupertinoColors.systemGrey,
              ),
              title: const Text('Считаем в'),
              additionalInfo: Text(
                _unitName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        LiquidSection(
          header: const Text('Цены, ₽'),
          footer: Text('Указывайте цену за 1 $_unit.'),
          children: [
            FormRow(
              label: 'Продаём по',
              controller: _price,
              placeholder: 'Сколько берём с клиента',
              keyboardType: decimal,
            ),
            FormRow(
              label: 'Купили по',
              controller: _cost,
              placeholder: 'Необязательно',
              keyboardType: decimal,
            ),
          ],
        ),
        if (_p == null)
          LiquidSection(
            header: const Text('Сколько есть сейчас'),
            footer: Text('Сколько $_unit лежит на складе прямо сейчас.'),
            children: [
              FormRow(
                label: 'Количество',
                controller: _initial,
                placeholder: '0',
                keyboardType: decimal,
              ),
            ],
          )
        else
          const Hint(
            'Остаток меняют кнопки «Пополнить» и «Пересчитать» на странице товара.',
          ),
        LiquidSection(
          header: const Text('Предупредить, если останется меньше'),
          footer: const Text(
            'Тогда товар станет оранжевым. Пусто: не предупреждать.',
          ),
          children: [
            FormRow(
              label: 'Меньше чем',
              controller: _min,
              placeholder: 'Например: 10',
              keyboardType: decimal,
            ),
          ],
        ),
      ],
    );
  }
}
