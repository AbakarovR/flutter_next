import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../inventory/product_ext.dart';
import '../../inventory/providers.dart';
import '../data/gearbox_extras.dart';
import '../data/gearbox_lock.dart';
import '../providers.dart';
import 'order_widgets.dart';

/// Окно «Коробка»: подбор масла и его количества для выбранного типа КПП.
/// Если коробку этой машины уже обслуживали, тип выбран сам и закреплён.
class GearboxPage extends ConsumerStatefulWidget {
  const GearboxPage({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<GearboxPage> createState() => _GearboxPageState();
}

class _GearboxPageState extends ConsumerState<GearboxPage> {
  static const _decimal = TextInputType.numberWithOptions(decimal: true);
  static final _oilKey = Object();

  bool _ready = false;
  List<Product> _products = [];
  Map<String, int> _inOrder = {}; // товар → сколько уже лежит в заказе

  GearboxType _type = GearboxType.auto;
  VehicleGearbox? _vg; // что заливали в коробку этой машины раньше
  bool _unlocked = false; // нажали «Другая коробка?»
  Product? _oil;
  int? _lastQty; // литраж прошлого раза
  final _qty = TextEditingController();

  String _initSig = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  // ───────────── Склад ─────────────

  /// Масла, подходящие для выбранного типа коробки.
  List<Product> get _oilsForType => _products
      .where((p) => p.kind == ProductKind.gearOil && p.gearbox == _type)
      .toList();

  /// Сколько масла свободно: остаток склада минус товар в заказе
  /// и количество, указанное в этом окне.
  int _free(Product? p, [Object? except]) {
    if (p == null) return 0;
    var used = _inOrder[p.id] ?? 0;
    if (except != _oilKey && _oil?.id == p.id) used += parseQty(_qty.text);
    return p.stockMilli - used;
  }

  bool _has(Product p) => p.unit == 'л' ? _free(p) > 0 : _free(p) >= 1000;

  Color _leftColor(Product p, int left) => left <= 0
      ? CupertinoColors.systemRed
      : (p.minStockMilli > 0 && left <= p.minStockMilli
            ? CupertinoColors.systemOrange
            : CupertinoColors.systemGreen);

  Widget _leftText(Product p, int left, {String extra = ''}) => Text(
    left < 0
        ? 'Больше, чем на складе'
        : 'Останется на складе: ${formatQty(left)} ${p.unit}$extra',
    style: TextStyle(
      fontSize: 14,
      color: left < 0 ? CupertinoColors.systemRed : _leftColor(p, left),
    ),
  );

  // ───────────── Загрузка и «Сбросить» ─────────────

  Future<void> _load() async {
    final repo = ref.read(ordersRepositoryProvider);
    final vg = await repo.vehicleGearbox(widget.orderId);
    final all = await ref.read(productsProvider.future);
    final items = await ref.read(orderItemsProvider(widget.orderId).future);
    if (!mounted) return;

    final inOrder = <String, int>{};
    for (final i in items) {
      final id = i.productId;
      if (id != null) inOrder[id] = (inOrder[id] ?? 0) + i.qtyMilli;
    }
    _products = all;
    _inOrder = inOrder;
    // Коробка этой машины уже известна: берём её тип и закрепляем.
    if (vg != null) {
      _vg = vg;
      _type = vg.type;
    }

    await _prefill();
    if (!mounted) return;
    setState(() {
      _initSig = _main;
      _ready = true;
    });
  }

  /// Подставляет масло, литраж и цену работы для текущего типа коробки:
  /// из прошлой замены этой машины или единственное масло в наличии.
  Future<void> _prefill() async {
    final type = _type;
    final last = await ref
        .read(ordersRepositoryProvider)
        .lastGearOil(widget.orderId, type);
    // Пока ждали ответ, тип могли переключить: тогда ответ уже не нужен.
    if (!mounted || type != _type) return;
    setState(() {
      _oil = null;
      _qty.clear();
      final list = _oilsForType.where(_has).toList();
      _oil =
          list.where((p) => p.id == last?.productId).firstOrNull ??
          (list.length == 1 ? list.first : null);
      _lastQty = last?.qtyMilli;
      final l = _lastQty;
      if (_oil != null && l != null && l <= _free(_oil, _oilKey)) {
        _qty.text = formatQty(l);
      }
    });
  }

  /// Значения, которые подставляет программа и меняет пользователь.
  /// После выбора типа новые подставленные значения становятся исходными.
  String get _main => [_oil?.id, _qty.text].join('|');

  /// «Сбросить» показываем только после изменения масла или количества.
  bool get _changed => _main != _initSig;

  /// Отмена выбора другой коробки: возвращаем закреплённый тип машины,
  /// заново подставляем масло и литры. Из окна не выходим.
  Future<void> _relock() async {
    final vg = _vg;
    if (vg == null) return;
    setState(() {
      _unlocked = false;
      _type = vg.type;
      _error = null;
    });
    await _prefill();
    if (mounted) setState(() => _initSig = _main);
  }

  void _setType(GearboxType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _error = null;
    });
    _prefill().then((_) {
      if (mounted) setState(() => _initSig = _main);
    });
  }

  /// Остаёмся на выбранном типе и возвращаем масло и количество
  /// к исходным значениям для этой коробки.
  Future<void> _reset() async {
    setState(() {
      _error = null;
    });
    await _prefill();
    if (mounted) setState(() => _initSig = _main);
  }

  // ───────────── Выбор товара ─────────────

  Future<Product?> _choose(String title, List<Product> list, String empty) =>
      showCupertinoModalPopup<Product>(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          title: Text(title),
          message: list.isEmpty ? Text(empty) : null,
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
      'Масло: ${_type.label}',
      _oilsForType,
      'Нет масла для этой коробки. Добавьте его на вкладке «Склад»: Масло → Коробка передач.',
    );
    if (p == null || !mounted) return;
    setState(() {
      _oil = p;
      if (parseQty(_qty.text) > _free(p, _oilKey)) _qty.clear();
    });
  }

  // ───────────── Итог и сохранение ─────────────

  int get _total {
    var sum = 0;
    final oil = _oil;
    if (oil != null) {
      sum += (parseQty(_qty.text) * oil.priceKopecks + 500) ~/ 1000;
    }
    return sum;
  }

  Future<void> _save() async {
    final oil = _oil;
    final oilQty = parseQty(_qty.text);

    if (oil == null) {
      setState(() => _error = 'Выберите масло для коробки передач');
      return;
    }
    if (oilQty <= 0) {
      setState(() => _error = 'Укажите, сколько литров масла');
      return;
    }

    // Общая проверка склада по каждому товару.
    final uses = <String, int>{};
    void use(Product p, int q) => uses[p.id] = (uses[p.id] ?? 0) + q;
    use(oil, oilQty);
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

    await ref
        .read(ordersRepositoryProvider)
        .addGearboxJob(
          widget.orderId,
          oil: oil,
          oilQtyMilli: oilQty,
          extras: const [],
          works: const [],
        );
    if (mounted) Navigator.pop(context, true);
  }

  // ───────────── Мелкие виджеты ─────────────

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

  /// Блок типа коробки: закреплённый (если коробку уже обслуживали)
  /// или обычный выбор АКПП / МКПП / РКПП.
  Widget _typeSection(Color primary) {
    final vg = _vg;
    if (vg != null && !_unlocked) {
      return LiquidSection(
        header: const Text('Коробка этой машины'),
        footer: const Text(
          'Тип взят из прошлого обслуживания. Ошиблись при первой записи? Нажмите «Другая коробка?».',
        ),
        children: [
          CupertinoListTile(
            leading: const Icon(
              CupertinoIcons.lock_fill,
              size: 20,
              color: CupertinoColors.systemGrey,
            ),
            title: Text(
              vg.type.fullName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'В прошлый раз: ${vg.productName} · ${formatQty(vg.qtyMilli)} л · ${dayTitle(vg.date)}',
            ),
          ),
          CupertinoListTile(
            title: Text('Другая коробка?', style: TextStyle(color: primary)),
            onTap: () => setState(() => _unlocked = true),
          ),
        ],
      );
    }
    return LiquidSection(
      header: const Text('Тип коробки'),
      footer: Text(_type.fullName),
      children: [
        // Вернуться к закреплённому типу, не выходя из окна.
        if (vg != null)
          CupertinoListTile(
            leading: Icon(CupertinoIcons.arrow_uturn_left, color: primary),
            title: Text(
              'Вернуть прежнюю: ${vg.type.label}',
              style: TextStyle(color: primary, fontWeight: FontWeight.w600),
            ),
            onTap: _relock,
          ),
        Segments<GearboxType>(
          value: _type,
          items: {for (final g in GearboxType.values) g: g.label},
          onChanged: _setType,
        ),
      ],
    );
  }

  // ───────────── Экран ─────────────

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const AppPage(title: 'Коробка', children: [Loading()]);
    }
    final primary = CupertinoTheme.of(context).primaryColor;
    final oil = _oil;
    final step = oil?.unit == 'шт' ? 1000 : 500;
    final merged = Listenable.merge([_qty]);

    return FormPage(
      title: 'Коробка',
      onSave: _save,
      error: _error,
      children: [
        // ── Тип коробки ──
        _typeSection(primary),

        // ── Масло ──
        LiquidSection(
          header: const Text('Масло в коробку'),
          footer: ListenableBuilder(
            listenable: _qty,
            builder: (_, _) {
              final o = _oil;
              if (o == null) {
                return Text(
                  _oilsForType.isEmpty
                      ? 'На складе нет масла для этой коробки. Добавьте его: Масло → Коробка передач → ${_type.label}.'
                      : 'Выберите масло. Закончившееся выбрать нельзя.',
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
          ),
          children: [
            CupertinoListTile(
              title: const Text('Масло'),
              additionalInfo: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  oil?.name ?? 'Выбрать',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: oil == null ? TextStyle(color: primary) : null,
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
                      const Expanded(child: Text('Литров')),
                      _qtyControl(
                        _qty,
                        step,
                        () => _free(oil, _oilKey),
                        width: 60,
                      ),
                    ],
                  ),
                ),
                ListenableBuilder(
                  listenable: _qty,
                  builder: (_, _) {
                    final free = _free(oil, _oilKey);
                    final shown = _type.chips
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
        ),

        // ── Другие товары ──

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
