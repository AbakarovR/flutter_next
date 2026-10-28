import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_localizations/flutter_localizations.dart';

import 'home_shell.dart';

/// Разрешает прокручивать списки перетаскиванием мышью (на десктопе).
class _AppScroll extends CupertinoScrollBehavior {
  const _AppScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}

class OilProApp extends StatelessWidget {
  const OilProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      title: 'OilPro',
      debugShowCheckedModeBanner: false,
      scrollBehavior: _AppScroll(),
      theme: CupertinoThemeData(
        primaryColor: CupertinoColors.systemBlue,
        scaffoldBackgroundColor: CupertinoColors.transparent,
        barBackgroundColor: CupertinoDynamicColor.withBrightness(
          color: Color(0xDDF7FAFF),
          darkColor: Color(0xCC101927),
        ),
      ),
      locale: Locale('ru'),
      supportedLocales: [Locale('ru'), Locale('en')],
      localizationsDelegates: [
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: HomeShell(),
    );
  }
}
