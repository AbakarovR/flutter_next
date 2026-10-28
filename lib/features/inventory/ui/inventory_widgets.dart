import 'package:flutter/cupertino.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/glass.dart';
import '../product_ext.dart';

/// Квадрат с градиентом, иконкой типа товара и мягкой тенью.
class ProductIcon extends StatelessWidget {
  const ProductIcon(this.kind, {super.key, this.size = 44});
  final ProductKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: softGradient(kind.color),
      borderRadius: BorderRadius.circular(size * 0.3),
      boxShadow: [
        BoxShadow(
          color: kind.color.withAlpha(70),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Icon(kind.icon, color: CupertinoColors.white, size: size * 0.55),
  );
}

/// Плашка статуса: В наличии / Заканчивается / Нет в наличии.
class StatusPill extends StatelessWidget {
  const StatusPill(this.product, {super.key});
  final Product product;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: product.statusColor.withAlpha(38),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      product.statusText,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: product.statusColor,
      ),
    ),
  );
}

/// Полоска уровня остатка (только если задан порог). Длина меняется плавно.
class StockBar extends StatelessWidget {
  const StockBar(this.product, {super.key});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final level = product.level;
    if (level == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        width: 140,
        height: 6,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: ColoredBox(
            color: CupertinoColors.systemGrey5.resolveFrom(context),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: level),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: v,
                child: ColoredBox(color: product.statusColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Карточка сводки. Нажатие включает фильтр, рамка появляется плавно.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.value,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String value, label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    hoverScale: 1.03,
    pressScale: 0.96,
    child: Glass(
      radius: 20,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(18) : CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? color.withAlpha(210)
                : CupertinoColors.white.withAlpha(110),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 14,
                height: 1.2,
                color: CupertinoColors.systemGrey,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
