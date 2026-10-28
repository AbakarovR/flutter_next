import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/plate.dart';
import '../../../core/widgets/form_row.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../core/widgets/ui_kit.dart';
import '../client_validation.dart';
import '../providers.dart';

/// vehicle == null: новое авто клиента [clientId], иначе изменение.
class VehicleFormPage extends ConsumerStatefulWidget {
  const VehicleFormPage({super.key, required this.clientId, this.vehicle});
  final String clientId;
  final Vehicle? vehicle;

  @override
  ConsumerState<VehicleFormPage> createState() => _VehicleFormPageState();
}

class _VehicleFormPageState extends ConsumerState<VehicleFormPage> {
  Vehicle? get _v => widget.vehicle;
  late final _plate = TextEditingController(text: _v?.plate);
  late final _brand = TextEditingController(text: _v?.brand);
  late final _model = TextEditingController(text: _v?.model);
  late final _year = TextEditingController(text: _v?.year?.toString());
  late final _vin = TextEditingController(text: _v?.vin);
  late final _mileage = TextEditingController(text: _v?.mileage.toString());
  String? _error;

  @override
  void dispose() {
    for (final c in [_plate, _brand, _model, _year, _vin, _mileage]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final plate = normalizePlate(_plate.text);
    if (!isValidPlate(plate)) {
      setState(() => _error = 'Введите госномер в формате А123ВС77');
      return;
    }
    final brandError = ClientValidation.validateVehicleName(
      _brand.text,
      'марку автомобиля',
    );
    if (brandError != null) {
      setState(() => _error = brandError);
      return;
    }
    final modelError = ClientValidation.validateVehicleName(
      _model.text,
      'модель автомобиля',
    );
    if (modelError != null) {
      setState(() => _error = modelError);
      return;
    }
    final mileageError = ClientValidation.validateMileage(_mileage.text);
    if (mileageError != null) {
      setState(() => _error = mileageError);
      return;
    }
    final yearError = ClientValidation.validateYear(_year.text);
    if (yearError != null) {
      setState(() => _error = yearError);
      return;
    }
    final vinError = ClientValidation.validateVin(_vin.text);
    if (vinError != null) {
      setState(() => _error = vinError);
      return;
    }
    final repo = ref.read(clientsRepositoryProvider);
    final plateExists = await repo.vehiclePlateExists(
      plate,
      exceptVehicleId: _v?.id,
    );
    if (!mounted) return;
    if (plateExists) {
      setState(() => _error = 'Автомобиль с таким госномером уже добавлен');
      return;
    }
    final yearText = _year.text.trim();
    final year = yearText.isEmpty ? null : int.parse(yearText);
    final km = int.parse(_mileage.text.trim());
    final v = _v;
    if (v == null) {
      await repo.addVehicle(
        clientId: widget.clientId,
        plate: plate,
        brand: ClientValidation.cleanText(_brand.text),
        model: ClientValidation.cleanText(_model.text),
        year: year,
        vin: _vin.text,
        mileage: km,
      );
    } else {
      await repo.updateVehicle(
        v.id,
        plate: plate,
        brand: ClientValidation.cleanText(_brand.text),
        model: ClientValidation.cleanText(_model.text),
        year: year,
        vin: _vin.text,
        mileage: km,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: _v == null ? 'Новое авто' : 'Изменить авто',
    onSave: _save,
    error: _error,
    children: [
      LiquidSection(
        header: const Text('Госномер'),
        footer: const Text(
          'Обязательно. Формат российского номера: А123ВС77 или А123ВС777. Латинские похожие буквы исправятся автоматически.',
        ),
        children: [
          FormRow(
            label: 'Номер',
            controller: _plate,
            placeholder: 'А123ВС77',
            capitalization: TextCapitalization.characters,
          ),
          // Превью номера обновляется с каждой буквой.
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
            label: 'Год выпуска',
            controller: _year,
            placeholder: 'Необязательно',
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      LiquidSection(
        header: const Text('Пробег и VIN'),
        footer: const Text(
          'Пробег обязателен и вводится целым числом. VIN необязателен, но если указан, должен содержать 17 символов.',
        ),
        children: [
          FormRow(
            label: 'Пробег, км',
            controller: _mileage,
            placeholder: 'Обязательно',
            keyboardType: TextInputType.number,
          ),
          FormRow(
            label: 'VIN',
            controller: _vin,
            placeholder: 'Необязательно',
            capitalization: TextCapitalization.characters,
          ),
        ],
      ),
    ],
  );
}
