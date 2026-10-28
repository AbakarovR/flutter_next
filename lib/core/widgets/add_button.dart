import 'package:flutter/cupertino.dart';

import 'glass.dart';

/// Крупная кнопка-плашка с иконкой: синяя подложка, обводка, пружинное нажатие.
class AddButton extends StatelessWidget {
  const AddButton(
    this.label,
    this.onTap, {
    super.key,
    this.icon = CupertinoIcons.add_circled_solid,
  });

  final String label;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Pressable(
        onTap: onTap,
        hoverScale: 1.02,
        pressScale: 0.97,
        child: Glass(
          radius: 20,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: primary.withAlpha(24),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: primary.withAlpha(80), width: 1.2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: primary),
                const SizedBox(width: 8),
                Text(
                  label,
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
    );
  }
}
