import 'package:flutter/cupertino.dart';

/// Строка формы: слева подпись, справа поле ввода.
/// Вынесли в отдельный виджет, чтобы не копировать одно и то же
/// в каждой форме (клиент, авто, товар, заказ).
class FormRow extends StatelessWidget {
  const FormRow({
    super.key,
    required this.label,
    required this.controller,
    this.placeholder,
    this.keyboardType,
    this.capitalization = TextCapitalization.none,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final String? placeholder;
  final TextInputType? keyboardType;
  final TextCapitalization capitalization;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label)),
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              placeholder: placeholder,
              keyboardType: keyboardType,
              textCapitalization: capitalization,
              maxLines: maxLines,
              cursorColor: CupertinoTheme.of(context).primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: dark ? const Color(0x331F2A3A) : const Color(0x80FFFFFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: dark
                      ? const Color(0x30FFFFFF)
                      : const Color(0xA6FFFFFF),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
