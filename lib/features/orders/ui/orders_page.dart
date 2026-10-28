import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/plate.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../inventory/ui/inventory_widgets.dart' show SummaryCard;
import '../data/orders_repository.dart';
import '../order_ext.dart';
import '../providers.dart';
import 'new_order_page.dart';
import 'order_details_page.dart';
import 'order_widgets.dart';

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  String _query = '';
  int _tab = 0; // 0 все, 1 в работе, 2 проведены (порядок как у OrderStatus)

  bool _isDraft(OrderListItem i) => i.order.status == OrderStatus.draft;

  bool _match(OrderListItem i) {
    final tabOk = _tab == 0 || i.order.status == OrderStatus.values[_tab - 1];
    final q = _query.trim().toLowerCase();
    return tabOk &&
        (q.isEmpty ||
            i.client.name.toLowerCase().contains(q) ||
            i.vehicle.plate.contains(normalizePlate(q)));
  }

  /// Нажали на карточку: включаем фильтр, нажали ещё раз: выключаем.
  void _toggleTab(int t) => setState(() => _tab = _tab == t ? 0 : t);

  void _add() => openPage(context, const NewOrderPage(), modal: true);

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(ordersListProvider).value;
    if (all == null) {
      return const LargeTitlePage(title: 'Заказы', children: [Loading()]);
    }

    // Сводка считается по всем заказам, поэтому не прыгает при поиске.
    final now = DateTime.now();
    final draftCount = all.where(_isDraft).length;
    final today = all
        .where((i) => !_isDraft(i) && isSameDay(i.order.completionDate, now))
        .toList();
    final revenue = today.fold<int>(0, (s, i) => s + i.order.totalKopecks);

    // Раскладываем: сверху «В работе», ниже проведённые по дням.
    final items = all.where(_match).toList();
    final active = items.where(_isDraft).toList();
    final done = items.where((i) => !_isDraft(i)).toList()
      ..sort(
        (a, b) => b.order.completionDate.compareTo(a.order.completionDate),
      );
    final byDay = <String, List<OrderListItem>>{};
    for (final i in done) {
      byDay.putIfAbsent(dayTitle(i.order.completionDate), () => []).add(i);
    }

    return LargeTitlePage(
      title: 'Заказы',
      onAdd: _add,
      children: [
        if (all.isEmpty)
          EmptyState(
            icon: CupertinoIcons.doc_text,
            text: 'Заказов пока нет',
            button: 'Создать заказ',
            onPressed: _add,
          )
        else ...[
          SearchField(
            'Имя клиента или госномер',
            (v) => setState(() => _query = v),
          ),
          Segments<int>(
            value: _tab,
            items: const {0: 'Все', 1: 'В работе', 2: 'Проведены'},
            onChanged: (v) => setState(() => _tab = v),
          ),
          // ── Две карточки сводки ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: SummaryCard(
                      value: '$draftCount',
                      label: 'В работе',
                      color: CupertinoColors.systemOrange,
                      selected: _tab == 1,
                      onTap: () => _toggleTab(1),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: SummaryCard(
                      value: formatRub(revenue),
                      label: 'Сегодня, заказов: ${today.length}',
                      color: CupertinoColors.systemGreen,
                      selected: _tab == 2,
                      onTap: () => _toggleTab(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            const EmptyState(
              icon: CupertinoIcons.search,
              text: 'Ничего не найдено',
            ),
          if (active.isNotEmpty)
            LiquidSection(
              header: const Text('В работе'),
              children: [for (final i in active) _tile(i)],
            ),
          for (final e in byDay.entries)
            LiquidSection(
              header: Text(
                '${e.key} · ${formatRub(e.value.fold<int>(0, (s, i) => s + i.order.totalKopecks))}',
              ),
              children: [for (final i in e.value) _tile(i)],
            ),
          if (active.isNotEmpty)
            const Hint('Свайп влево по заказу «В работе»: удалить.'),
        ],
      ],
    );
  }

  /// Одна строка заказа. Заказы «В работе» можно удалить свайпом.
  Widget _tile(OrderListItem i) {
    final o = i.order;
    final v = i.vehicle;
    final draft = _isDraft(i);
    final when = draft
        ? '${dayTitle(o.createdAt)}, ${formatTime(o.createdAt)}'
        : formatTime(o.completionDate);
    final hasSum = o.totalKopecks > 0;

    final tile = CupertinoListTile(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Row(
        children: [
          PlateBadge(v.plate, small: true),
          const SizedBox(width: 8),
          Expanded(child: Text(i.client.name, overflow: TextOverflow.ellipsis)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('${v.brand} ${v.model} · $when'),
      ),
      additionalInfo: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            hasSum ? formatMoney(o.totalKopecks) : 'Пусто',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: hasSum
                  ? CupertinoColors.label.resolveFrom(context)
                  : CupertinoColors.systemGrey,
            ),
          ),
          if (draft) ...[const SizedBox(height: 4), OrderStatusPill(o.status)],
        ],
      ),
      trailing: const CupertinoListTileChevron(),
      onTap: () => openPage(context, OrderDetailsPage(orderId: o.id)),
    );

    if (!draft) return tile;

    return Dismissible(
      key: ValueKey(o.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: CupertinoColors.systemRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
      ),
      confirmDismiss: (_) =>
          confirm(context, 'Удалить заказ?', '${v.plate} · ${i.client.name}'),
      onDismissed: (_) =>
          ref.read(ordersRepositoryProvider).softDeleteOrder(o.id),
      child: tile,
    );
  }
}
