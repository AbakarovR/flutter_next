import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../inventory/providers.dart';
import '../../inventory/product_ext.dart';
import '../data/engine_extras.dart';
import '../data/kit_extras.dart';
import '../data/work_extras.dart';
import '../providers.dart';
import '../ui/order_widgets.dart';

/// Выбранный фильтр: вариант (0 масляный, 1 воздушный, 2 салонный, -1 другой),
/// товар со склада и цена работы по его замене.
class _FilterRow {
  _FilterRow(this.variant, this.product, int workKopecks)
    : price = TextEditingController(
        text: workKopecks > 0 ? kopecksToInput(workKopecks) : null,
      );

  final int variant;
  Product product;
  final TextEditingController price;
}

/// Другой товар со склада и его количество.
class _ExtraRow {
  _ExtraRow(this.product, int qtyMilli)
    : qty = TextEditingController(text: formatQty(qtyMilli));

  Product product;
  final TextEditingController qty;
}

/// Снимок окна на момент открытия: к нему возвращает «Сбросить».
class _Snap {
  const _Snap(
    this.withOil,
    this.oil,
    this.qty,
    this.filters,
    this.extras,
    this.sig,
  );
  final bool withOil;
  final Product? oil;
  final String qty, sig;
  final List<(int, Product, String)> filters;
  final List<(Product, String)> extras;
}

/// Окно «Двигатель»: замена масла, фильтры и другие товары одним действием.
/// Всё связано со складом: больше, чем есть, добавить нельзя.
class EnginePage extends ConsumerStatefulWidget {
  const EnginePage({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<EnginePage> createState() => _EnginePageState();
}

class _EnginePageState extends ConsumerState<EnginePage> {
  static const _decimal = TextInputType.numberWithOptions(decimal: true);
  static const _litres = ['3', '3,5', '4', '4,5', '5', '6'];
  static final _oilKey = Object();

  /// (подпись, часть названия товара, название работы)
  static const _variants = [
    ('Масляный фильтр', 'масл', 'Замена масляного фильтра'),
    ('Воздушный фильтр', 'воздуш', 'Замена воздушного фильтра'),
    ('Салонный фильтр', 'салон', 'Замена салонного фильтра'),
  ];

  bool _ready = false;
  List<Product> _products = [];
  Map<String, int> _inOrder = {}; // товар → сколько уже лежит в заказе
  Set<String> _workTitles = {}; // работы, которые уже есть в заказе
  Map<String, int> _prices = {}; // последние цены работ

  bool _withOil = true;
  Product? _oil;
  int? _lastQty; // литраж прошлого раза
  final _qty = TextEditingController();

  final _filters = <_FilterRow>[];
  final _extras = <_ExtraRow>[];
  final _ctrls = <TextEditingController>[]; // все контроллеры для dispose

  _Snap? _snap;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qty.dispose();
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  // ───────────── Склад ─────────────

  /// Сколько товара ещё свободно: склад минус заказ минус всё, что выбрано
  /// в этом окне. [except] — строка, которую не считаем (для её собственного
  /// максимума).
  int _free(Product? p, [Object? except]) {
    if (p == null) return 0;
    var used = _inOrder[p.id] ?? 0;
    if (except != _oilKey && _withOil && _oil?.id == p.id) {
      used += parseQty(_qty.text);
    }
    for (final f in _filters) {
      if (f != except && f.product.id == p.id) used += 1000;
    }
    for (final e in _extras) {
      if (e != except && e.product.id == p.id) used += parseQty(e.qty.text);
    }
    return p.stockMilli - used;
  }

  /// Есть ли что взять: литровым достаточно любого остатка, штучным нужна 1 шт.
  bool _has(Product p) => p.unit == 'л' ? _free(p) > 0 : _free(p) >= 1000;

  Color _leftColor(Product p, int left) => left <= 0
      ? CupertinoColors.systemRed
      : (p.minStockMilli > 0 && left <= p.minStockMilli
            ? CupertinoColors.systemOrange
            : CupertinoColors.systemGreen);

  /// Подпись «Останется на складе: …».
  Widget _leftText(Product p, int left, {String extra = ''}) => Text(
    left < 0
        ? 'Больше, чем на складе'
        : 'Останется на складе: ${formatQty(left)} ${p.unit}$extra',
    style: TextStyle(
      fontSize: 14,
      color: left < 0 ? CupertinoColors.systemRed : _leftColor(p, left),
    ),
  );

  // ───────────── Фильтры ─────────────

  String _filterTitle(_FilterRow f) =>
      f.variant >= 0 ? _variants[f.variant].$3 : 'Замена: ${f.product.name}';

  _FilterRow _newFilter(int variant, Product p) {
    final title = variant >= 0 ? _variants[variant].$3 : '';
    final r = _FilterRow(variant, p, _prices[title] ?? 0);
    _ctrls.add(r.price);
    return r;
  }

  _ExtraRow _newExtra(Product p, int qty) {
    final r = _ExtraRow(p, qty);
    _ctrls.add(r.qty);
    return r;
  }

  /// К какому варианту относится фильтр по типу товара.
  int _variantOf(Product p) {
    final kindVariant = switch (p.kind) {
      ProductKind.oilFilter => 0,
      ProductKind.airFilter => 1,
      ProductKind.cabinFilter => 2,
      _ => -1,
    };
    if (kindVariant >= 0) {
      return _filters.any((f) => f.variant == kindVariant) ? -1 : kindVariant;
    }

    // Для старых записей без отдельного вида фильтра определяем его
    // по названию. Неизвестный тип не назначаем одному из трёх слотов.
    final n = p.name.toLowerCase();
    for (var v = 0; v < _variants.length; v++) {
      if (n.contains(_variants[v].$2) && !_filters.any((f) => f.variant == v)) {
        return v;
      }
    }
    return -1;
  }

  // ───────────── Загрузка ─────────────

  Future<void> _load() async {
    final repo = ref.read(ordersRepositoryProvider);
    final kit = await repo.lastKit(widget.orderId);
    final prices = await repo.lastWorkPrices();
    final all = await ref.read(productsProvider.future);
    final items = await ref.read(orderItemsProvider(widget.orderId).future);
    if (!mounted) return;

    final inOrder = <String, int>{};
    for (final i in items) {
      final id = i.productId;
      if (id != null) inOrder[id] = (inOrder[id] ?? 0) + i.qtyMilli;
    }

    setState(() {
      _products = all;
      _inOrder = inOrder;
      _prices = prices;
      _workTitles = {
        for (final i in items)
          if (i.kind == ItemKind.work) i.title,
      };

      // Прошлое масло, если есть на складе; иначе единственное в наличии.
      final oils = all
          .where(
            (p) =>
                p.kind == ProductKind.oil &&
                p.stockMilli - (inOrder[p.id] ?? 0) > 0,
          )
          .toList();
      _oil =
          oils.where((p) => p.id == kit.oil?.productId).firstOrNull ??
          (oils.length == 1 ? oils.first : null);
      _lastQty = kit.oil?.qtyMilli;
      final last = _lastQty;
      if (_oil != null && last != null && last <= _free(_oil, _oilKey)) {
        _qty.text = formatQty(last);
      }

      // Фильтры из прошлой замены этой машины (только те, что есть в наличии).
      for (final id in kit.filterIds) {
        final p = all.where((x) => x.id == id).firstOrNull;
        if (p != null && _free(p) >= 1000) {
          _filters.add(_newFilter(_variantOf(p), p));
        }
      }

      _takeSnapshot();
      _ready = true;
    });
  }

  String get _sig => [
    _withOil,
    _oil?.id,
    _qty.text,
    ..._filters.map((f) => '${f.variant}:${f.product.id}:${f.price.text}'),
    ..._extras.map((e) => '${e.product.id}:${e.qty.text}'),
  ].join('|');

  void _takeSnapshot() {
    _snap = _Snap(
      _withOil,
      _oil,
      _qty.text,
      [for (final f in _filters) (f.variant, f.product, f.price.text)],
      [for (final e in _extras) (e.product, e.qty.text)],
      _sig,
    );
  }

  bool get _changed => _snap != null && _snap!.sig != _sig;

  void _reset() => setState(() {
    final s = _snap!;
    _withOil = s.withOil;
    _oil = s.oil;
    _qty.text = s.qty;
    _filters
      ..clear()
      ..addAll([
        for (final (v, p, t) in s.filters) _newFilter(v, p)..price.text = t,
      ]);
    _extras
      ..clear()
      ..addAll([for (final (p, t) in s.extras) _newExtra(p, 0)..qty.text = t]);
    _error = null;
  });

  // ───────────── Выбор товара ─────────────

  /// Меню выбора товара. Закончившиеся серые и не выбираются.
  Future<Product?> _choose(String title, List<Product> list) =>
      showCupertinoModalPopup<Product>(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          title: Text(title),
          message: list.isEmpty
              ? const Text(
                  'Подходящих товаров нет. Добавьте их на вкладке «Склад».',
                )
              : null,
          actions: [
            for (final p in list)
              if (_has(p))
                CupertinoActionSheetAction(
                  onPressed: () => Navigator.pop(ctx, p),
                  child: Text(
                    '${p.name} · осталось ${formatQty(_free(p))} ${p.unit}',
                  ),
                )
              else
                CupertinoActionSheetAction(
                  onPressed: () {},
                  child: Text(
                    '${p.name} · нет в наличии',
                    style: const TextStyle(color: CupertinoColors.systemGrey),
                  ),
                ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
        ),
      );

  Future<void> _pickOil() async {
    final p = await _choose(
      'Выберите масло',
      _products.where((p) => p.kind == ProductKind.oil).toList(),
    );
    if (p == null || !mounted) return;
    setState(() {
      _oil = p;
      if (parseQty(_qty.text) > _free(p, _oilKey)) _qty.clear();
    });
  }

  /// Фильтр нельзя назначить в два блока одновременно. При изменении
  /// текущая строка исключается из проверки, чтобы оставить её товар.
  List<Product> _availableFilters({int? variant, _FilterRow? except}) =>
      _products
          .where(
            (p) =>
                p.kind.isFilter &&
                !_filters.any(
                  (f) => !identical(f, except) && f.product.id == p.id,
                ) &&
                (variant == null || _matchesVariant(p, variant)),
          )
          .toList();

  List<Product> get _freeFilters => _availableFilters();

  bool _matchesVariant(Product p, int variant) {
    final expected = switch (variant) {
      0 => ProductKind.oilFilter,
      1 => ProductKind.airFilter,
      2 => ProductKind.cabinFilter,
      _ => null,
    };
    if (expected == null) return false;
    if (p.kind == expected) return true;

    // Совместимость с товарами старой базы, где фильтры ещё были общим типом.
    if (p.kind != ProductKind.filter) return false;
    return p.name.toLowerCase().contains(_variants[variant].$2);
  }

  Future<void> _toggleVariant(int v) async {
    HapticFeedback.selectionClick();
    final i = _filters.indexWhere((f) => f.variant == v);
    if (i >= 0) {
      setState(() => _filters.removeWhere((f) => f.variant == v));
      return;
    }
    final pool = _availableFilters(variant: v);
    Product? p;
    if (pool.length == 1 && _has(pool.first)) {
      p = pool.first;
    } else {
      p = await _choose(
        'Выберите фильтр (${_variants[v].$1.toLowerCase()})',
        pool,
      );
    }
    if (p == null || !mounted) return;
    final selected = p;
    if (_filters.any((f) => f.variant == v || f.product.id == selected.id)) {
      setState(() => _error = 'Этот фильтр уже выбран в заказе');
      return;
    }
    setState(() {
      _error = null;
      _filters.add(_newFilter(v, selected));
    });
  }

  Future<void> _addOtherFilter() async {
    final p = await _choose('Выберите фильтр', _freeFilters);
    if (p == null || !mounted) return;
    if (_filters.any((f) => f.product.id == p.id)) {
      setState(() => _error = 'Этот фильтр уже выбран в заказе');
      return;
    }
    setState(() {
      _error = null;
      _filters.add(_newFilter(-1, p));
    });
  }

  Future<void> _changeFilter(_FilterRow f) async {
    final v = f.variant;
    final pool = _availableFilters(variant: v < 0 ? null : v, except: f);
    final p = await _choose('Выберите фильтр', pool);
    if (p == null || !mounted) return;
    if (_filters.any(
      (other) => !identical(other, f) && other.product.id == p.id,
    )) {
      setState(() => _error = 'Этот фильтр уже выбран в другом разделе');
      return;
    }
    if (v >= 0 && !_matchesVariant(p, v)) return;
    setState(() {
      _error = null;
      f.product = p;
    });
  }

  Future<void> _addExtra() async {
    final pool = _products
        .where(
          (p) =>
              (p.kind.isFluid || p.kind.isOther) &&
              !_extras.any((e) => e.product.id == p.id),
        )
        .toList();
    final p = await _choose('Выберите товар', pool);
    if (p == null || !mounted) return;
    final free = _free(p);
    setState(() => _extras.add(_newExtra(p, free >= 1000 ? 1000 : free)));
  }

  // ───────────── Итог и сохранение ─────────────

  int get _total {
    var sum = 0;
    final oil = _oil;
    if (_withOil && oil != null) {
      sum += (parseQty(_qty.text) * oil.priceKopecks + 500) ~/ 1000;
    }
    for (final f in _filters) {
      sum += f.product.priceKopecks;
      if (!_workTitles.contains(_filterTitle(f))) {
        sum += parseMoney(f.price.text);
      }
    }
    for (final e in _extras) {
      sum += (parseQty(e.qty.text) * e.product.priceKopecks + 500) ~/ 1000;
    }
    return sum;
  }

  Future<void> _save() async {
    final oil = _withOil ? _oil : null;
    final oilQty = parseQty(_qty.text);

    final filterIds = _filters.map((f) => f.product.id).toSet();
    final specificVariants = _filters
        .where((f) => f.variant >= 0)
        .map((f) => f.variant)
        .toSet();
    if (filterIds.length != _filters.length ||
        specificVariants.length !=
            _filters.where((f) => f.variant >= 0).length) {
      setState(() => _error = 'Каждый фильтр можно добавить только один раз');
      return;
    }

    if (_withOil && (oil == null || oilQty <= 0)) {
      setState(
        () =>
            _error = 'Выберите масло и количество или отключите «Менять масло»',
      );
      return;
    }
    if (oil == null && _filters.isEmpty && _extras.isEmpty) {
      setState(() => _error = 'Добавьте масло, фильтр или товар');
      return;
    }
    for (final e in _extras) {
      if (parseQty(e.qty.text) <= 0) {
        setState(() => _error = 'Укажите количество: ${e.product.name}');
        return;
      }
    }

    // Общая проверка склада: сколько всего хотим взять по каждому товару.
    final uses = <String, int>{};
    void use(Product p, int q) => uses[p.id] = (uses[p.id] ?? 0) + q;
    if (oil != null) use(oil, oilQty);
    for (final f in _filters) {
      use(f.product, 1000);
    }
    for (final e in _extras) {
      use(e.product, parseQty(e.qty.text));
    }
    for (final entry in uses.entries) {
      final p = _products.firstWhere((x) => x.id == entry.key);
      final free = p.stockMilli - (_inOrder[p.id] ?? 0);
      if (entry.value > free) {
        setState(
          () => _error = free <= 0
              ? '«${p.name}» на складе больше нет'
              : '«${p.name}»: доступно только ${formatQty(free)} ${p.unit}',
        );
        return;
      }
    }

    // Работа без цены не добавляется, дубли работ тоже.
    final works = <(String, int)>[];
    for (final f in _filters) {
      final t = _filterTitle(f);
      final price = parseMoney(f.price.text);
      if (price > 0 && !_workTitles.contains(t)) works.add((t, price));
    }

    await ref
        .read(ordersRepositoryProvider)
        .addEngineJob(
          widget.orderId,
          oil: oil,
          oilQtyMilli: oilQty,
          filters: [for (final f in _filters) f.product],
          extras: [for (final e in _extras) (e.product, parseQty(e.qty.text))],
          works: works,
        );
    if (mounted) Navigator.pop(context, true);
  }

  // ───────────── Мелкие виджеты ─────────────

  /// Круглая кнопка «+» или «−». Если [onTap] == null, она серая и неактивна.
  Widget _round(IconData icon, VoidCallback? onTap, {bool minus = false}) {
    final primary = CupertinoTheme.of(context).primaryColor;
    final active = onTap != null;
    final box = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: active && !minus ? softGradient(primary) : null,
        color: !active
            ? CupertinoColors.systemGrey5.resolveFrom(context)
            : (minus ? CupertinoColors.systemRed.withAlpha(30) : null),
      ),
      child: Icon(
        icon,
        size: 20,
        color: !active
            ? CupertinoColors.systemGrey3.resolveFrom(context)
            : (minus ? CupertinoColors.systemRed : CupertinoColors.white),
      ),
    );
    return active ? Pressable(onTap: onTap, child: box) : box;
  }

  void _set(TextEditingController c, int milli) =>
      c.text = milli <= 0 ? '' : formatQty(milli);

  /// «[−] 4,5 [+]»: шаг [step], выше [max] подняться нельзя.
  Widget _qtyControl(
    TextEditingController c,
    int step,
    int Function() max, {
    double width = 84,
  }) => ListenableBuilder(
    listenable: c,
    builder: (_, _) {
      final q = parseQty(c.text);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _round(
            CupertinoIcons.minus,
            q > 0 ? () => _set(c, q - step < 0 ? 0 : q - step) : null,
            minus: true,
          ),
          SizedBox(
            width: width,
            child: CupertinoTextField(
              controller: c,
              placeholder: '0',
              textAlign: TextAlign.center,
              decoration: null,
              keyboardType: _decimal,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          _round(
            CupertinoIcons.add,
            q + step <= max() ? () => _set(c, q + step) : null,
          ),
        ],
      );
    },
  );

  /// Поле цены работы или пометка «уже в заказе».
  Widget _priceField(String title, TextEditingController c) =>
      _workTitles.contains(title)
      ? const Text(
          'уже в заказе',
          style: TextStyle(color: CupertinoColors.systemGrey),
        )
      : SizedBox(
          width: 110,
          child: CupertinoTextField(
            controller: c,
            placeholder: 'Цена',
            suffix: const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Text(
                '₽',
                style: TextStyle(color: CupertinoColors.systemGrey),
              ),
            ),
            textAlign: TextAlign.right,
            decoration: null,
            keyboardType: _decimal,
          ),
        );

  /// Капсула «Масляный | Воздушный | Салонный» на всю ширину.
  Widget _variantBar() {
    final primary = CupertinoTheme.of(context).primaryColor;
    final track = CupertinoColors.tertiarySystemFill.resolveFrom(context);
    final text = CupertinoColors.label.resolveFrom(context);
    final line = CupertinoColors.separator.resolveFrom(context);
    final n = _variants.length;
    bool on(int i) => _filters.any((f) => f.variant == i);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: track,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            for (var i = 0; i < n; i++)
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _toggleVariant(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: on(i) ? primary : CupertinoColors.transparent,
                          borderRadius: BorderRadius.circular(19),
                          boxShadow: on(i)
                              ? [
                                  BoxShadow(
                                    color: primary.withAlpha(80),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : const [],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: on(i)
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: on(i) ? CupertinoColors.white : text,
                              ),
                              child: Text(
                                _variants[i].$1,
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (i < n - 1)
                      Align(
                        alignment: Alignment.centerRight,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: (on(i) || on(i + 1)) ? 0 : 1,
                            child: Container(width: 1, height: 18, color: line),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Строка фильтра: название, остаток, «−» и цена работы.
  Widget _filterTile(_FilterRow f) {
    final title = _filterTitle(f);
    return Padding(
      key: ObjectKey(f),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _changeFilter(f),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.product.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      _leftText(f.product, _free(f.product)),
                    ],
                  ),
                ),
              ),
              _round(
                CupertinoIcons.minus,
                () => setState(() => _filters.remove(f)),
                minus: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              ),
              _priceField(title, f.price),
            ],
          ),
        ],
      ),
    );
  }

  /// Строка другого товара: название, остаток, количество, удаление.
  Widget _extraTile(_ExtraRow e) {
    final step = 1000; // жидкости и штучные: шаг 1
    return Padding(
      key: ObjectKey(e),
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
      child: Row(
        children: [
          CupertinoButton(
            padding: const EdgeInsets.all(6),
            minimumSize: Size.zero,
            onPressed: () => setState(() => _extras.remove(e)),
            child: const Icon(
              CupertinoIcons.minus_circle_fill,
              color: CupertinoColors.systemRed,
              size: 22,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.product.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                ListenableBuilder(
                  listenable: e.qty,
                  builder: (_, _) => _leftText(e.product, _free(e.product)),
                ),
              ],
            ),
          ),
          _qtyControl(e.qty, step, () => _free(e.product, e), width: 56),
        ],
      ),
    );
  }

  /// Строка-кнопка «+ …» в конце блока.
  Widget _addTile(String label, VoidCallback onTap) {
    final primary = CupertinoTheme.of(context).primaryColor;
    return CupertinoListTile(
      leading: Icon(CupertinoIcons.add_circled_solid, color: primary),
      title: Text(
        label,
        style: TextStyle(color: primary, fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    );
  }

  // ───────────── Экран ─────────────

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const AppPage(title: 'Двигатель', children: [Loading()]);
    }
    final oil = _oil;
    final oilStep = oil?.unit == 'шт' ? 1000 : 500;
    final merged = Listenable.merge([
      _qty,
      for (final f in _filters) f.price,
      for (final e in _extras) e.qty,
    ]);

    return FormPage(
      title: 'Двигатель',
      onSave: _save,
      error: _error,
      children: [
        // ── Замена масла ──
        LiquidSection(
          header: const Text('Замена масла'),
          footer: _withOil
              ? ListenableBuilder(
                  listenable: _qty,
                  builder: (_, _) {
                    final o = _oil;
                    if (o == null) {
                      return const Text(
                        'Выберите масло. Закончившееся выбрать нельзя.',
                      );
                    }
                    final inOrder = _inOrder[o.id] ?? 0;
                    final extra = [
                      if (inOrder > 0)
                        ' · в заказе уже ${formatQty(inOrder)} ${o.unit}',
                      if (_lastQty != null)
                        ' · в прошлый раз ${formatQty(_lastQty!)} ${o.unit}',
                    ].join();
                    return _leftText(o, _free(o), extra: extra);
                  },
                )
              : const Text('Масло не добавится: меняете только фильтры.'),
          children: [
            CupertinoListTile(
              title: const Text('Менять масло'),
              trailing: CupertinoSwitch(
                value: _withOil,
                onChanged: (v) => setState(() => _withOil = v),
              ),
            ),
            if (_withOil) ...[
              CupertinoListTile(
                title: const Text('Масло'),
                additionalInfo: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    oil?.name ?? 'Выбрать',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: oil == null
                        ? const TextStyle(color: CupertinoColors.systemBlue)
                        : null,
                  ),
                ),
                trailing: const CupertinoListTileChevron(),
                onTap: _pickOil,
              ),
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            oil?.unit == 'шт' ? 'Количество, шт' : 'Литров',
                          ),
                        ),
                        _qtyControl(
                          _qty,
                          oilStep,
                          () => _free(oil, _oilKey),
                          width: 60,
                        ),
                      ],
                    ),
                  ),
                  if (oil?.unit != 'шт')
                    ListenableBuilder(
                      listenable: _qty,
                      builder: (_, _) {
                        final free = _free(oil, _oilKey);
                        final shown = _litres
                            .where((s) => parseQty(s) <= free)
                            .toList();
                        return shown.isEmpty
                            ? const SizedBox.shrink()
                            : QuickChips(
                                shown,
                                (s) => _qty.text = s,
                                selected: {_qty.text},
                              );
                      },
                    ),
                ],
              ),
            ],
          ],
        ),

        // ── Замена фильтра ──
        LiquidSection(
          header: const Text('Замена фильтра'),
          footer: const Text(
            'Нажмите на вид фильтра и выберите товар со склада. У каждого своя работа и цена.',
          ),
          children: [
            _variantBar(),
            for (final f in _filters) _filterTile(f),
            _addTile('Другой фильтр', _addOtherFilter),
          ],
        ),

        // ── Другие товары ──
        LiquidSection(
          header: const Text('Другие товары'),
          footer: const Text(
            'Жидкости и прочее со склада. Спишутся при проведении заказа.',
          ),
          children: [
            for (final e in _extras) _extraTile(e),
            _addTile('Добавить товар', _addExtra),
          ],
        ),

        // ── Итог ──
        ListenableBuilder(
          listenable: merged,
          builder: (_, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                'Итого: ${formatMoney(_total)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),

        // ── Сбросить (только если что-то менялось) ──
        ListenableBuilder(
          listenable: merged,
          builder: (_, _) => _changed
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    color: CupertinoColors.systemRed.withAlpha(30),
                    borderRadius: BorderRadius.circular(16),
                    onPressed: _reset,
                    child: const Text(
                      'Сбросить',
                      style: TextStyle(
                        color: CupertinoColors.systemRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
