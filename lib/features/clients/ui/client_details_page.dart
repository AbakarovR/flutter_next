import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../inventory/product_ext.dart';
import '../providers.dart';
import '../vehicle_service.dart';
import 'client_form_page.dart';
import 'vehicle_history_page.dart';
import 'vehicle_form_page.dart';

/// Что в прошлый раз заливали в двигатель и в коробку этой машины.
class _ServiceInfo extends ConsumerWidget {
  const _ServiceInfo(this.vehicleId);
  final String vehicleId;

  String _line(String label, ServiceEntry e) =>
      '$label: ${e.title} · ${formatQty(e.qtyMilli)} ${e.unit} · '
      '${dayTitle(e.date)}, ${formatKm(e.mileage)} км';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(vehicleServiceProvider(vehicleId)).value;
    final style = metaTextStyle(context);

    if (s == null || s.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('Замен масла ещё не было', style: style),
      );
    }
    final g = s.gearbox;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.engine != null)
            Text(_line('Двигатель', s.engine!), style: style),
          if (g != null)
            Text(
              _line('Коробка (${g.gearbox?.label ?? '—'})', g),
              style: style,
            ),
        ],
      ),
    );
  }
}

class ClientDetailsPage extends ConsumerWidget {
  const ClientDetailsPage({super.key, required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(clientProvider(clientId)).value;
    final vehicles = ref.watch(clientVehiclesProvider(clientId)).value ?? [];
    if (client == null) {
      return const AppPage(title: 'Клиент', children: [Loading()]);
    }
    final repo = ref.read(clientsRepositoryProvider);

    return AppPage(
      title: 'Клиент',
      children: [
        // ── Шапка ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            children: [
              InitialsAvatar(name: client.name, size: 80),
              const SizedBox(height: 12),
              Text(
                client.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if ((client.phone ?? '').isNotEmpty)
                Text(
                  client.phone!,
                  style: const TextStyle(
                    fontSize: 16,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
            ],
          ),
        ),

        // ── Действия ──
        ActionRow([
          ActionItem(
            CupertinoIcons.pencil,
            'Изменить',
            () =>
                openPage(context, ClientFormPage(client: client), modal: true),
          ),
          ActionItem(
            CupertinoIcons.add_circled,
            'Авто',
            () => openPage(
              context,
              VehicleFormPage(clientId: clientId),
              modal: true,
            ),
          ),
          ActionItem(CupertinoIcons.delete, 'Удалить', () async {
            if (!await confirm(
              context,
              'Удалить клиента?',
              'Вместе с его автомобилями.',
            )) {
              return;
            }
            await repo.softDeleteClient(clientId);
            if (context.mounted) Navigator.pop(context);
          }, color: CupertinoColors.systemRed),
        ]),

        // ── Автомобили ──
        LiquidSection(
          header: const Text('Автомобили'),
          footer: vehicles.isEmpty
              ? const Text('Нажмите «Авто», чтобы добавить первый.')
              : const Text(
                  'Нажмите на авто, чтобы изменить. Свайп влево: удалить.',
                ),
          children: [
            for (final v in vehicles)
              Dismissible(
                key: ValueKey(v.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: CupertinoColors.systemRed,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(
                    CupertinoIcons.delete,
                    color: CupertinoColors.white,
                  ),
                ),
                confirmDismiss: (_) =>
                    confirm(context, 'Удалить автомобиль?', v.plate),
                onDismissed: (_) => repo.softDeleteVehicle(v.id),
                child: CupertinoListTile(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  title: Row(children: [PlateBadge(v.plate)]),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${v.brand} ${v.model}${v.year != null ? ', ${v.year}' : ''}',
                        ),
                        _ServiceInfo(v.id),
                        CupertinoButton.filled(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          minimumSize: const Size(0, 44),
                          alignment: Alignment.centerLeft,
                          borderRadius: BorderRadius.circular(14),
                          onPressed: () =>
                              openPage(context, VehicleHistoryPage(vehicle: v)),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(CupertinoIcons.clock, size: 17),
                              SizedBox(width: 8),
                              Text('Вся история обслуживания'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  additionalInfo: Text('${formatKm(v.mileage)} км'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => openPage(
                    context,
                    VehicleFormPage(clientId: clientId, vehicle: v),
                    modal: true,
                  ),
                ),
              ),
          ],
        ),

        // ── Заметка (если есть) ──
        if ((client.note ?? '').isNotEmpty)
          LiquidSection(
            header: const Text('Заметка'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(client.note!),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
