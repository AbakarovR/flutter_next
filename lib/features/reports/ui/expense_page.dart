import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../core/widgets/form_row.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../orders/ui/order_widgets.dart';
import '../providers.dart';

/// Запись расхода: аренда, зарплата, коммунальные и т.д.
class ExpensePage extends ConsumerStatefulWidget {
  const ExpensePage({super.key});

  @override
  ConsumerState<ExpensePage> createState() => _ExpensePageState();
}

class _ExpensePageState extends ConsumerState<ExpensePage> {
  static const _names = [
    'Аренда',
    'Зарплата',
    'Коммунальные',
    'Инструмент',
    'Реклама',
    'Расходники',
  ];

  final _title = TextEditingController();
  final _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseMoney(_amount.text);
    if (amount <= 0) {
      setState(() => _error = 'Укажите сумму больше нуля');
      return;
    }
    await ref.read(reportsRepositoryProvider).addExpense(_title.text, amount);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: 'Расход',
    onSave: _save,
    error: _error,
    children: [
      LiquidSection(
        header: const Text('На что потратили'),
        footer: const Text('Нажмите на подсказку или напишите своё.'),
        children: [
          FormRow(
            label: 'Название',
            controller: _title,
            placeholder: 'Например: Аренда',
            capitalization: TextCapitalization.sentences,
          ),
          ListenableBuilder(
            listenable: _title,
            builder: (_, _) => QuickChips(
              _names,
              (s) => _title.text = s,
              selected: {_title.text.trim()},
            ),
          ),
        ],
      ),
      LiquidSection(
        header: const Text('Сумма'),
        children: [
          FormRow(
            label: 'Сумма, ₽',
            controller: _amount,
            placeholder: '0',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ),
    ],
  );
}
