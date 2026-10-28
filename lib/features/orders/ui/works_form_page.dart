import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/ui_kit.dart';
import '../data/work_extras.dart';
import '../providers.dart';

/// Одна выбранная работа: поле названия и поле цены.
class _WorkRow {
  _WorkRow(String title, int priceKopecks)
    : title = TextEditingController(text: title),
      price = TextEditingController(
        text: priceKopecks > 0 ? kopecksToInput(priceKopecks) : null,
      );

  final TextEditingController title;
  final TextEditingController price;
}

/// Экран «Работы»: нажимаешь варианты, каждый становится строкой
/// со своей ценой, а «Готово» добавляет всё в заказ.
class WorksFormPage extends ConsumerStatefulWidget {
  const WorksFormPage({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<WorksFormPage> createState() => _WorksFormPageState();
}

class _WorksFormPageState extends ConsumerState<WorksFormPage> {
  /// (короткая подпись, полное название работы)
  static const _oilWorks = [
    ('Двигатель', 'Замена масла'),
    ('Коробка передач', 'Замена масла в коробке'),
  ];
  static const _filterWorks = [
    ('Масляный фильтр', 'Замена масляного фильтра'),
    ('Воздушный фильтр', 'Замена воздушного фильтра'),
    ('Салонный фильтр', 'Замена салонного фильтра'),
  ];

  /// Строки, которые видит пользователь.
  final _rows = <_WorkRow>[];

  /// Все созданные строки: контроллеры освобождаем разом в dispose.
  final _created = <_WorkRow>[];

  Map<String, int> _lastPrices = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    // Подгружаем последние цены и подставляем в пустые поля.
    ref.read(ordersRepositoryProvider).lastWorkPrices().then((m) {
      if (!mounted) return;
      setState(() {
        _lastPrices = m;
        for (final r in _rows) {
          final p = m[r.title.text.trim()];
          if (r.price.text.isEmpty && p != null) {
            r.price.text = kopecksToInput(p);
          }
        }
      });
    });
  }

  @override
  void dispose() {
    for (final r in _created) {
      r.title.dispose();
      r.price.dispose();
    }
    super.dispose();
  }

  _WorkRow _newRow(String title) {
    final r = _WorkRow(title, _lastPrices[title] ?? 0);
    _created.add(r);
    return r;
  }

  /// Нажали вариант: добавляем строку или убираем, если уже есть.
  void _toggle(String name) {
    HapticFeedback.selectionClick();
    setState(() {
      final i = _rows.indexWhere((r) => r.title.text.trim() == name);
      if (i >= 0) {
        _rows.removeAt(i);
      } else {
        _rows.add(_newRow(name));
      }
    });
  }

  Future<void> _save() async {
    final works = [
      for (final r in _rows)
        if (r.title.text.trim().isNotEmpty)
          (r.title.text.trim(), parseMoney(r.price.text)),
    ];
    if (works.isEmpty) {
      setState(() => _error = 'Выберите хотя бы одну работу');
      return;
    }
    await ref
        .read(ordersRepositoryProvider)
        .addWorkItems(widget.orderId, works);
    if (mounted) Navigator.pop(context, true);
  }

  /// Капсула на всю ширину с равными частями и разделителями.
  /// Можно выбрать несколько вариантов: каждый выбранный подсвечен.
  Widget _segments(List<(String, String)> items, Set<String> selected) {
    final primary = CupertinoTheme.of(context).primaryColor;
    final track = CupertinoColors.tertiarySystemFill.resolveFrom(context);
    final text = CupertinoColors.label.resolveFrom(context);
    final line = CupertinoColors.separator.resolveFrom(context);
    final n = items.length;

    bool on(int i) => selected.contains(items[i].$2);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: track,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            for (var i = 0; i < n; i++)
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _toggle(items[i].$2),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: on(i) ? primary : CupertinoColors.transparent,
                          borderRadius: BorderRadius.circular(19),
                          boxShadow: on(i)
                              ? [
                                  BoxShadow(
                                    color: primary.withAlpha(80),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : const [],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: on(i)
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: on(i) ? CupertinoColors.white : text,
                              ),
                              child: Text(
                                items[i].$1,
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Разделитель справа; рядом с выбранным варианты скрыт.
                    if (i < n - 1)
                      Align(
                        alignment: Alignment.centerRight,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: (on(i) || on(i + 1)) ? 0 : 1,
                            child: Container(width: 1, height: 18, color: line),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = Listenable.merge([for (final r in _rows) r.title]);
    final prices = Listenable.merge([for (final r in _rows) r.price]);
    final primary = CupertinoTheme.of(context).primaryColor;

    return FormPage(
      title: 'Работы',
      onSave: _save,
      error: _error,
      children: [
        LiquidSection(
          header: const Text('Замена масла'),
          children: [
            ListenableBuilder(
              listenable: titles,
              builder: (_, _) => _segments(_oilWorks, {
                for (final r in _rows) r.title.text.trim(),
              }),
            ),
          ],
        ),
        LiquidSection(
          header: const Text('Замена фильтра'),
          footer: const Text(
            'Нажимайте на варианты: каждый станет отдельной строкой со своей ценой.',
          ),
          children: [
            ListenableBuilder(
              listenable: titles,
              builder: (_, _) => _segments(_filterWorks, {
                for (final r in _rows) r.title.text.trim(),
              }),
            ),
          ],
        ),
        if (_rows.isNotEmpty)
          LiquidSection(
            header: const Text('Выбрано'),
            footer: ListenableBuilder(
              listenable: prices,
              builder: (_, _) {
                final sum = _rows.fold<int>(
                  0,
                  (s, r) => s + parseMoney(r.price.text),
                );
                return Text(
                  'Работ: ${_rows.length}. Сумма: ${formatMoney(sum)}.',
                );
              },
            ),
            children: [
              for (final r in _rows)
                Padding(
                  key: ObjectKey(r),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.all(6),
                        minimumSize: Size.zero,
                        onPressed: () => setState(() => _rows.remove(r)),
                        child: const Icon(
                          CupertinoIcons.minus_circle_fill,
                          color: CupertinoColors.systemRed,
                          size: 22,
                        ),
                      ),
                      Expanded(
                        child: CupertinoTextField(
                          controller: r.title,
                          // Новая пустая строка сразу получает курсор.
                          autofocus: r.title.text.isEmpty,
                          placeholder: 'Название работы',
                          decoration: null,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ),
                      SizedBox(
                        width: 96,
                        child: CupertinoTextField(
                          controller: r.price,
                          placeholder: 'Цена',
                          suffix: const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Text(
                              '₽',
                              style: TextStyle(
                                color: CupertinoColors.systemGrey,
                              ),
                            ),
                          ),
                          textAlign: TextAlign.right,
                          decoration: null,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        // ── Кнопка «Другая работа» в общем стиле ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Pressable(
            onTap: () => setState(() => _rows.add(_newRow(''))),
            hoverScale: 1.02,
            pressScale: 0.97,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: primary.withAlpha(30),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primary.withAlpha(90), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.add_circled_solid,
                    size: 22,
                    color: primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Другая работа',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
