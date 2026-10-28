import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/form_row.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../inventory/providers.dart';
import '../data/kit_extras.dart';
import '../providers.dart';
import 'order_widgets.dart';

/// item != null: изменение строки.
/// product != null: добавление товара.
/// иначе: добавление работы.
class OrderItemFormPage extends ConsumerStatefulWidget {
  const OrderItemFormPage({
    super.key,
    required this.orderId,
    this.product,
    this.item,
  });
  final String orderId;
  final Product? product;
  final OrderItem? item;

  @override
  ConsumerState<OrderItemFormPage> createState() => _OrderItemFormPageState();
}

class _OrderItemFormPageState extends ConsumerState<OrderItemFormPage> {
  static const _workNames = [
    'Замена масла',
    'Замена масляного фильтра',
    'Замена воздушного фильтра',
    'Замена салонного фильтра',
    'Диагностика',
  ];
  static const _oilLitres = ['3', '3,5', '4', '4,5', '5', '6'];
  static const _fluidLitres = ['1', '2', '4', '5'];

  OrderItem? get _item => widget.item;
  Product? get _product => widget.product;
  bool get _isWork =>
      _item != null ? _item!.kind == ItemKind.work : _product == null;

  late final _title = TextEditingController(text: _item?.title);
  late final _qty = TextEditingController(
    text: _item != null ? formatQty(_item!.qtyMilli) : '1',
  );
  late final _price = TextEditingController(
    text: _item != null
        ? kopecksToInput(_item!.priceKopecks)
        : (_product != null ? kopecksToInput(_product!.priceKopecks) : null),
  );
  String? _error;
  int? _lastQty; // литраж прошлого раза у этой машины (только для масла)

  @override
  void initState() {
    super.initState();
    final p = _product;
    // Для масла при добавлении подсматриваем литраж прошлого заказа.
    if (p != null && _item == null && p.kind == ProductKind.oil) {
      ref.read(ordersRepositoryProvider).lastKit(widget.orderId).then((k) {
        final last = k.oil?.qtyMilli;
        if (!mounted || last == null) return;
        setState(() {
          _lastQty = last;
          if (_qty.text == '1') {
            _qty.text = formatQty(last);
          }
        });
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _qty, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Разбирает поле «Название» на отдельные работы по запятой.
  List<String> get _parts => _title.text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// Нажали на подсказку: дописываем через запятую или убираем.
  void _toggleWork(String name) {
    final parts = _parts;
    parts.contains(name) ? parts.remove(name) : parts.add(name);
    _title.text = parts.join(', ');
  }

  /// Сколько этого товара ещё можно положить в заказ:
  /// остаток склада минус то, что уже лежит в других строках заказа.
  /// Для работ возвращает null (ограничения нет).
  int? _available() {
    final pid = _product?.id ?? _item?.productId;
    if (pid == null) return null;
    final stock =
        _product?.stockMilli ??
        (ref.read(productsProvider).value ?? <Product>[])
            .where((p) => p.id == pid)
            .firstOrNull
            ?.stockMilli;
    if (stock == null) return null;
    final others =
        (ref.read(orderItemsProvider(widget.orderId)).value ?? <OrderItem>[])
            .where((i) => i.productId == pid && i.id != _item?.id)
            .fold<int>(0, (s, i) => s + i.qtyMilli);
    return stock - others;
  }

  Future<void> _save() async {
    final qty = parseQty(_qty.text);
    final price = parseMoney(_price.text);
    if (_isWork && _title.text.trim().isEmpty) {
      setState(() => _error = 'Напишите, какая работа');
      return;
    }
    if (qty <= 0) {
      setState(() => _error = 'Количество должно быть больше нуля');
      return;
    }
    // Не даём положить в заказ больше, чем есть на складе.
    final free = _available();
    if (free != null && qty > free) {
      setState(
        () => _error = free <= 0
            ? 'Этого товара на складе больше нет'
            : 'На складе доступно только ${formatQty(free)}',
      );
      return;
    }
    final repo = ref.read(ordersRepositoryProvider);
    final item = _item;
    if (item != null) {
      await repo.updateItem(
        item,
        title: _isWork ? _title.text : item.title,
        qtyMilli: qty,
        priceKopecks: price,
      );
    } else if (_product != null) {
      await repo.addProductItem(
        widget.orderId,
        _product!,
        qtyMilli: qty,
        priceKopecks: price,
      );
    } else {
      await repo.addWorkItem(
        widget.orderId,
        title: _title.text,
        qtyMilli: qty,
        priceKopecks: price,
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    const decimal = TextInputType.numberWithOptions(decimal: true);
    final p = _product;

    return FormPage(
      title: _item == null
          ? (_isWork ? 'Новая работа' : 'Добавить товар')
          : 'Изменить строку',
      onSave: _save,
      error: _error,
      children: [
        if (_isWork)
          LiquidSection(
            header: const Text('Что сделали'),
            footer: const Text(
              'Нажимайте на подсказки, чтобы добавить. Нажмите ещё раз, чтобы убрать.',
            ),
            children: [
              FormRow(
                label: 'Название',
                controller: _title,
                placeholder: 'Замена масла',
                capitalization: TextCapitalization.sentences,
              ),
              ListenableBuilder(
                listenable: _title,
                builder: (_, _) => QuickChips(
                  _workNames,
                  _toggleWork,
                  selected: _parts.toSet(),
                ),
              ),
            ],
          ),
        LiquidSection(
          header: Text(
            _isWork ? 'Сколько и по какой цене' : (p?.name ?? _item!.title),
          ),
          footer: ListenableBuilder(
            listenable: Listenable.merge([_qty, _price]),
            builder: (_, _) {
              final qty = parseQty(_qty.text);
              final sum = (qty * parseMoney(_price.text) + 500) ~/ 1000;
              final free = _available();
              final short = free != null && qty > free;
              final stock = free == null
                  ? ''
                  : ' Доступно: ${formatQty(free < 0 ? 0 : free)}.'
                        '${short ? ' Больше нельзя.' : ''}';
              return Text(
                'Сумма: ${formatMoney(sum)}.$stock',
                style: short
                    ? const TextStyle(color: CupertinoColors.systemRed)
                    : null,
              );
            },
          ),
          children: [
            FormRow(
              label: 'Количество',
              controller: _qty,
              placeholder: '1',
              keyboardType: decimal,
            ),
            // Быстрые литры для масла и жидкостей при добавлении.
            if (p != null && _item == null && p.unit == 'л') ...[
              ListenableBuilder(
                listenable: _qty,
                builder: (_, _) => QuickChips(
                  p.kind == ProductKind.oil ? _oilLitres : _fluidLitres,
                  (s) => _qty.text = s,
                  selected: {_qty.text},
                ),
              ),
              if (_lastQty != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text(
                    'В прошлый раз у этой машины: ${formatQty(_lastQty!)} л',
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                ),
            ],
            FormRow(
              label: 'Цена, ₽',
              controller: _price,
              placeholder: 'За единицу',
              keyboardType: decimal,
            ),
          ],
        ),
      ],
    );
  }
}
