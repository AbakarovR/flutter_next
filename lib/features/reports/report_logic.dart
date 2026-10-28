import '../../core/database/app_database.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import 'data/reports_repository.dart';

enum Period { day, week, month }

/// Период [from, to): to не входит.
typedef Range = ({DateTime from, DateTime to});

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

Range rangeFor(Period p, DateTime a) {
  final d = _day(a);
  switch (p) {
    case Period.day:
      return (from: d, to: DateTime(d.year, d.month, d.day + 1));
    case Period.week:
      final s = DateTime(d.year, d.month, d.day - (d.weekday - 1));
      return (from: s, to: DateTime(s.year, s.month, s.day + 7));
    case Period.month:
      return (
        from: DateTime(d.year, d.month),
        to: DateTime(d.year, d.month + 1),
      );
  }
}

/// Сдвиг якоря на один период вперёд (dir = 1) или назад (dir = -1).
DateTime shiftAnchor(Period p, DateTime a, int dir) => switch (p) {
  Period.day => DateTime(a.year, a.month, a.day + dir),
  Period.week => DateTime(a.year, a.month, a.day + 7 * dir),
  Period.month => DateTime(a.year, a.month + dir, 1),
};

const _gen = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];
const _nom = [
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

/// Название периода: «Сегодня», «19 – 25 октября», «Октябрь 2026».
String periodTitle(Period p, Range r) {
  switch (p) {
    case Period.day:
      return dayTitle(r.from);
    case Period.week:
      final last = DateTime(r.to.year, r.to.month, r.to.day - 1);
      return r.from.month == last.month
          ? '${r.from.day} – ${last.day} ${_gen[last.month - 1]}'
          : '${r.from.day} ${_gen[r.from.month - 1]} – ${last.day} ${_gen[last.month - 1]}';
    case Period.month:
      return '${_nom[r.from.month - 1]} ${r.from.year}';
  }
}

/// Статистика по одному товару за период.
class ProductStat {
  ProductStat(this.id, this.name, this.unit, this.kind);
  final String id;
  final String name;
  final String unit;
  final ProductKind kind;
  int qty = 0;
  int revenue = 0;
  int cost = 0;

  int get profit => revenue - cost;

  /// Наценка в процентах от закупки (null, если закупка не указана).
  int? get markup => cost > 0 ? (profit * 100 / cost).round() : null;
}

class Report {
  Report({
    required this.ordersCount,
    required this.salesCount,
    required this.works,
    required this.goodsInOrders,
    required this.retail,
    required this.cost,
    required this.expenses,
    required this.products,
  });

  final int ordersCount, salesCount;
  final int works, goodsInOrders, retail, cost, expenses;
  final List<ProductStat> products;

  int get revenue => works + goodsInOrders + retail;
  int get grossProfit => revenue - cost;
  int get netProfit => grossProfit - expenses;
  int get avgCheck =>
      ordersCount == 0 ? 0 : (works + goodsInOrders) ~/ ordersCount;
}

Report buildReport({
  required int ordersCount,
  required List<OrderLine> lines,
  required List<Sale> sales,
  required List<Expense> expenses,
  required Map<String, Product> products,
}) {
  var works = 0, goods = 0, retail = 0, cost = 0;
  final stats = <String, ProductStat>{};

  ProductStat stat(String id, String title) {
    final p = products[id];
    return stats.putIfAbsent(
      id,
      () =>
          ProductStat(id, title, p?.unit ?? 'шт', p?.kind ?? ProductKind.other),
    );
  }

  for (final l in lines) {
    if (l.item.kind == ItemKind.work) {
      works += l.revenue;
      continue;
    }
    goods += l.revenue;
    cost += l.cost;
    final id = l.item.productId;
    if (id != null) {
      stat(id, l.item.title)
        ..qty += l.item.qtyMilli
        ..revenue += l.revenue
        ..cost += l.cost;
    }
  }

  for (final s in sales) {
    final rev = (s.qtyMilli * s.priceKopecks + 500) ~/ 1000;
    final c = (s.qtyMilli * s.costKopecks + 500) ~/ 1000;
    retail += rev;
    cost += c;
    stat(s.productId, s.title)
      ..qty += s.qtyMilli
      ..revenue += rev
      ..cost += c;
  }

  final list = stats.values.toList()
    ..sort((a, b) => b.profit.compareTo(a.profit));

  return Report(
    ordersCount: ordersCount,
    salesCount: sales.length,
    works: works,
    goodsInOrders: goods,
    retail: retail,
    cost: cost,
    expenses: expenses.fold<int>(0, (s, e) => s + e.amountKopecks),
    products: list,
  );
}

/// Текст отчёта для копирования.
String reportText(Report r, String title) {
  final b = StringBuffer()
    ..writeln('Отчёт: $title')
    ..writeln(
      'Заказов проведено: ${r.ordersCount}, средний чек ${formatMoney(r.avgCheck)}',
    )
    ..writeln('Розничных продаж вне заказ-наряда: ${r.salesCount}')
    ..writeln()
    ..writeln('Выручка: ${formatMoney(r.revenue)}')
    ..writeln('  работы: ${formatMoney(r.works)}')
    ..writeln('  товары в заказах: ${formatMoney(r.goodsInOrders)}')
    ..writeln('  розничные продажи: ${formatMoney(r.retail)}')
    ..writeln('Себестоимость товаров: ${formatMoney(r.cost)}')
    ..writeln('Валовая прибыль: ${formatMoney(r.grossProfit)}')
    ..writeln('Расходы: ${formatMoney(r.expenses)}')
    ..writeln('Чистая прибыль: ${formatMoney(r.netProfit)}');
  if (r.products.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Товары:');
    for (final p in r.products) {
      b.writeln(
        '${p.name}: ${formatQty(p.qty)} ${p.unit}, '
        'выручка ${formatMoney(p.revenue)}, прибыль ${formatMoney(p.profit)}',
      );
    }
  }
  return b.toString().trimRight();
}
