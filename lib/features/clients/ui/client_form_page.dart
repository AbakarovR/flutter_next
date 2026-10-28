import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/form_row.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/ui_kit.dart';
import '../client_validation.dart';
import '../providers.dart';

/// Одна форма для двух случаев: client == null → новый клиент,
/// иначе изменение существующего.
class ClientFormPage extends ConsumerStatefulWidget {
  const ClientFormPage({super.key, this.client});
  final Client? client;

  @override
  ConsumerState<ClientFormPage> createState() => _ClientFormPageState();
}

class _ClientFormPageState extends ConsumerState<ClientFormPage> {
  late final _name = TextEditingController(text: widget.client?.name);
  late final _phone = TextEditingController(text: widget.client?.phone);
  late final _note = TextEditingController(text: widget.client?.note);
  String? _error;

  bool get _isNew => widget.client == null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nameError = ClientValidation.validateName(_name.text);
    if (nameError != null) {
      setState(() => _error = nameError);
      return;
    }
    final phone = ClientValidation.normalizePhone(_phone.text);
    if (phone == null) {
      setState(() => _error = 'Введите корректный номер телефона РФ');
      return;
    }
    if (_note.text.trim().length > 500) {
      setState(() => _error = 'Заметка не должна быть длиннее 500 символов');
      return;
    }
    final repo = ref.read(clientsRepositoryProvider);
    if (_isNew) {
      await repo.addClient(
        name: ClientValidation.cleanText(_name.text),
        phone: phone,
        note: _note.text,
      );
    } else {
      await repo.updateClient(
        widget.client!.id,
        name: ClientValidation.cleanText(_name.text),
        phone: phone,
        note: _note.text,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.transparent,
      navigationBar: CupertinoNavigationBar(
        leading: NavTextButton(
          'Отмена',
          onTap: () => Navigator.of(context).pop(),
        ),
        middle: Text(_isNew ? 'Новый клиент' : 'Изменить клиента'),
        trailing: NavTextButton('Готово', primary: true, onTap: _save),
      ),
      child: Stack(
        children: [
          SafeArea(
            child: ListView(
              children: [
                LiquidSection(
                  header: const Text('Как зовут клиента'),
                  children: [
                    FormRow(
                      label: 'Имя',
                      controller: _name,
                      placeholder: 'Например: Иван Петров',
                      capitalization: TextCapitalization.words,
                    ),
                  ],
                ),
                LiquidSection(
                  header: const Text('Как связаться'),
                  footer: const Text(
                    'Телефон обязателен. Формат: +7 900 000-00-00.',
                  ),
                  children: [
                    FormRow(
                      label: 'Телефон',
                      controller: _phone,
                      placeholder: '+7 900 000-00-00',
                      keyboardType: TextInputType.phone,
                    ),
                  ],
                ),
                LiquidSection(
                  header: const Text('Заметка'),
                  footer: const Text(
                    'Например: «любит синтетику», «звонить после 18:00».',
                  ),
                  children: [
                    FormRow(
                      label: 'Текст',
                      controller: _note,
                      placeholder: 'Необязательно',
                      maxLines: 3,
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: CupertinoColors.systemRed),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
