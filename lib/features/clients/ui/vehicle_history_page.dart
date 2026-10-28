import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../orders/order_ext.dart';
import '../../orders/ui/order_details_page.dart';
import '../vehicle_service.dart';

/// Полный список завершённых заказ-нарядов конкретного автомобиля.
class VehicleHistoryPage extends ConsumerWidget {
  const VehicleHistoryPage({super.key, required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(vehicleHistoryProvider(vehicle.id));

    return AppPage(
      title: 'История обслуживания',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
          child: Column(
            children: [
              Text(
                '${vehicle.brand} ${vehicle.model}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(vehicle.plate, style: metaTextStyle(context, fontSize: 15)),
            ],
          ),
        ),
        if (history.isLoading)
          const Loading()
        else if (history.hasError)
          const Hint('Не удалось загрузить историю обслуживания.')
        else if ((history.value ?? []).isEmpty)
          const EmptyState(
            icon: CupertinoIcons.clock,
            text: 'Завершённых визитов пока нет',
          )
        else
          for (final visit in history.value!)
            LiquidSection(
              header: Text(
                '${formatDateTime(visit.order.completionDate)} · '
                '${formatKm(visit.order.mileage)} км',
                style: metaTextStyle(
                  context,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                for (final line in visit.lines)
                  CupertinoListTile(
                    title: Text(line.item.title),
                    subtitle: Text(
                      '${formatQty(line.item.qtyMilli)}'
                      '${line.unit.isEmpty ? '' : ' ${line.unit}'} × '
                      '${formatMoney(line.item.priceKopecks)}',
                    ),
                    additionalInfo: Text(formatMoney(line.item.sumKopecks)),
                  ),
                CupertinoListTile(
                  title: const Text(
                    'Итого',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  additionalInfo: Text(
                    formatMoney(visit.order.totalKopecks),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => openPage(
                    context,
                    OrderDetailsPage(orderId: visit.order.id),
                  ),
                ),
              ],
            ),
      ],
    );
  }
}
