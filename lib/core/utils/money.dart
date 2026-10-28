import 'package:intl/intl.dart';

final _fmt = NumberFormat.currency(locale: 'ru', symbol: '₽', decimalDigits: 2);
final _plain = NumberFormat.decimalPattern('ru');

/// 150050 → «1 500,50 ₽». Только для показа, считаем всегда в копейках.
String formatMoney(int kopecks) => _fmt.format(kopecks / 100);

/// 1250000 → «12 500 ₽». Короткая запись для карточек.
String formatRub(int kopecks) => '${_plain.format((kopecks / 100).round())} ₽';

/// «1500,50» (ввод) → 150050.
int parseMoney(String input) {
  final v = double.tryParse(input.replaceAll(',', '.').replaceAll(' ', ''));
  return v == null ? 0 : (v * 100).round();
}

/// 4500 → «4,5».
String formatQty(int milli) {
  final v = milli / 1000;
  return v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toString().replaceAll('.', ',');
}

/// «4,5» → 4500.
int parseQty(String input) {
  final v = double.tryParse(input.replaceAll(',', '.').replaceAll(' ', ''));
  return v == null ? 0 : (v * 1000).round();
}

/// 150000 → «1500», 150050 → «1500,50». Для подстановки в поле.
String kopecksToInput(int kopecks) {
  if (kopecks % 100 == 0) return '${kopecks ~/ 100}';
  return (kopecks / 100).toStringAsFixed(2).replaceAll('.', ',');
}

/// Пробег с пробелами: 123456 → «123 456».
String formatKm(int km) => _plain.format(km);
