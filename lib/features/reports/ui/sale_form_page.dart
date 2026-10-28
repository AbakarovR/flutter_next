import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/form_row.dart';
import '../../../core/widgets/round_button.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../inventory/providers.dart';
import '../../orders/ui/order_widgets.dart';
import '../providers.dart';

/// Продажа выбранного товара без заказа. Больше остатка продать нельзя.
class SaleFormPage extends ConsumerStatefulWidget {
  const SaleFormPage({super.key, required this.product});
  final Product product;

  @override
  ConsumerState<SaleFormPage> createState() => _SaleFormPageState();
}

class _SaleFormPageState extends ConsumerState<SaleFormPage> {
  static const _decimal = TextInputType.numberWithOptions(decimal: true);
  static const _litres = ['1', '2', '4', '5'];

  Product get _p => widget.product;

  /// Свежий остаток из базы.
  int get _stock =>
      ref.read(productProvider(_p.id)).value?.stockMilli ?? _p.stockMilli;

  /// Шаг кнопок: 0,5 для литров, 1 для штук.
  int get _step => _p.unit == 'л' ? 500 : 1000;

  late final _qty = TextEditingController(text: '1');
  late final _price = TextEditingController(
    text: kopecksToInput(_p.priceKopecks),
  );
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final c in [_qty, _price, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(int milli) => _qty.text = milli <= 0 ? '' : formatQty(milli);

  Future<void> _save() async {
    final qty = parseQty(_qty.text);
    if (qty <= 0) {
      setState(() => _error = 'Количество должно быть больше нуля');
      return;
    }
    if (qty > _stock) {
      setState(
        () => _error = 'На складе только ${formatQty(_stock)} ${_p.unit}',
      );
      return;
    }
    final ok = await ref
        .read(reportsRepositoryProvider)
        .sell(
          _p,
          qtyMilli: qty,
          priceKopecks: parseMoney(_price.text),
          note: _note.text,
        );
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = 'Остаток изменился. Проверьте количество.');
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: 'Продажа',
      onSave: _save,
      error: _error,
      children: [
        LiquidSection(
          header: Text(_p.name),
          footer: ListenableBuilder(
            listenable: _qty,
            builder: (_, _) {
              final left = _stock - parseQty(_qty.text);
              return Text(
                left < 0
                    ? 'Больше, чем на складе: ${formatQty(_stock)} ${_p.unit}'
                    : 'На складе ${formatQty(_stock)} ${_p.unit}. Останется: ${formatQty(left)} ${_p.unit}.',
                style: left < 0
                    ? const TextStyle(color: CupertinoColors.systemRed)
                    : null,
              );
            },
          ),
          children: [
            Column(
              children: [
                ListenableBuilder(
                  listenable: _qty,
                  builder: (_, _) {
                    final q = parseQty(_qty.text);
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _p.unit == 'л' ? 'Литров' : 'Количество, шт',
                            ),
                          ),
                          RoundButton(
                            CupertinoIcons.minus,
                            q > 0
                                ? () => _set(q - _step < 0 ? 0 : q - _step)
                                : null,
                            minus: true,
                          ),
                          SizedBox(
                            width: 84,
                            child: CupertinoTextField(
                              controller: _qty,
                              placeholder: '0',
                              textAlign: TextAlign.center,
                              decoration: null,
                              keyboardType: _decimal,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          RoundButton(
                            CupertinoIcons.add,
                            q + _step <= _stock ? () => _set(q + _step) : null,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                if (_p.unit == 'л')
                  ListenableBuilder(
                    listenable: _qty,
                    builder: (_, _) {
                      final shown = _litres
                          .where((s) => parseQty(s) <= _stock)
                          .toList();
                      return shown.isEmpty
                          ? const SizedBox.shrink()
                          : QuickChips(
                              shown,
                              (s) => _qty.text = s,
                              selected: {_qty.text},
                            );
                    },
                  ),
              ],
            ),
            FormRow(
              label: 'Цена, ₽',
              controller: _price,
              placeholder: 'За ${_p.unit}',
              keyboardType: _decimal,
            ),
            FormRow(
              label: 'Заметка',
              controller: _note,
              placeholder: 'Необязательно',
            ),
          ],
        ),
        ListenableBuilder(
          listenable: Listenable.merge([_qty, _price]),
          builder: (_, _) {
            final q = parseQty(_qty.text);
            final sum = (q * parseMoney(_price.text) + 500) ~/ 1000;
            final cost = (q * _p.costKopecks + 500) ~/ 1000;
            final profit = sum - cost;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      'Сумма: ${formatMoney(sum)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _p.costKopecks > 0
                          ? 'Себестоимость: ${formatMoney(cost)}'
                          : 'Себестоимость не указана',
                      style: const TextStyle(
                        fontSize: 14,
                        color: CupertinoColors.systemGrey,
                      ),
                    ),
                    if (_p.costKopecks > 0)
                      Text(
                        'Прибыль: ${formatMoney(profit)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: profit >= 0
                              ? CupertinoColors.systemGreen
                              : CupertinoColors.systemRed,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
