import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  // Нужно, если до runApp мы будем вызывать нативный код
  // (например, открывать базу данных). На будущее.
  WidgetsFlutterBinding.ensureInitialized();

  // ProviderScope хранит всё состояние Riverpod.
  // Без него провайдеры не заработают.
  runApp(const ProviderScope(child: OilProApp()));
}
