import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/ui_kit.dart';
import '../product_ext.dart';
import '../providers.dart';
import 'inventory_widgets.dart';
import 'product_form_page.dart';
import 'stock_receipt_page.dart';

/// Строка «название слева, значение справа».
Widget _row(String title, String value, {Color? color}) => CupertinoListTile(
  title: Text(title),
  additionalInfo: Text(
    value,
    style: color == null
        ? null
        : TextStyle(fontWeight: FontWeight.w600, color: color),
  ),
);

class ProductDetailsPage extends ConsumerWidget {
  const ProductDetailsPage({super.key, required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(productProvider(productId)).value;
    final moves = ref.watch(productMovementsProvider(productId)).value ?? [];
    if (p == null) return const AppPage(title: 'Товар', children: [Loading()]);

    final margin = p.priceKopecks - p.costKopecks;

    return AppPage(
      title: 'Товар',
      children: [
        // ── Шапка ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            children: [
              ProductIcon(p.kind, size: 72),
              const SizedBox(height: 12),
              Text(
                p.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                p.kind.label,
                style: const TextStyle(color: CupertinoColors.systemGrey),
              ),
              const SizedBox(height: 16),
              Text(
                '${formatQty(p.stockMilli)} ${p.unit}',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: p.stockColor,
                ),
              ),
              const SizedBox(height: 6),
              StatusPill(p),
              StockBar(p),
            ],
          ),
        ),

        // ── Действия ──
        ActionRow([
          ActionItem(
            CupertinoIcons.arrow_down_circle,
            'Пополнить',
            () => openPage(context, StockReceiptPage(product: p), modal: true),
          ),
          ActionItem(
            CupertinoIcons.arrow_2_circlepath,
            'Пересчитать',
            () => _recount(context, ref, p),
          ),
          ActionItem(
            CupertinoIcons.pencil,
            'Изменить',
            () => openPage(context, ProductFormPage(product: p), modal: true),
          ),
          ActionItem(CupertinoIcons.delete, 'Удалить', () async {
            if (!await confirm(
              context,
              'Удалить товар?',
              'В старых заказах он останется как был.',
            )) {
              return;
            }
            await ref
                .read(inventoryRepositoryProvider)
                .softDeleteProduct(productId);
            if (context.mounted) Navigator.pop(context);
          }, color: CupertinoColors.systemRed),
        ]),
        const Hint(
          'Пополнить: привезли товар. Пересчитать: на полке оказалось другое количество.',
        ),

        // ── Цены ──
        LiquidSection(
          header: const Text('Цены'),
          children: [
            _row('Продаём по', '${formatMoney(p.priceKopecks)} за ${p.unit}'),
            _row(
              'Купили по',
              p.costKopecks == 0
                  ? 'Не указано'
                  : '${formatMoney(p.costKopecks)} за ${p.unit}',
            ),
            if (p.costKopecks > 0) ...[
              _row(
                'Заработок с 1 ${p.unit}',
                formatMoney(margin),
                color: margin >= 0
                    ? CupertinoColors.systemGreen
                    : CupertinoColors.systemRed,
              ),
              _row(
                'Остаток стоит',
                '${formatMoney(p.valueKopecks)} (по закупке)',
              ),
            ],
          ],
        ),
        LiquidSection(
          header: const Text('Предупреждение'),
          children: [
            _row(
              'Предупредить, если меньше',
              p.minStockMilli == 0
                  ? 'Не задано'
                  : '${formatQty(p.minStockMilli)} ${p.unit}',
            ),
          ],
        ),

        // ── История ──
        if (moves.isNotEmpty)
          LiquidSection(
            header: const Text('Что происходило с товаром'),
            children: [
              for (final m in moves)
                CupertinoListTile(
                  leading: Icon(m.kind.icon, color: m.kind.color, size: 28),
                  title: Text(m.kind.label),
                  subtitle: Text(
                    formatDateTime(m.createdAt) +
                        (m.note == null ? '' : ' · ${m.note}'),
                  ),
                  additionalInfo: Text(
                    '${m.deltaMilli > 0 ? '+' : '−'}${formatQty(m.deltaMilli.abs())} ${p.unit}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: m.deltaMilli > 0
                          ? CupertinoColors.systemGreen
                          : CupertinoColors.systemRed,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// «Пересчитать»: вводим, сколько реально осталось. Разницу программа
  /// посчитает сама и запишет в историю.
  Future<void> _recount(BuildContext context, WidgetRef ref, Product p) async {
    final ctrl = TextEditingController(text: formatQty(p.stockMilli));
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Сколько осталось на самом деле?'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: ctrl,
            autofocus: true,
            suffix: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(p.unit),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Исправить'),
          ),
        ],
      ),
    );
    final actual = parseQty(ctrl.text);
    ctrl.dispose();
    if (ok == true) {
      await ref
          .read(inventoryRepositoryProvider)
          .adjustTo(p.id, actual, note: 'Пересчёт');
    }
  }
}
