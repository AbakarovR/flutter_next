import 'package:flutter/cupertino.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/glass.dart';
import '../../inventory/ui/inventory_widgets.dart';
import '../order_ext.dart';

/// Цветная плашка статуса заказа.
class OrderStatusPill extends StatelessWidget {
  const OrderStatusPill(this.status, {super.key});
  final OrderStatus status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: status.color.withAlpha(38),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      status.label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: status.color,
      ),
    ),
  );
}

/// Иконка строки заказа: kind == null означает работу (фиолетовый ключ),
/// иначе иконка типа товара (как на складе).
class ItemIcon extends StatelessWidget {
  const ItemIcon({super.key, this.kind, this.size = 36});
  final ProductKind? kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = kind;
    if (k != null) return ProductIcon(k, size: size);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: softGradient(CupertinoColors.systemPurple),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.systemPurple.withAlpha(70),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        CupertinoIcons.wrench_fill,
        color: CupertinoColors.white,
        size: size * 0.55,
      ),
    );
  }
}

/// Ряд быстрых кнопок-подсказок.
/// [selected] — подсказки, которые уже выбраны: они подсвечиваются синим.
class QuickChips extends StatelessWidget {
  const QuickChips(
    this.labels,
    this.onTap, {
    super.key,
    this.selected = const {},
  });

  final List<String> labels;
  final ValueChanged<String> onTap;
  final Set<String> selected;

  @override
  Widget build(BuildContext context) {
    final blue = CupertinoTheme.of(context).primaryColor;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final l in labels)
            Pressable(
              onTap: () => onTap(l),
              hoverScale: 1.04,
              pressScale: 0.94,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected.contains(l)
                      ? blue.withAlpha(46)
                      : CupertinoColors.systemGrey5.resolveFrom(context),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected.contains(l)
                        ? blue.withAlpha(120)
                        : CupertinoColors.transparent,
                  ),
                ),
                child: Text(
                  l,
                  style: TextStyle(
                    fontSize: 14,
                    color: selected.contains(l) ? blue : null,
                    fontWeight: selected.contains(l) ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
