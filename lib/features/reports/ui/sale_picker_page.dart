import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../inventory/product_ext.dart';
import '../../inventory/providers.dart';
import '../../inventory/ui/inventory_widgets.dart';
import '../../inventory/ui/product_filter.dart';
import 'sale_form_page.dart';

/// Выбор товара для продажи без заказа. Окно остаётся открытым:
/// можно продать несколько товаров подряд и нажать «Закрыть».
class SalePickerPage extends ConsumerStatefulWidget {
  const SalePickerPage({super.key, this.isTab = false});
  final bool isTab;

  @override
  ConsumerState<SalePickerPage> createState() => _SalePickerPageState();
}

class _SalePickerPageState extends ConsumerState<SalePickerPage> {
  String _query = '';
  ProductFilter _filter = const ProductFilter(tab: TopTab.oil);
  int _sold = 0;

  void _changeFilter(ProductFilter filter) => setState(() {
    _filter = filter;
    _query = '';
  });

  Future<void> _open(Product p) async {
    final ok = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => SaleFormPage(product: p),
      ),
    );
    if (ok == true && mounted) setState(() => _sold++);
  }

  @override
  Widget build(BuildContext context) {
    final close = widget.isTab
        ? null
        : NavTextButton('Закрыть', onTap: () => Navigator.pop(context));
    final all = ref.watch(productsProvider).value;
    if (all == null) {
      if (widget.isTab) {
        return const LargeTitlePage(title: 'Продажи', children: [Loading()]);
      }
      return AppPage(
        title: 'Продажа товара',
        leading: close,
        children: const [Loading()],
      );
    }

    final q = _query.trim().toLowerCase();
    final items = all
        .where((p) => _filter.matches(p) && p.name.toLowerCase().contains(q))
        .toList();

    final children = <Widget>[
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
      Hint(
        _sold > 0
            ? widget.isTab
                  ? 'В этой сессии продано: $_sold. Выберите следующий товар.'
                  : 'Продано в этом окне: $_sold. Выберите ещё товар или нажмите «Закрыть».'
            : 'Выберите товар, который продаёте без заказа.',
      ),
      items.isEmpty
          ? EmptyState(
              icon: CupertinoIcons.cube_box,
              text: all.isEmpty
                  ? 'На складе нет товаров.\nДобавьте их на вкладке «Склад».'
                  : 'Ничего не найдено',
            )
          : LiquidSection(
              children: [
                for (final p in items)
                  CupertinoListTile(
                    leadingSize: 40,
                    leading: ProductIcon(p.kind, size: 40),
                    title: Text(p.name),
                    subtitle: Text(
                      '${formatMoney(p.priceKopecks)} за ${p.unit}',
                    ),
                    additionalInfo: Text(
                      p.isOut
                          ? 'Нет в наличии'
                          : '${formatQty(p.stockMilli)} ${p.unit}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: p.statusColor,
                      ),
                    ),
                    trailing: p.isOut ? null : const CupertinoListTileChevron(),
                    onTap: p.isOut ? null : () => _open(p),
                  ),
              ],
            ),
    ];

    if (widget.isTab) {
      return LargeTitlePage(title: 'Продажи', children: children);
    }
    return AppPage(title: 'Продажа товара', leading: close, children: children);
  }
}
