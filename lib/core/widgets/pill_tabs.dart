import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'glass.dart';

/// Ряд вкладок на всю ширину: все варианты делят место поровну,
/// между ними тонкие разделители, выбранный подсвечен «пузырём»,
/// который плавно переезжает. items = {значение: подпись}.
class PillTabs<T extends Object> extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;
    final track = CupertinoColors.tertiarySystemFill.resolveFrom(context);
    final text = CupertinoColors.label.resolveFrom(context);
    final line = CupertinoColors.separator.resolveFrom(context);
    final keys = items.keys.toList();
    final n = keys.length;
    final index = keys.indexOf(value).clamp(0, n - 1);

    /// Разделитель справа от вкладки i (после последней его нет).
    /// Прячется, если рядом выбранная вкладка: у неё свой «пузырь».
    Widget divider(int i) {
      final hidden = i == index || i + 1 == index;
      if (hidden) return const SizedBox(width: 1, height: 18);
      return Container(width: 1, height: 18, color: line);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Glass(
        radius: 22,
        child: Container(
          height: 42,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: track.withAlpha(45),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Stack(
            children: [
              // «Пузырь» под выбранной вкладкой плавно переезжает.
              AnimatedAlign(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / n,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(17),
                      boxShadow: [
                        BoxShadow(
                          color: primary.withAlpha(80),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < n; i++)
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (keys[i] == value) return;
                              HapticFeedback.selectionClick();
                              onChanged(keys[i]);
                            },
                            child: SizedBox.expand(
                              child: Center(
                                // FittedBox уменьшает длинную подпись, а не обрезает её.
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: AnimatedDefaultTextStyle(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: keys[i] == value
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: keys[i] == value
                                            ? CupertinoColors.white
                                            : text,
                                      ),
                                      child: Text(
                                        items[keys[i]]!,
                                        maxLines: 1,
                                        softWrap: false,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (i < n - 1)
                            Align(
                              alignment: Alignment.centerRight,
                              child: IgnorePointer(child: divider(i)),
                            ),
                        ],
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
}
