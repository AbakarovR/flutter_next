import 'package:flutter/cupertino.dart';

import 'glass.dart';
import 'pill_tabs.dart';

const _grey = CupertinoColors.systemGrey;

/// Читаемый стиль для вторичной информации: даты, пробега и примечаний.
TextStyle metaTextStyle(
  BuildContext context, {
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.w400,
}) => TextStyle(
  fontSize: fontSize,
  height: 1.3,
  fontWeight: fontWeight,
  color: CupertinoColors.systemGrey.resolveFrom(context),
);

/// Стеклянная сгруппированная секция для всех основных экранов.
/// Параметры header, footer и children соответствуют CupertinoListSection,
/// поэтому бизнес-разметка экранов остаётся обычной Cupertino-разметкой.
class LiquidSection extends StatelessWidget {
  const LiquidSection({
    super.key,
    this.header,
    this.footer,
    required this.children,
    this.margin,
  });

  final Widget? header;
  final Widget? footer;
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Glass(
      radius: 24,
      child: CupertinoListSection.insetGrouped(
        header: header,
        footer: footer,
        margin: EdgeInsets.zero,
        backgroundColor: CupertinoColors.transparent,
        decoration: BoxDecoration(
          color: CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        clipBehavior: Clip.antiAlias,
        children: children,
      ),
    ),
  );
}

/// Открыть экран. modal: true = выезжает снизу (для форм).
PageRoute<T> quickPageRoute<T>(Widget page, {bool modal = false}) =>
    PageRouteBuilder<T>(
      fullscreenDialog: modal,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, animation, _, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final offset = Tween<Offset>(
          begin: modal ? const Offset(0, 0.025) : const Offset(0.025, 0),
          end: Offset.zero,
        ).animate(curve);
        return SlideTransition(position: offset, child: child);
      },
    );

Future<void> openPage(
  BuildContext context,
  Widget page, {
  bool modal = false,
}) =>
    Navigator.of(context).push<void>(quickPageRoute<void>(page, modal: modal));

/// Диалог «Вы уверены?». Возвращает true, если нажали главную кнопку.
/// destructive: true = красная кнопка (удаление), false = обычная.
Future<bool> confirm(
  BuildContext context,
  String title,
  String text, {
  String action = 'Удалить',
  bool destructive = true,
}) async =>
    await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// Обычная страница (карточка клиента, товара, заказа): серый фон,
/// стеклянная панель сверху, прокрутка. Слева «Назад», если есть куда вернуться.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.children,
    this.leading,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? leading, trailing;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.transparent,
      child: Stack(
        children: [
          ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(
              top: mq.padding.top + GlassTopBar.height + 8,
              bottom: mq.padding.bottom + 32,
            ),
            children: children,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GlassTopBar(
              title: title,
              leading:
                  leading ??
                  (Navigator.of(context).canPop()
                      ? const NavBackButton()
                      : null),
              trailing: trailing,
            ),
          ),
        ],
      ),
    );
  }
}

/// Страница-форма: «Отмена» слева, «Готово» справа, ошибка внизу.
class FormPage extends StatelessWidget {
  const FormPage({
    super.key,
    required this.title,
    required this.onSave,
    required this.children,
    this.error,
  });

  final String title;
  final VoidCallback onSave;
  final List<Widget> children;
  final String? error;

  @override
  Widget build(BuildContext context) => AppPage(
    title: title,
    leading: NavTextButton('Отмена', onTap: () => Navigator.pop(context)),
    trailing: NavTextButton('Готово', onTap: onSave, primary: true),
    children: [
      ...children,
      if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
          child: Text(
            error!,
            style: const TextStyle(
              color: CupertinoColors.systemRed,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
    ],
  );
}

/// Страница списка с большим заголовком, который сворачивается при прокрутке.
class LargeTitlePage extends StatelessWidget {
  const LargeTitlePage({
    super.key,
    required this.title,
    required this.children,
    this.onAdd,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onAdd; // если задан, справа появляется «+»

  @override
  Widget build(BuildContext context) {
    final add = onAdd;
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.transparent,
      child: Stack(
        children: [
          CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: Text(title),
                trailing: add == null
                    ? null
                    : NavIconButton(
                        icon: CupertinoIcons.add,
                        onTap: add,
                        filled: true,
                      ),
              ),
              SliverSafeArea(
                top: false,
                sliver: SliverList(delegate: SliverChildListDelegate(children)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Крутилка загрузки.
class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(40),
    child: Center(child: CupertinoActivityIndicator()),
  );
}

/// Пустой экран: иконка в мягком круге, текст и (по желанию) кнопка.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.text,
    this.button,
    this.onPressed,
  });

  final IconData icon;
  final String text;
  final String? button;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CupertinoColors.white.withAlpha(95),
              border: Border.all(color: CupertinoColors.white.withAlpha(180)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x160F3268),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, size: 44, color: CupertinoColors.systemGrey),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _grey, fontSize: 16),
          ),
          if (onPressed != null) ...[
            const SizedBox(height: 16),
            CupertinoButton.filled(
              borderRadius: BorderRadius.circular(22),
              onPressed: onPressed,
              child: Text(button ?? 'Добавить'),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Серая подсказка по центру.
class Hint extends StatelessWidget {
  const Hint(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 14,
        height: 1.3,
        color: CupertinoColors.systemGrey.resolveFrom(context),
      ),
    ),
  );
}

/// Строка поиска.
class SearchField extends StatelessWidget {
  const SearchField(this.placeholder, this.onChanged, {super.key});
  final String placeholder;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Glass(
      radius: 17,
      child: CupertinoSearchTextField(
        placeholder: placeholder,
        onChanged: onChanged,
        backgroundColor: CupertinoColors.transparent,
        borderRadius: BorderRadius.circular(17),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    ),
  );
}

/// Переключатель на всю ширину: items = {значение: подпись}.
/// Рисует тот же PillTabs, поэтому выглядит одинаково во всём приложении.
class Segments<T extends Object> extends StatelessWidget {
  const Segments({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) =>
      PillTabs<T>(value: value, items: items, onChanged: onChanged);
}

/// Одна кнопка-действие в ряду.
class ActionItem {
  const ActionItem(this.icon, this.label, this.onTap, {this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color; // по умолчанию цвет темы (синий)
}

/// Ряд кнопок-действий: иконка в цветном круге и подпись на карточке.
class ActionRow extends StatelessWidget {
  const ActionRow(this.items, {super.key});
  final List<ActionItem> items;

  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          for (final a in items)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Pressable(
                  onTap: a.onTap,
                  hoverScale: 1.05,
                  pressScale: 0.93,
                  child: Glass(
                    radius: 22,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: CupertinoColors.transparent,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (a.color ?? primary).withAlpha(30),
                            ),
                            child: Icon(
                              a.icon,
                              size: 22,
                              color: a.color ?? primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            a.label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: a.color ?? primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
