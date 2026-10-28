import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/plate.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../core/widgets/ui_kit.dart';
import '../data/clients_repository.dart';
import '../providers.dart';
import 'client_details_page.dart';
import 'client_form_page.dart';

class ClientsPage extends ConsumerStatefulWidget {
  const ClientsPage({super.key});

  @override
  ConsumerState<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends ConsumerState<ClientsPage> {
  String _query = '';

  /// Поиск по имени, телефону или госномеру.
  bool _match(ClientListItem i) {
    final q = _query.trim().toLowerCase();
    return q.isEmpty ||
        i.client.name.toLowerCase().contains(q) ||
        (i.client.phone ?? '').contains(q) ||
        i.vehicles.any((v) => v.plate.contains(normalizePlate(q)));
  }

  void _add() => openPage(context, const ClientFormPage(), modal: true);

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(clientsListProvider).value;
    if (all == null) {
      return const LargeTitlePage(title: 'Клиенты', children: [Loading()]);
    }

    // Раскладываем по первой букве имени (список уже отсортирован).
    final groups = <String, List<ClientListItem>>{};
    for (final i in all.where(_match)) {
      final name = i.client.name.trim();
      final ch = name.isEmpty ? '#' : name[0].toUpperCase();
      final key = RegExp(r'[A-ZА-ЯЁ]').hasMatch(ch) ? ch : '#';
      groups.putIfAbsent(key, () => []).add(i);
    }

    return LargeTitlePage(
      title: 'Клиенты',
      onAdd: _add,
      children: [
        if (all.isEmpty)
          EmptyState(
            icon: CupertinoIcons.person_2,
            text: 'Клиентов пока нет',
            button: 'Добавить клиента',
            onPressed: _add,
          )
        else ...[
          SearchField(
            'Имя, телефон или госномер',
            (v) => setState(() => _query = v),
          ),
          if (groups.isEmpty)
            const EmptyState(
              icon: CupertinoIcons.search,
              text: 'Ничего не найдено',
            ),
          for (final e in groups.entries)
            LiquidSection(
              header: Text(e.key),
              children: [for (final i in e.value) _tile(i)],
            ),
          Hint('Всего клиентов: ${all.length}'),
        ],
      ],
    );
  }

  Widget _tile(ClientListItem i) {
    final c = i.client;
    return CupertinoListTile(
      leadingSize: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: InitialsAvatar(name: c.name, size: 44),
      title: Text(c.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((c.phone ?? '').isNotEmpty) Text(c.phone!),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: i.vehicles.isEmpty
                ? const Text('Нет автомобилей')
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final v in i.vehicles)
                        PlateBadge(v.plate, small: true),
                    ],
                  ),
          ),
        ],
      ),
      trailing: const CupertinoListTileChevron(),
      onTap: () => openPage(context, ClientDetailsPage(clientId: c.id)),
    );
  }
}
