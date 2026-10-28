import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../inventory/providers.dart';
import '../../inventory/ui/inventory_widgets.dart';
import '../../inventory/ui/product_filter.dart';
import '../providers.dart';
import 'order_item_form_page.dart';

/// Выбор товаров со склада для заказа. Окно НЕ закрывается после добавления:
/// можно добавить сколько угодно товаров и нажать «Готово».
/// «Отмена» возвращает заказ к состоянию на момент открытия окна.
class ProductPickerPage extends ConsumerStatefulWidget {
  const ProductPickerPage({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<ProductPickerPage> createState() => _ProductPickerPageState();
}

class _ProductPickerPageState extends ConsumerState<ProductPickerPage> {
  String _query = '';
  ProductFilter _filter = const ProductFilter(tab: TopTab.oil);

  /// Сколько каждого товара лежало в заказе, когда мы открыли окно.
  /// По этому снимку работают «Сбросить» и «Отмена».
  Map<String, int>? _base;

  void _changeFilter(ProductFilter filter) => setState(() {
    _filter = filter;
    _query = '';
  });

  @override
  void initState() {
    super.initState();
    ref.read(orderItemsProvider(widget.orderId).future).then((items) {
      if (mounted) setState(() => _base = _qtyByProduct(items));
    });
  }

  /// Сумма количеств по каждому товару: id товара → тысячные.
  Map<String, int> _qtyByProduct(List<OrderItem> items) {
    final m = <String, int>{};
    for (final i in items) {
      final id = i.productId;
      if (id != null) m[id] = (m[id] ?? 0) + i.qtyMilli;
    }
    return m;
  }

  List<OrderItem> get _items =>
      ref.read(orderItemsProvider(widget.orderId)).value ?? [];

  /// Отличается ли заказ от снимка при открытии окна.
  bool _differs(Map<String, int> base, Map<String, int> now) => {
    ...base.keys,
    ...now.keys,
  }.any((id) => (base[id] ?? 0) != (now[id] ?? 0));

  /// Открываем форму количества. После сохранения возвращаемся сюда же.
  Future<void> _pick(Product p) async {
    await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => OrderItemFormPage(orderId: widget.orderId, product: p),
      ),
    );
  }

  /// +1 штука. Если на складе больше нет, ничего не делаем.
  Future<void> _plus(Product p, int added) {
    if (p.stockMilli - added < 1000) return Future.value();
    return ref
        .read(ordersRepositoryProvider)
        .addProductItem(
          widget.orderId,
          p,
          qtyMilli: 1000,
          priceKopecks: p.priceKopecks,
        );
  }

  /// −1 штука. У литровых товаров убираем всю строку.
  Future<void> _minus(Product p) {
    final repo = ref.read(ordersRepositoryProvider);
    final item = _items.where((i) => i.productId == p.id).firstOrNull;
    if (item == null) return Future.value();
    if (p.unit != 'л' && item.qtyMilli > 1000) {
      return repo.updateItem(
        item,
        title: item.title,
        qtyMilli: item.qtyMilli - 1000,
        priceKopecks: item.priceKopecks,
      );
    }
    return repo.removeItem(item);
  }

  /// Возвращает заказ к снимку [base] без вопросов.
  Future<void> _revert(
    Map<String, int> base,
    Map<String, Product> products,
  ) async {
    final repo = ref.read(ordersRepositoryProvider);
    final now = _qtyByProduct(
      await ref.read(orderItemsProvider(widget.orderId).future),
    );

    for (final id in {...base.keys, ...now.keys}) {
      final target = base[id] ?? 0;
      if ((now[id] ?? 0) == target) continue;
      final items = await ref.read(orderItemsProvider(widget.orderId).future);
      final item = items.where((i) => i.productId == id).firstOrNull;
      final p = products[id];

      if (item == null) {
        if (p != null && target > 0) {
          await repo.addProductItem(
            widget.orderId,
            p,
            qtyMilli: target,
            priceKopecks: p.priceKopecks,
          );
        }
      } else if (target == 0) {
        await repo.removeItem(item);
      } else {
        await repo.updateItem(
          item,
          title: item.title,
          qtyMilli: target,
          priceKopecks: item.priceKopecks,
        );
      }
    }
  }

  /// «Сбросить добавленное»: спрашиваем и откатываем, окно остаётся открытым.
  Future<void> _reset(
    Map<String, int> base,
    Map<String, Product> products,
  ) async {
    final ok = await confirm(
      context,
      'Сбросить добавленное?',
      'Заказ вернётся к тому, что было до открытия этого окна.',
      action: 'Сбросить',
    );
    if (ok) await _revert(base, products);
  }

  /// «Отмена»: если что-то добавляли, спрашиваем, откатываем и закрываем.
  Future<void> _cancel(
    Map<String, int>? base,
    Map<String, int> now,
    Map<String, Product> products,
  ) async {
    if (base != null && _differs(base, now)) {
      final ok = await confirm(
        context,
        'Отменить добавленное?',
        'Всё, что вы добавили в этом окне, будет убрано из заказа.',
        action: 'Отменить',
      );
      if (!ok) return;
      await _revert(base, products);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(productsProvider).value;
    if (all == null) {
      return AppPage(
        title: 'Добавить товар',
        leading: NavTextButton('Отмена', onTap: () => Navigator.pop(context)),
        children: const [Loading()],
      );
    }

    // Сколько каждого товара сейчас в заказе.
    final inOrder = _qtyByProduct(
      ref.watch(orderItemsProvider(widget.orderId)).value ?? <OrderItem>[],
    );
    final products = {for (final p in all) p.id: p};

    final base = _base;
    final changed = base != null && _differs(base, inOrder);

    final q = _query.trim().toLowerCase();
    final items = all
        .where((p) => _filter.matches(p) && p.name.toLowerCase().contains(q))
        .toList();

    return AppPage(
      title: 'Добавить товар',
      leading: NavTextButton(
        'Отмена',
        onTap: () => _cancel(base, inOrder, products),
      ),
      trailing: NavTextButton(
        'Готово',
        onTap: () => Navigator.pop(context),
        primary: true,
      ),
      children: [
        SearchField(
          'Найти товар в этом разделе',
          (v) => setState(() => _query = v),
          key: ObjectKey(_filter),
        ),
        ProductFilterBar(
          key: ObjectKey(_filter),
          filter: _filter,
          showAll: false,
          onChanged: _changeFilter,
        ),
        const Hint('«+» добавляет, «−» убирает. Закончите: нажмите «Готово».'),
        // Место под кнопку есть всегда: список не сдвигается.
        changed
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  color: CupertinoColors.systemRed.withAlpha(30),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: () => _reset(base, products),
                  child: const Text(
                    'Сбросить добавленное',
                    style: TextStyle(
                      color: CupertinoColors.systemRed,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
        items.isEmpty
            ? EmptyState(
                icon: CupertinoIcons.cube_box,
                text: all.isEmpty
                    ? 'На складе нет товаров.\nДобавьте их на вкладке «Склад».'
                    : 'Ничего не найдено',
              )
            : LiquidSection(
                children: [for (final p in items) _tile(p, inOrder[p.id] ?? 0)],
              ),
      ],
    );
  }

  /// Круглая кнопка «+» или «−». Если [onTap] == null, она серая и неактивна.
  Widget _roundButton(
    IconData icon,
    VoidCallback? onTap, {
    bool minus = false,
  }) {
    final primary = CupertinoTheme.of(context).primaryColor;
    final active = onTap != null;
    final box = Container(
      width: 34,
      height: 34,
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

  Widget _tile(Product p, int added) {
    final piece = p.unit != 'л'; // штучные товары добавляем одним нажатием
    final left = p.stockMilli - added;
    final color = left <= 0
        ? CupertinoColors.systemRed
        : (p.minStockMilli > 0 && left <= p.minStockMilli
              ? CupertinoColors.systemOrange
              : CupertinoColors.systemGreen);

    return CupertinoListTile(
      leadingSize: 40,
      leading: ProductIcon(p.kind, size: 40),
      title: Text(p.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${formatMoney(p.priceKopecks)} за ${p.unit}'),
          if (added > 0)
            Text(
              left < 0
                  ? 'В заказе: ${formatQty(added)} ${p.unit} · больше, чем на складе'
                  : 'В заказе: ${formatQty(added)} ${p.unit} · спишется при проведении',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: left < 0
                    ? CupertinoColors.systemRed
                    : CupertinoColors.systemGreen,
              ),
            ),
        ],
      ),
      additionalInfo: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${formatQty(left < 0 ? 0 : left)} ${p.unit}',
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
          if (added > 0)
            Text(
              'было ${formatQty(p.stockMilli)}',
              style: const TextStyle(
                fontSize: 13,
                color: CupertinoColors.systemGrey,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (added > 0) ...[
            _roundButton(CupertinoIcons.minus, () => _minus(p), minus: true),
            const SizedBox(width: 8),
          ],
          if (piece)
            _roundButton(
              CupertinoIcons.add,
              left >= 1000 ? () => _plus(p, added) : null,
            )
          else
            const CupertinoListTileChevron(),
        ],
      ),
      onTap: () => _pick(p),
    );
  }
}
