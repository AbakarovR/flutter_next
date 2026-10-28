import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/ui_kit.dart';
import '../product_ext.dart';
import '../providers.dart';
import 'inventory_widgets.dart';
import 'product_details_page.dart';
import 'product_filter.dart';
import 'product_form_page.dart';

enum _Status { all, low, out }

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  String _query = '';
  ProductFilter _filter = const ProductFilter(tab: TopTab.oil);
  _Status _status = _Status.all;

  bool _match(Product p) {
    final statusOk = switch (_status) {
      _Status.all => true,
      _Status.low => p.isLow,
      _Status.out => p.isOut,
    };
    return _filter.matches(p) &&
        statusOk &&
        p.name.toLowerCase().contains(_query.trim().toLowerCase());
  }

  /// Сначала то, что кончается, потом остальное, внутри групп по алфавиту.
  int _order(Product a, Product b) {
    final c = (a.needsAttention ? 0 : 1).compareTo(b.needsAttention ? 0 : 1);
    return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  void _add() =>
      openPage(context, ProductFormPage(initialFilter: _filter), modal: true);

  void _changeFilter(ProductFilter filter) => setState(() {
    _filter = filter;
    _query = '';
    _status = _Status.all;
  });

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(productsProvider);
    final all = async.value;
    if (all == null) {
      return LargeTitlePage(
        title: 'Склад',
        children: [
          async.hasError ? Text('Ошибка: ${async.error}') : const Loading(),
        ],
      );
    }

    final sectionItems = all.where(_filter.matches).toList();
    final items = sectionItems.where(_match).toList()..sort(_order);
    final totalValue = sectionItems.fold<int>(
      0,
      (sum, p) => sum + p.valueKopecks,
    );
    final cards = [
      (
        _Status.all,
        'Всего товаров',
        CupertinoColors.systemBlue,
        sectionItems.length,
      ),
      (
        _Status.low,
        'Заканчивается',
        CupertinoColors.systemOrange,
        sectionItems.where((p) => p.isLow).length,
      ),
      (
        _Status.out,
        'Нет в наличии',
        CupertinoColors.systemRed,
        sectionItems.where((p) => p.isOut).length,
      ),
    ];

    return LargeTitlePage(
      title: 'Склад',
      onAdd: _add,
      children: [
        if (all.isEmpty) ...[
          ProductFilterBar(
            key: ObjectKey(_filter),
            filter: _filter,
            showAll: false,
            onChanged: _changeFilter,
          ),
          EmptyState(
            icon: CupertinoIcons.cube_box,
            text: 'В этом разделе пока нет товаров',
            button: 'Добавить товар',
            onPressed: _add,
          ),
        ] else ...[
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                for (final (s, label, color, count) in cards)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SummaryCard(
                        value: '$count',
                        label: label,
                        color: color,
                        selected: _status == s,
                        onTap: () => setState(
                          () => _status = _status == s ? _Status.all : s,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (totalValue > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Hint('Товара на ${formatMoney(totalValue)} (по закупке)'),
            ),
          if (items.isEmpty)
            const EmptyState(
              icon: CupertinoIcons.search,
              text: 'Ничего не найдено',
            )
          else
            LiquidSection(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [for (final p in items) _tile(p)],
            ),
        ],
      ],
    );
  }

  Widget _tile(Product p) => CupertinoListTile(
    leadingSize: 44,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    leading: ProductIcon(p.kind),
    title: Text(p.name),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // У масла КПП показываем тип коробки.
        Text(
          p.kind == ProductKind.gearOil && p.gearbox != null
              ? '${p.gearbox!.label} · ${formatMoney(p.priceKopecks)} за ${p.unit}'
              : '${formatMoney(p.priceKopecks)} за ${p.unit}',
        ),
        StockBar(p),
      ],
    ),
    additionalInfo: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${formatQty(p.stockMilli)} ${p.unit}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        StatusPill(p),
      ],
    ),
    trailing: const CupertinoListTileChevron(),
    onTap: () => openPage(context, ProductDetailsPage(productId: p.id)),
  );
}
