import 'package:flutter/cupertino.dart';

import 'glass.dart';

/// Круглая кнопка «+» или «−». Если [onTap] == null, она серая и неактивна.
class RoundButton extends StatelessWidget {
  const RoundButton(
    this.icon,
    this.onTap, {
    super.key,
    this.minus = false,
    this.size = 36,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool minus;
  final double size;

  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;
    final active = onTap != null;
    final box = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: active && !minus ? softGradient(primary) : null,
        color: !active
            ? CupertinoColors.systemGrey5.resolveFrom(context)
            : (minus ? CupertinoColors.systemRed.withAlpha(30) : null),
      ),
      child: Icon(
        icon,
        size: 20,
        color: !active
            ? CupertinoColors.systemGrey3.resolveFrom(context)
            : (minus ? CupertinoColors.systemRed : CupertinoColors.white),
      ),
    );
    return active ? Pressable(onTap: onTap!, child: box) : box;
  }
}
