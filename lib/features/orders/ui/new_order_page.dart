import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../core/utils/plate.dart';
import '../../../core/widgets/add_button.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../clients/providers.dart';
import '../providers.dart';
import 'order_details_page.dart';
import 'quick_car_page.dart';

class NewOrderPage extends ConsumerStatefulWidget {
  const NewOrderPage({super.key});

  @override
  ConsumerState<NewOrderPage> createState() => _NewOrderPageState();
}

class _NewOrderPageState extends ConsumerState<NewOrderPage> {
  String _query = '';

  /// Перед заказом уточняем актуальный пробег: в карточке авто может быть
  /// сохранён пробег с прошлого визита.
  Future<int?> _askMileage(int previousMileage) async {
    final controller = TextEditingController(text: previousMileage.toString());
    String? error;
    try {
      return await showCupertinoDialog<int>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => CupertinoAlertDialog(
            title: const Text('Пробег автомобиля'),
            content: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoTextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    placeholder: 'км',
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(
                        color: CupertinoColors.systemRed,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена'),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () {
                  final mileage = int.tryParse(controller.text.trim());
                  if (mileage == null || mileage < 0) {
                    setDialogState(
                      () => error = 'Введите пробег целым числом от 0 км.',
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, mileage);
                },
                child: const Text('Продолжить'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  /// Создаём заказ и заменяем экран выбора на сам заказ.
  Future<void> _create(
    String clientId,
    String vehicleId,
    int mileage, {
    bool askForMileage = true,
  }) async {
    final actualMileage = askForMileage ? await _askMileage(mileage) : mileage;
    if (actualMileage == null || !mounted) return;
    final id = await ref
        .read(ordersRepositoryProvider)
        .createDraft(
          clientId: clientId,
          vehicleId: vehicleId,
          mileage: actualMileage,
        );
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(quickPageRoute<void>(OrderDetailsPage(orderId: id)));
  }

  /// Нового клиента с машиной создаём прямо здесь и сразу открываем заказ.
  Future<void> _quickNew() async {
    final car = await Navigator.of(context).push<NewCar>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => QuickCarPage(initialQuery: _query),
      ),
    );
    if (car != null && mounted) {
      await _create(
        car.clientId,
        car.vehicleId,
        car.mileage,
        askForMileage: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsListProvider).value;
    if (clients == null) {
      return const AppPage(title: 'Новый заказ', children: [Loading()]);
    }

    // Плоский список пар «клиент + его авто».
    final q = _query.trim().toLowerCase();
    final rows = [
      for (final i in clients)
        for (final v in i.vehicles)
          if (q.isEmpty ||
              v.plate.contains(normalizePlate(q)) ||
              i.client.name.toLowerCase().contains(q) ||
              '${v.brand} ${v.model}'.toLowerCase().contains(q))
            (i.client, v),
    ];

    return AppPage(
      title: 'Новый заказ',
      children: [
        SearchField(
          'Госномер, марка или имя клиента',
          (v) => setState(() => _query = v),
        ),
        AddButton(
          'Новый клиент и авто',
          _quickNew,
          icon: CupertinoIcons.person_add_solid,
        ),
        if (rows.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.car_detailed,
            text: 'Такой машины нет.\nНажмите «Новый клиент и авто».',
          )
        else
          LiquidSection(
            header: const Text('Или выберите автомобиль'),
            children: [
              for (final (c, v) in rows)
                CupertinoListTile(
                  leadingSize: 40,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  leading: InitialsAvatar(name: c.name, size: 40),
                  title: Row(children: [PlateBadge(v.plate)]),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${v.brand} ${v.model} · ${c.name}'),
                  ),
                  additionalInfo: Text('${formatKm(v.mileage)} км'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => _create(c.id, v.id, v.mileage),
                ),
            ],
          ),
      ],
    );
  }
}
