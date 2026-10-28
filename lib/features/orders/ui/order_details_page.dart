import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/providers.dart';
import '../data/orders_repository.dart';
import '../order_ext.dart';
import '../providers.dart';
import 'engine_page.dart';
import 'gearbox_page.dart';
import 'order_item_form_page.dart';
import 'order_widgets.dart';
import 'product_picker_page.dart';
import 'works_form_page.dart';

/// Строка «название слева, сумма справа» для блока итогов.
Widget _sumRow(String title, int kopecks) => CupertinoListTile(
  title: Text(title),
  additionalInfo: Text(formatMoney(kopecks)),
);

class OrderDetailsPage extends ConsumerWidget {
  const OrderDetailsPage({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(orderProvider(orderId)).value;
    final items = ref.watch(orderItemsProvider(orderId)).value ?? [];
    // Товары склада по id: нужны, чтобы показать иконку и нехватку.
    final products = {
      for (final p in ref.watch(productsProvider).value ?? <Product>[]) p.id: p,
    };
    if (data == null) {
      return const AppPage(title: 'Заказ', children: [Loading()]);
    }

    final o = data.order;
    final v = data.vehicle;
    final draft = o.status == OrderStatus.draft;
    final repo = ref.read(ordersRepositoryProvider);

    final goods = items.where((i) => i.kind == ItemKind.product).toList();
    final works = items.where((i) => i.kind == ItemKind.work).toList();
    int sum(List<OrderItem> l) => l.fold<int>(0, (s, i) => s + i.sumKopecks);
    final total = sum(items);

    void openEngine() =>
        openPage(context, EnginePage(orderId: orderId), modal: true);
    void openGearbox() =>
        openPage(context, GearboxPage(orderId: orderId), modal: true);

    return AppPage(
      title: 'Заказ-наряд',
      children: [
        // ── Шапка ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            children: [
              PlateBadge(v.plate),
              const SizedBox(height: 10),
              Text(
                data.client.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${v.brand} ${v.model}',
                style: const TextStyle(color: CupertinoColors.systemGrey),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OrderStatusPill(o.status),
                  const SizedBox(width: 8),
                  Text(
                    draft
                        ? 'создан ${formatDateTime(o.createdAt)}'
                        : 'проведён ${formatDateTime(o.completionDate)}',
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── Действия ──
        if (draft)
          ActionRow([
            ActionItem(CupertinoIcons.gear, 'Двигатель', openEngine),
            ActionItem(
              CupertinoIcons.arrow_swap,
              'Коробка передач',
              openGearbox,
            ),
            ActionItem(
              CupertinoIcons.drop,
              'Товар',
              () => openPage(
                context,
                ProductPickerPage(orderId: orderId),
                modal: true,
              ),
            ),
            ActionItem(
              CupertinoIcons.wrench,
              'Работа',
              () => openPage(
                context,
                WorksFormPage(orderId: orderId),
                modal: true,
              ),
            ),
            ActionItem(CupertinoIcons.delete, 'Удалить', () async {
              if (!await confirm(
                context,
                'Удалить заказ?',
                'Заказ в работе будет удалён.',
              )) {
                return;
              }
              await repo.softDeleteOrder(orderId);
              if (context.mounted) Navigator.pop(context);
            }, color: CupertinoColors.systemRed),
          ])
        else
          ActionRow([
            ActionItem(
              CupertinoIcons.doc_on_doc,
              'Чек',
              () => _copyReceipt(context, data, items),
            ),
            ActionItem(
              CupertinoIcons.arrow_uturn_left,
              'Вернуть в работу',
              () async {
                if (!await confirm(
                  context,
                  'Вернуть заказ в работу?',
                  'Списанные товары вернутся на склад.',
                  action: 'Вернуть',
                  destructive: false,
                )) {
                  return;
                }
                await repo.reopen(orderId);
              },
            ),
          ]),

        // ── Пробег ──
        LiquidSection(
          footer: const Text(
            'Пробег нужен для напоминания о следующей замене.',
          ),
          children: [
            CupertinoListTile(
              title: const Text('Пробег'),
              additionalInfo: Text('${formatKm(o.mileage)} км'),
              trailing: draft ? const CupertinoListTileChevron() : null,
              onTap: draft ? () => _editMileage(context, repo, o) : null,
            ),
          ],
        ),

        // ── Состав: товары и работы отдельно ──
        if (items.isEmpty) ...[
          if (draft) const Hint('Добавьте товар или работу кнопками выше.'),
        ] else ...[
          if (goods.isNotEmpty)
            LiquidSection(
              header: const Text('Товары'),
              children: [
                for (final i in goods)
                  _itemTile(context, repo, i, draft, products[i.productId]),
              ],
            ),
          if (works.isNotEmpty)
            LiquidSection(
              header: const Text('Работы'),
              children: [
                for (final i in works) _itemTile(context, repo, i, draft, null),
              ],
            ),
          if (draft)
            const Hint(
              'Нажмите на строку, чтобы изменить. Свайп влево: убрать.',
            ),
        ],

        // ── Итоги ──
        LiquidSection(
          children: [
            if (goods.isNotEmpty && works.isNotEmpty) ...[
              _sumRow('Товары', sum(goods)),
              _sumRow('Работы', sum(works)),
            ],
            CupertinoListTile(
              title: const Text(
                'Итого',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              additionalInfo: Text(
                formatMoney(total),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
            ),
          ],
        ),

        // ── Провести ──
        if (draft) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: CupertinoButton.filled(
              onPressed: items.isEmpty ? null : () => _complete(context, repo),
              child: Text(
                items.isEmpty
                    ? 'Провести заказ'
                    : 'Провести · ${formatMoney(total)}',
              ),
            ),
          ),
          const Hint('При проведении товары спишутся со склада.'),
        ],
      ],
    );
  }

  /// Строка заказа: иконка, название, количество × цена, сумма.
  /// [p] это товар на складе (для работ null).
  Widget _itemTile(
    BuildContext context,
    OrdersRepository repo,
    OrderItem i,
    bool draft,
    Product? p,
  ) {
    final tile = CupertinoListTile(
      leadingSize: 36,
      leading: ItemIcon(
        kind: i.kind == ItemKind.work ? null : (p?.kind ?? ProductKind.other),
      ),
      title: Text(i.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${formatQty(i.qtyMilli)} × ${formatMoney(i.priceKopecks)}'),
          if (draft && p != null && p.stockMilli < i.qtyMilli)
            Text(
              'Не хватает: на складе ${formatQty(p.stockMilli)} ${p.unit}',
              style: const TextStyle(
                fontSize: 14,
                color: CupertinoColors.systemOrange,
              ),
            ),
        ],
      ),
      additionalInfo: Text(
        formatMoney(i.sumKopecks),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: CupertinoColors.label.resolveFrom(context),
        ),
      ),
      onTap: draft
          ? () => openPage(
              context,
              OrderItemFormPage(orderId: orderId, item: i),
              modal: true,
            )
          : null,
    );
    if (!draft) return tile;

    return Dismissible(
      key: ValueKey(i.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: CupertinoColors.systemRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
      ),
      onDismissed: (_) => repo.removeItem(i),
      child: tile,
    );
  }

  /// Проверяем склад, спрашиваем подтверждение и проводим.
  Future<void> _complete(BuildContext context, OrdersRepository repo) async {
    final short = await repo.shortages(orderId);
    if (!context.mounted) return;
    if (short.isNotEmpty) {
      await _showStockShortage(context, short.join('\n'));
      return;
    }
    final ok = await confirm(
      context,
      'Провести заказ?',
      'Товары спишутся со склада.',
      action: 'Провести',
      destructive: false,
    );
    if (!ok || !context.mounted) return;
    try {
      await repo.complete(orderId);
    } on InsufficientStockException catch (error) {
      if (context.mounted) {
        await _showStockShortage(context, error.shortages.join('\n'));
      }
    }
  }

  Future<void> _showStockShortage(BuildContext context, String details) async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Недостаточно товара'),
        content: Text('$details\n\nПополните склад или измените заказ.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  /// Копирует текст заказа в буфер обмена: можно вставить клиенту в мессенджер.
  Future<void> _copyReceipt(
    BuildContext context,
    OrderListItem d,
    List<OrderItem> items,
  ) async {
    final o = d.order;
    final v = d.vehicle;
    final b = StringBuffer()
      ..writeln('Заказ-наряд от ${formatDateTime(o.createdAt)}')
      ..writeln('${v.brand} ${v.model}, ${v.plate}')
      ..writeln('Пробег: ${formatKm(o.mileage)} км')
      ..writeln();
    for (final i in items) {
      b.writeln(
        '${i.title}: ${formatQty(i.qtyMilli)} × '
        '${formatMoney(i.priceKopecks)} = ${formatMoney(i.sumKopecks)}',
      );
    }
    final total = items.fold<int>(0, (s, i) => s + i.sumKopecks);
    b
      ..writeln()
      ..write('Итого: ${formatMoney(total)}');

    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (!context.mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Чек скопирован'),
        content: const Text('Вставьте его в мессенджер или СМС клиенту.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  Future<void> _editMileage(
    BuildContext context,
    OrdersRepository repo,
    Order o,
  ) async {
    final ctrl = TextEditingController(text: o.mileage.toString());
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Пробег, км'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
    final km = int.tryParse(ctrl.text.trim());
    ctrl.dispose();
    if (ok == true && km != null) await repo.setMileage(o.id, km);
  }
}
