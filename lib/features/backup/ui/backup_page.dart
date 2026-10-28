import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/widgets/ui_kit.dart';
import '../data/backup_service.dart';
import '../providers.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  Future<void> _export(BuildContext actionContext) async {
    final box = actionContext.findRenderObject() as RenderBox?;
    final sharePositionOrigin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      final json = await ref.read(backupServiceProvider).createBackup();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final name = 'oilpro-backup-$stamp.json';
      final file = XFile.fromData(
        utf8.encode(json),
        mimeType: 'application/json',
        name: name,
      );

      final mobile =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;
      if (kIsWeb || mobile) {
        await SharePlus.instance.share(
          ShareParams(
            files: [file],
            title: 'Резервная копия OilPro',
            sharePositionOrigin: sharePositionOrigin,
          ),
        );
        _showMessage(
          'Резервная копия подготовлена для сохранения или отправки.',
        );
      } else {
        final location = await getSaveLocation(
          suggestedName: name,
          confirmButtonText: 'Сохранить',
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'Резервная копия OilPro',
              extensions: ['json'],
              mimeTypes: ['application/json'],
              uniformTypeIdentifiers: ['public.json'],
            ),
          ],
        );
        if (location == null) return;
        await file.saveTo(location.path);
        _showMessage('Резервная копия сохранена.');
      }
    } catch (error) {
      _showMessage('Не удалось создать копию: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final XFile? file;
    try {
      file = await openFile();
    } catch (error) {
      _showMessage('Не удалось открыть выбор файла: $error', error: true);
      return;
    }
    if (file == null || !mounted) return;

    final String contents;
    final BackupSummary summary;
    try {
      contents = await file.readAsString();
      summary = ref.read(backupServiceProvider).inspectBackup(contents);
    } on BackupFormatException catch (error) {
      _showMessage(error.message, error: true);
      return;
    } catch (error) {
      _showMessage('Не удалось прочитать файл: $error', error: true);
      return;
    }
    if (!mounted) return;

    final confirmed = await confirm(
      context,
      'Заменить текущие данные?',
      'Из файла будут восстановлены клиенты: ${summary.clients}, '
          'автомобили: ${summary.vehicles}, товары: ${summary.products}, '
          'заказы: ${summary.orders}. Текущая база будет заменена.',
      action: 'Восстановить',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(backupServiceProvider).restoreBackup(contents);
      _showMessage('Данные восстановлены из резервной копии.');
    } on BackupFormatException catch (error) {
      _showMessage(error.message, error: true);
    } catch (error) {
      _showMessage('Не удалось восстановить данные: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Резервная копия',
    children: [
      const Hint(
        'Копия содержит данные клиентов, автомобилей, заказов, склада и '
        'отчётов. Храните файл в надёжном месте.',
      ),
      LiquidSection(
        header: const Text('Данные приложения'),
        children: [
          CupertinoListTile(
            leading: const Icon(CupertinoIcons.square_arrow_up),
            title: const Text('Создать резервную копию'),
            subtitle: const Text('Сохранить файл или отправить его себе'),
            trailing: const CupertinoListTileChevron(),
            onTap: _busy ? null : () => _export(context),
          ),
          CupertinoListTile(
            leading: const Icon(CupertinoIcons.square_arrow_down),
            title: const Text('Восстановить из файла'),
            subtitle: const Text('Заменит данные в этом приложении'),
            trailing: const CupertinoListTileChevron(),
            onTap: _busy ? null : _import,
          ),
        ],
      ),
      if (_busy) const Loading(),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _message!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _messageIsError
                  ? CupertinoColors.systemRed
                  : CupertinoColors.systemGrey,
            ),
          ),
        ),
    ],
  );
}
