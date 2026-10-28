import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/pill_tabs.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../backup/ui/backup_page.dart';
import '../../inventory/providers.dart';
import '../../orders/data/orders_repository.dart';
import '../../orders/order_ext.dart';
import '../../orders/ui/order_details_page.dart';
import '../providers.dart';
import '../report_logic.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  Period _period = Period.day;
  DateTime _anchor = DateTime.now();

  Range get _range => rangeFor(_period, _anchor);

  /// Вперёд можно, только если следующий период уже начался.
  bool get _canForward {
    final n = DateTime.now();
    return !_range.to.isAfter(DateTime(n.year, n.month, n.day));
  }

  void _move(int dir) =>
      setState(() => _anchor = shiftAnchor(_period, _anchor, dir));

  Future<void> _pickDate() async {
    final picked = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (_) => _CalendarSheet(initialDate: _anchor),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _anchor = picked;
      _period = Period.day;
    });
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    final orders = ref.watch(reportOrdersProvider(range)).value;
    final sales = ref.watch(reportSalesProvider(range)).value;
    final units = {
      for (final product in ref.watch(productsProvider).value ?? <Product>[])
        product.id: product.unit,
    };

    return LargeTitlePage(
      title: 'Отчёт',
      children: [
        _periodBar(range),
        PillTabs<Period>(
          value: _period,
          items: const {
            Period.day: 'День',
            Period.week: 'Неделя',
            Period.month: 'Месяц',
          },
          onChanged: (p) => setState(() => _period = p),
        ),
        if (orders == null || sales == null)
          const Loading()
        else
          ..._body(orders, sales, units),
      ],
    );
  }

  // ───────────── Период ─────────────

  Widget _periodBar(Range range) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Row(
      children: [
        NavIconButton(
          icon: CupertinoIcons.chevron_back,
          onTap: () => _move(-1),
        ),
        Expanded(
          child: Text(
            periodTitle(_period, range),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        NavIconButton(icon: CupertinoIcons.calendar, onTap: _pickDate),
        _canForward
            ? NavIconButton(
                icon: CupertinoIcons.chevron_forward,
                onTap: () => _move(1),
              )
            : const SizedBox(width: 42),
      ],
    ),
  );

  // ───────────── Содержимое ─────────────

  List<Widget> _body(
    List<OrderListItem> orders,
    List<Sale> sales,
    Map<String, String> units,
  ) => [
    ActionRow([
      ActionItem(
        CupertinoIcons.archivebox,
        'Бэкап',
        () => openPage(context, const BackupPage()),
      ),
    ]),
    if (orders.isEmpty)
      const Hint('За выбранный период заказ-нарядов пока нет.')
    else
      _ordersSection(orders),
    if (sales.isNotEmpty) _salesSection(sales, units),
  ];

  Widget _ordersSection(List<OrderListItem> orders) => LiquidSection(
    header: Text('Проведённые заказы: ${orders.length}'),
    children: [
      for (final i in orders)
        CupertinoListTile(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          title: Row(
            children: [
              PlateBadge(i.vehicle.plate, small: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(i.client.name, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${i.vehicle.brand} ${i.vehicle.model} · ${formatTime(i.order.completionDate)}',
            ),
          ),
          additionalInfo: Text(
            formatMoney(i.order.totalKopecks),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          trailing: const CupertinoListTileChevron(),
          onTap: () => openPage(context, OrderDetailsPage(orderId: i.order.id)),
        ),
    ],
  );

  int _saleRevenue(Sale sale) =>
      (sale.qtyMilli * sale.priceKopecks + 500) ~/ 1000;

  int _saleCost(Sale sale) => (sale.qtyMilli * sale.costKopecks + 500) ~/ 1000;

  Widget _salesSection(List<Sale> sales, Map<String, String> units) {
    final total = sales.fold<int>(0, (sum, sale) => sum + _saleRevenue(sale));
    return LiquidSection(
      header: Text('Отдельные продажи: ${sales.length}'),
      children: [
        CupertinoListTile(
          title: const Text('Сумма продаж за период'),
          additionalInfo: Text(
            formatMoney(total),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        for (final sale in sales)
          Dismissible(
            key: ValueKey(sale.id),
            direction: DismissDirection.endToStart,
            background: Container(
              color: CupertinoColors.systemRed,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(
                CupertinoIcons.delete,
                color: CupertinoColors.white,
              ),
            ),
            confirmDismiss: (_) => confirm(
              context,
              'Отменить продажу?',
              '${sale.title}. Деньги и товар будут возвращены в учёт и на склад.',
              action: 'Отменить',
            ),
            onDismissed: (_) =>
                ref.read(reportsRepositoryProvider).cancelSale(sale),
            child: CupertinoListTile(
              title: Text(sale.title),
              subtitle: Text(
                '${formatQty(sale.qtyMilli)} ${units[sale.productId] ?? ''} · '
                '${formatTime(sale.createdAt)}\n'
                '${sale.costKopecks > 0 ? 'Себестоимость ${formatMoney(_saleCost(sale))} · прибыль ${formatMoney(_saleRevenue(sale) - _saleCost(sale))}' : 'Себестоимость не указана · прибыль не рассчитана'}'
                '${sale.note == null ? '' : '\n${sale.note}'}',
              ),
              additionalInfo: Text(
                formatMoney(_saleRevenue(sale)),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }
}

/// Календарь в стиле Cupertino. Выбранная дата применяется после нажатия
/// «Выбрать», поэтому закрытие по свайпу или кнопке «Отмена» ничего не меняет.
class _CalendarSheet extends StatefulWidget {
  const _CalendarSheet({required this.initialDate});

  final DateTime initialDate;

  @override
  State<_CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends State<_CalendarSheet> {
  static const _months = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];
  static const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  static final _firstDate = DateTime(2000);

  late DateTime _selected = DateTime(
    widget.initialDate.year,
    widget.initialDate.month,
    widget.initialDate.day,
  );
  late DateTime _month = DateTime(_selected.year, _selected.month);

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get _canGoBack => _month.isAfter(DateTime(2000, 1));
  bool get _canGoForward =>
      _month.isBefore(DateTime(_today.year, _today.month));

  void _moveMonth(int amount) => setState(() {
    _month = DateTime(_month.year, _month.month + amount);
  });

  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;
    final firstWeekday = DateTime(_month.year, _month.month).weekday - 1;
    final dayCount = DateTime(_month.year, _month.month + 1, 0).day;
    final weekCount = (firstWeekday + dayCount + 6) ~/ 7;
    final background = CupertinoColors.systemGroupedBackground
        .resolveFrom(context)
        .withAlpha(185);

    return SafeArea(
      top: false,
      child: Glass(
        radius: 28,
        child: Container(
          color: background,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отмена'),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('Выбрать'),
                  ),
                ],
              ),
              Row(
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.all(8),
                    onPressed: _canGoBack ? () => _moveMonth(-1) : null,
                    child: const Icon(CupertinoIcons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${_months[_month.month - 1]} ${_month.year}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.all(8),
                    onPressed: _canGoForward ? () => _moveMonth(1) : null,
                    child: const Icon(CupertinoIcons.chevron_right),
                  ),
                ],
              ),
              Row(
                children: [
                  for (var weekday = 0; weekday < 7; weekday++)
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            _weekdays[weekday],
                            style: TextStyle(
                              color: weekday >= 5
                                  ? CupertinoColors.systemRed
                                  : CupertinoColors.systemGrey.resolveFrom(
                                      context,
                                    ),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              for (var week = 0; week < weekCount; week++)
                Row(
                  children: [
                    for (var weekday = 0; weekday < 7; weekday++)
                      Expanded(
                        child: _dayCell(
                          week * 7 + weekday - firstWeekday + 1,
                          dayCount,
                          primary,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayCell(int day, int dayCount, Color primary) {
    if (day < 1 || day > dayCount) return const SizedBox(height: 44);

    final date = DateTime(_month.year, _month.month, day);
    final enabled = !date.isBefore(_firstDate) && !date.isAfter(_today);
    final selected = _sameDay(date, _selected);
    final today = _sameDay(date, _today);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => setState(() => _selected = date) : null,
      child: SizedBox(
        height: 44,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? primary : CupertinoColors.transparent,
              shape: BoxShape.circle,
              border: today && !selected
                  ? Border.all(color: primary, width: 1.5)
                  : null,
            ),
            child: Text(
              '$day',
              style: TextStyle(
                color: !enabled
                    ? CupertinoColors.tertiaryLabel.resolveFrom(context)
                    : selected
                    ? CupertinoColors.white
                    : CupertinoColors.label.resolveFrom(context),
                fontWeight: selected || today ? FontWeight.w700 : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
