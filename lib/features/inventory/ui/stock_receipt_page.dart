import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/form_row.dart';
import '../../../core/widgets/ui_kit.dart';
import '../providers.dart';

/// Экран «Пополнить»: привезли или купили товар.
class StockReceiptPage extends ConsumerStatefulWidget {
  const StockReceiptPage({super.key, required this.product});
  final Product product;

  @override
  ConsumerState<StockReceiptPage> createState() => _StockReceiptPageState();
}

class _StockReceiptPageState extends ConsumerState<StockReceiptPage> {
  final _qty = TextEditingController();
  late final _cost = TextEditingController(
    text: widget.product.costKopecks > 0
        ? kopecksToInput(widget.product.costKopecks)
        : null,
  );
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final c in [_qty, _cost, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final qty = parseQty(_qty.text);
    if (qty <= 0) {
      setState(() => _error = 'Укажите, сколько привезли (больше нуля)');
      return;
    }
    final cost = parseMoney(_cost.text);
    await ref
        .read(inventoryRepositoryProvider)
        .receive(
          widget.product.id,
          qtyMilli: qty,
          costKopecks: cost > 0 ? cost : null,
          note: _note.text,
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const decimal = TextInputType.numberWithOptions(decimal: true);
    final p = widget.product;

    return FormPage(
      title: 'Пополнить',
      onSave: _save,
      error: _error,
      children: [
        LiquidSection(
          header: Text(p.name),
          // Подпись пересчитывается при каждой цифре.
          footer: ListenableBuilder(
            listenable: _qty,
            builder: (_, _) => Text(
              'Сейчас: ${formatQty(p.stockMilli)} ${p.unit}. '
              'Станет: ${formatQty(p.stockMilli + parseQty(_qty.text))} ${p.unit}.',
            ),
          ),
          children: [
            FormRow(
              label: 'Привезли',
              controller: _qty,
              placeholder: 'Сколько ${p.unit}',
              keyboardType: decimal,
            ),
          ],
        ),
        // Быстрые кнопки: каждое нажатие прибавляет число к полю.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final n in [1, 5, 10, 20])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: CupertinoButton.tinted(
                      padding: EdgeInsets.zero,
                      onPressed: () =>
                          _qty.text = formatQty(parseQty(_qty.text) + n * 1000),
                      child: Text('+$n'),
                    ),
                  ),
                ),
            ],
          ),
        ),
        LiquidSection(
          header: const Text('Дополнительно'),
          footer: Text('Цена закупки за 1 ${p.unit}, в рублях.'),
          children: [
            FormRow(
              label: 'Купили по',
              controller: _cost,
              placeholder: 'Необязательно',
              keyboardType: decimal,
            ),
            FormRow(
              label: 'Заметка',
              controller: _note,
              placeholder: 'Поставщик, накладная',
            ),
          ],
        ),
      ],
    );
  }
}
