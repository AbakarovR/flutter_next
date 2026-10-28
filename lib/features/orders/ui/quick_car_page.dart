import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/plate.dart';
import '../../../core/widgets/form_row.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../clients/data/quick_create.dart';
import '../../clients/providers.dart';

/// Результат: кого и какую машину создали.
class NewCar {
  const NewCar(this.clientId, this.vehicleId, this.mileage);
  final String clientId;
  final String vehicleId;
  final int mileage;
}

/// Быстрое создание клиента и машины прямо из «Нового заказа».
/// [initialQuery] — то, что искали: цифры считаем номером, остальное именем.
class QuickCarPage extends ConsumerStatefulWidget {
  const QuickCarPage({super.key, this.initialQuery = ''});
  final String initialQuery;

  @override
  ConsumerState<QuickCarPage> createState() => _QuickCarPageState();
}

class _QuickCarPageState extends ConsumerState<QuickCarPage> {
  bool get _looksLikePlate => RegExp(r'\d').hasMatch(widget.initialQuery);

  late final _name = TextEditingController(
    text: _looksLikePlate ? null : widget.initialQuery.trim(),
  );
  late final _plate = TextEditingController(
    text: _looksLikePlate ? normalizePlate(widget.initialQuery) : null,
  );
  final _phone = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _mileage = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _plate, _phone, _brand, _model, _mileage]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if ([_name, _plate, _brand, _model].any((c) => c.text.trim().isEmpty)) {
      setState(() => _error = 'Заполните имя, госномер, марку и модель');
      return;
    }
    final plate = normalizePlate(_plate.text);

    // Не создаём дубль: машина с таким номером уже может быть в базе.
    final clients = ref.read(clientsListProvider).value ?? [];
    for (final i in clients) {
      if (i.vehicles.any((v) => v.plate == plate)) {
        setState(
          () => _error =
              'Автомобиль $plate уже есть у клиента «${i.client.name}». Выберите его в списке.',
        );
        return;
      }
    }

    final km = int.tryParse(_mileage.text.trim()) ?? 0;
    final ids = await ref
        .read(clientsRepositoryProvider)
        .addClientWithVehicle(
          name: _name.text,
          phone: _phone.text,
          plate: plate,
          brand: _brand.text,
          model: _model.text,
          mileage: km,
        );
    if (mounted) {
      Navigator.pop(context, NewCar(ids.clientId, ids.vehicleId, km));
    }
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: 'Новый клиент и авто',
    onSave: _save,
    error: _error,
    children: [
      LiquidSection(
        header: const Text('Клиент'),
        children: [
          FormRow(
            label: 'Имя',
            controller: _name,
            placeholder: 'Иван Петров',
            capitalization: TextCapitalization.words,
          ),
          FormRow(
            label: 'Телефон',
            controller: _phone,
            placeholder: 'Необязательно',
            keyboardType: TextInputType.phone,
          ),
        ],
      ),
      LiquidSection(
        header: const Text('Госномер'),
        footer: const Text('Можно латиницей, программа исправит сама.'),
        children: [
          FormRow(
            label: 'Номер',
            controller: _plate,
            placeholder: 'А123ВС77',
            capitalization: TextCapitalization.characters,
          ),
          ListenableBuilder(
            listenable: _plate,
            builder: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(child: PlateBadge(normalizePlate(_plate.text))),
            ),
          ),
        ],
      ),
      LiquidSection(
        header: const Text('Автомобиль'),
        footer: const Text('Пробег нужен для напоминаний о замене масла.'),
        children: [
          FormRow(
            label: 'Марка',
            controller: _brand,
            placeholder: 'Toyota',
            capitalization: TextCapitalization.words,
          ),
          FormRow(
            label: 'Модель',
            controller: _model,
            placeholder: 'Camry',
            capitalization: TextCapitalization.words,
          ),
          FormRow(
            label: 'Пробег, км',
            controller: _mileage,
            placeholder: '0',
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    ],
  );
}
