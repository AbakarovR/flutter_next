import 'package:flutter/cupertino.dart';

/// Госномер в рамке, как на табличке. Белый фон и чёрный текст заданы
/// жёстко, чтобы номер выглядел одинаково и в светлой, и в тёмной теме.
class PlateBadge extends StatelessWidget {
  const PlateBadge(this.plate, {super.key, this.small = false});

  final String plate;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 10,
        vertical: small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(small ? 4 : 6),
        border: Border.all(color: const Color(0xFF222222), width: 1.4),
      ),
      child: Text(
        plate.isEmpty ? '— — —' : plate,
        style: TextStyle(
          color: const Color(0xFF111111),
          fontSize: small ? 12 : 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
