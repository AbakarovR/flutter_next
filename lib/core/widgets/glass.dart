import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// Мягкий диагональный градиент от светлого оттенка к основному цвету.
/// Делает плоские иконки «объёмными».
LinearGradient softGradient(Color c) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color.lerp(c, const Color(0xFFFFFFFF), 0.28)!, c],
);

/// Лёгкая стеклянная панель без BackdropFilter.
/// Полупрозрачная заливка и обводка сохраняют стиль, не создавая дорогой
/// отдельный слой размытия для каждой карточки.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = 28});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: dark ? const Color(0x22000000) : const Color(0x0C0F3268),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xD21C293A), Color(0xBF121C2A)]
                : const [Color(0xEFFFFFFF), Color(0xDDF3F7FC)],
          ),
          border: Border.all(
            color: dark ? const Color(0x36FFFFFF) : const Color(0xCCFFFFFF),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Нежный цветной фон под стеклянными поверхностями.
/// Блики декоративные и не перехватывают касания.
class LiquidBackdrop extends StatelessWidget {
  const LiquidBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: dark
                      ? const [
                          Color(0xFF0B1220),
                          Color(0xFF101927),
                          Color(0xFF090E17),
                        ]
                      : const [
                          Color(0xFFF2F7FF),
                          Color(0xFFEAF2FF),
                          Color(0xFFF8F6FF),
                        ],
                ),
              ),
            ),
            const Positioned(
              top: -120,
              right: -100,
              child: _AmbientGlow(
                size: 340,
                light: Color(0x667FCBFF),
                dark: Color(0x333B82F6),
              ),
            ),
            const Positioned(
              bottom: -210,
              right: -70,
              child: _AmbientGlow(
                size: 400,
                light: Color(0x6679D7F2),
                dark: Color(0x2847C2D8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({
    required this.size,
    required this.light,
    required this.dark,
  });

  final double size;
  final Color light;
  final Color dark;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          CupertinoTheme.brightnessOf(context) == Brightness.dark
              ? dark
              : light,
          (CupertinoTheme.brightnessOf(context) == Brightness.dark
                  ? dark
                  : light)
              .withAlpha(0),
        ],
      ),
    ),
  );
}

/// Реагирует на нажатие и наведение мыши: наведение увеличивает,
/// нажатие меняет размер на [pressScale] и даёт лёгкую вибрацию.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.hoverScale = 1.01,
    this.pressScale = 0.98,
  });

  final Widget child;
  final VoidCallback onTap;
  final double hoverScale;
  final double pressScale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scale = _down
        ? widget.pressScale
        : (_hover ? widget.hoverScale : 1.0);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Круглая кнопка с иконкой («+», «Назад»).
/// filled: true = залита градиентом цвета темы, иначе стеклянная.
class NavIconButton extends StatelessWidget {
  const NavIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;
    return Pressable(
      onTap: onTap,
      child: Glass(
        radius: 21,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: filled ? softGradient(primary) : null,
            color: filled ? null : CupertinoColors.transparent,
            border: Border.all(
              color: CupertinoColors.white.withAlpha(filled ? 120 : 190),
            ),
          ),
          child: Icon(
            icon,
            size: 24,
            color: filled ? CupertinoColors.white : primary,
          ),
        ),
      ),
    );
  }
}

/// Кнопка-таблетка с текстом («Отмена», «Готово»).
/// primary: true = синяя, с градиентом, тенью и жирным белым текстом.
class NavTextButton extends StatelessWidget {
  const NavTextButton(
    this.label, {
    super.key,
    required this.onTap,
    this.primary = false,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = CupertinoTheme.of(context).primaryColor;
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 104,
        height: 44,
        child: Glass(
          radius: 22,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: primary ? softGradient(color) : null,
              color: primary
                  ? null
                  : CupertinoColors.secondarySystemFill
                        .resolveFrom(context)
                        .withAlpha(85),
              border: Border.all(
                color: primary
                    ? CupertinoColors.white.withAlpha(150)
                    : CupertinoColors.separator.resolveFrom(context),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 16,
                    color: primary
                        ? CupertinoColors.white
                        : CupertinoColors.label.resolveFrom(context),
                  ),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: primary
                          ? CupertinoColors.white
                          : CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка «Назад»: закрывает текущий экран.
class NavBackButton extends StatelessWidget {
  const NavBackButton({super.key});

  @override
  Widget build(BuildContext context) => NavTextButton(
    'Назад',
    icon: CupertinoIcons.chevron_back,
    onTap: () => Navigator.maybePop(context),
  );
}

/// Своя верхняя панель: полупрозрачное стекло, слева и справа кнопки,
/// по центру заголовок. Заменяет системную CupertinoNavigationBar.
class GlassTopBar extends StatelessWidget {
  const GlassTopBar({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
  });

  static const height = 60.0;
  final String title;
  final Widget? leading, trailing;

  @override
  Widget build(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final top = MediaQuery.paddingOf(context).top;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0xF20E1725) : const Color(0xF2F4F8FF),
        border: Border(
          bottom: BorderSide(
            color: dark ? const Color(0x30FFFFFF) : const Color(0xBFFFFFFF),
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: SizedBox(
          height: height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 120),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
              ),
              if (leading != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: leading,
                  ),
                ),
              if (trailing != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: trailing,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
