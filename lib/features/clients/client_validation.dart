/// Нормализация и проверки данных клиента и его автомобиля.
/// Оставляем правила в одном месте, чтобы формы одинаково принимали данные.
class ClientValidation {
  static String cleanText(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String? validateName(String value) {
    final name = cleanText(value);
    if (name.length < 2) return 'Укажите имя клиента полностью';
    if (name.length > 80) return 'Имя не должно быть длиннее 80 символов';
    if (!RegExp(
      r"^[\p{L}\p{M}][\p{L}\p{M} .'-]*$",
      unicode: true,
    ).hasMatch(name)) {
      return 'В имени используйте буквы, пробелы и дефис';
    }
    return null;
  }

  /// Российский номер приводим к единому виду +7 (XXX) XXX-XX-XX.
  static String? normalizePhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    String national;
    if (digits.length == 10) {
      national = digits;
    } else if (digits.length == 11 &&
        (digits.startsWith('7') || digits.startsWith('8'))) {
      national = digits.substring(1);
    } else {
      return null;
    }
    if (national.startsWith('0')) return null;
    return '+7 (${national.substring(0, 3)}) '
        '${national.substring(3, 6)}-'
        '${national.substring(6, 8)}-'
        '${national.substring(8, 10)}';
  }

  static String? validateVehicleName(String value, String label) {
    final text = cleanText(value);
    if (text.isEmpty) return 'Укажите $label';
    if (text.length > 60) return '$label не должно быть длиннее 60 символов';
    if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text)) {
      return 'Проверьте поле «$label»';
    }
    if (!RegExp(
      r"^[\p{L}\p{M}\p{N} .,'()+/#&\-]+$",
      unicode: true,
    ).hasMatch(text)) {
      return 'В поле «$label» есть недопустимые символы';
    }
    return null;
  }

  static String? validateVin(String value) {
    final vin = value.trim().toUpperCase();
    if (vin.isEmpty) return null;
    return RegExp(r'^[A-HJ-NPR-Z0-9]{17}$').hasMatch(vin)
        ? null
        : 'VIN должен содержать 17 символов без I, O и Q';
  }

  static String? validateYear(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final year = int.tryParse(text);
    if (year == null || year < 1886 || year > DateTime.now().year + 1) {
      return 'Укажите год от 1886 до ${DateTime.now().year + 1}';
    }
    return null;
  }

  static String? validateMileage(String value) {
    final text = value.trim();
    final mileage = int.tryParse(text);
    if (text.isEmpty || mileage == null || mileage < 0) {
      return 'Укажите пробег целым числом от 0 км';
    }
    if (mileage > 10000000) return 'Проверьте пробег';
    return null;
  }
}
