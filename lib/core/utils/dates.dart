import 'package:intl/intl.dart';

final _dateTime = DateFormat('dd.MM.yyyy HH:mm');
final _time = DateFormat('HH:mm');

const _months = [
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

/// 12.10.2026 14:30
String formatDateTime(DateTime d) => _dateTime.format(d);

/// 14:30
String formatTime(DateTime d) => _time.format(d);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// «Сегодня», «Вчера» или «5 октября» (с годом, если он не текущий).
String dayTitle(DateTime d) {
  final now = DateTime.now();
  if (isSameDay(d, now)) return 'Сегодня';
  if (isSameDay(d, now.subtract(const Duration(days: 1)))) return 'Вчера';
  final year = d.year == now.year ? '' : ' ${d.year}';
  return '${d.day} ${_months[d.month - 1]}$year';
}
