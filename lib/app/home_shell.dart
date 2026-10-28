import 'package:flutter/cupertino.dart';

import '../core/widgets/glass.dart';
import '../features/clients/ui/clients_page.dart';
import '../features/inventory/ui/inventory_page.dart';
import '../features/orders/ui/orders_page.dart';
import '../features/reports/ui/reports_page.dart';
import '../features/reports/ui/sale_picker_page.dart';

/// Считает, сколько экранов открыто в одной вкладке.
/// 1 = только корневой список, больше = мы зашли вглубь.
class _DepthObserver extends NavigatorObserver {
  final depth = ValueNotifier<int>(0);
  int _n = 0;

  void _publish() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => depth.value = _n);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _n++;
    _publish();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _n--;
    _publish();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _n--;
    _publish();
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _barHeight = 72.0;

  int _index = 0;
  final _observers = List.generate(5, (_) => _DepthObserver());
  final _tabs = List<Widget?>.filled(5, null);

  @override
  void dispose() {
    for (final o in _observers) {
      o.depth.dispose();
    }
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    _tab(i);
    setState(() => _index = i);
  }

  Widget _tab(int i) => _tabs[i] ??= CupertinoTabView(
    navigatorObservers: [_observers[i]],
    builder: (_) => _page(i),
  );

  Widget _page(int i) => switch (i) {
    0 => const OrdersPage(),
    1 => const ClientsPage(),
    2 => const InventoryPage(),
    3 => const SalePickerPage(isTab: true),
    _ => const ReportsPage(),
  };

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final safeBottom = mq.padding.bottom;
    _tab(_index);

    return Stack(
      fit: StackFit.expand,
      children: [
        const LiquidBackdrop(),
        ValueListenableBuilder<int>(
          valueListenable: _observers[_index].depth,
          builder: (context, depth, _) {
            // Панель видна только на корневых списках вкладок.
            final showBar = depth <= 1;
            final space = showBar
                ? _barHeight + 12 + safeBottom + 8
                : safeBottom;

            return Stack(
              fit: StackFit.expand,
              children: [
                MediaQuery(
                  data: mq.copyWith(
                    padding: mq.padding.copyWith(bottom: space),
                  ),
                  // IndexedStack хранит вкладки живыми: переключение быстрое
                  // и не перезапускает содержимое экранов.
                  child: IndexedStack(
                    index: _index,
                    children: [
                      for (var i = 0; i < 5; i++)
                        _tabs[i] ?? const SizedBox.shrink(),
                    ],
                  ),
                ),
                if (showBar)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: safeBottom + 12,
                    child: Align(
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _FloatingTabBar(
                            index: _index,
                            height: _barHeight,
                            onTap: _select,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Парящая стеклянная панель вкладок.
class _FloatingTabBar extends StatelessWidget {
  const _FloatingTabBar({
    required this.index,
    required this.onTap,
    required this.height,
  });

  final int index;
  final double height;
  final ValueChanged<int> onTap;

  // Обычная иконка, залитая иконка (для выбранной) и подпись.
  static const _items = <(IconData, IconData, String)>[
    (CupertinoIcons.doc_text, CupertinoIcons.doc_text_fill, 'Заказы'),
    (CupertinoIcons.person_2, CupertinoIcons.person_2_fill, 'Клиенты'),
    (CupertinoIcons.cube_box, CupertinoIcons.cube_box_fill, 'Склад'),
    (CupertinoIcons.cart, CupertinoIcons.cart_fill, 'Продажи'),
    (CupertinoIcons.chart_bar, CupertinoIcons.chart_bar_fill, 'Отчёт'),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;
    final idle = CupertinoColors.systemGrey.resolveFrom(context);
    final n = _items.length;

    return Glass(
      radius: height / 2,
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            // «Пузырь» под выбранной вкладкой плавно переезжает.
            AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment(-1 + 2 * index / (n - 1), 0),
              child: FractionallySizedBox(
                widthFactor: 1 / n,
                heightFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: primary.withAlpha(40),
                      borderRadius: BorderRadius.circular(height / 2 - 6),
                      border: Border.all(color: primary.withAlpha(50)),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < n; i++)
                  Expanded(
                    child: Pressable(
                      onTap: () => onTap(i),
                      hoverScale: 1.01,
                      pressScale: 0.98,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedScale(
                            scale: i == index ? 1.04 : 1,
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOut,
                            child: Icon(
                              i == index ? _items[i].$2 : _items[i].$1,
                              size: 26,
                              color: i == index ? primary : idle,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _items[i].$3,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: i == index
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: i == index ? primary : idle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
