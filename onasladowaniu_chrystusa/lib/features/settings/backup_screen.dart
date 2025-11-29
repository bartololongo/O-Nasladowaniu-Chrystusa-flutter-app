import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // <- dla RenderBox
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../shared/services/backup_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _isBusy = false;

  Future<void> _exportBackup() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    final messenger = ScaffoldMessenger.of(context);
    final backupService = BackupService();

    try {
      final backupJson = await backupService.createBackupJson();
      final prettyJson =
          const JsonEncoder.withIndent('  ').convert(backupJson);

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');

      final fileName = 'onasladowaniu_backup_$timestamp.json';
      final file = File(p.join(tempDir.path, fileName));

      await file.writeAsString(prettyJson, encoding: utf8);

      // >>> FIX: obliczamy sharePositionOrigin na podstawie aktualnego kontekstu
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 1, 1);

      await Share.shareXFiles(
        [
          XFile(
            file.path,
            mimeType: 'application/json',
            name: fileName,
          ),
        ],
        subject: 'Kopia danych – O naśladowaniu Chrystusa',
        text:
            'Załączony plik zawiera kopię danych z aplikacji „O naśladowaniu Chrystusa”.',
        sharePositionOrigin: origin,
      );
      // <<< FIX KONIEC

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Kopia danych została utworzona.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Nie udało się wyeksportować danych: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _importBackup() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    final messenger = ScaffoldMessenger.of(context);
    final backupService = BackupService();

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Nie wybrano pliku.')),
        );
        return;
      }

      final filePath = result.files.single.path;
      if (filePath == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Nieprawidłowy plik.')),
        );
        return;
      }

      final file = File(filePath);
      if (!await file.exists()) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Wybrany plik nie istnieje.')),
        );
        return;
      }

      final content = await file.readAsString(encoding: utf8);
      final dynamic decoded = json.decode(content);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Plik backupu ma nieprawidłowy format (spodziewano obiektu JSON).',
        );
      }

      await backupService.restoreFromBackupJson(decoded);

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Dane zostały pomyślnie przywrócone z kopii.'),
        ),
      );
    } on FormatException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Plik nie jest prawidłowym backupem: ${e.message}'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Nie udało się zaimportować danych: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = _isBusy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kopia danych'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Backup danych aplikacji',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tutaj możesz wyeksportować swój dziennik, ulubione, zakładki, '
              'postęp wyzwania „Czytaj całość” oraz ustawienia czytnika do '
              'pliku JSON i później je przywrócić (również na nowszej wersji aplikacji).',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: isDisabled ? null : _exportBackup,
              icon: const Icon(Icons.upload_file),
              label: const Text('Eksportuj dane'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: isDisabled ? null : _importBackup,
              icon: const Icon(Icons.download),
              label: const Text('Importuj dane'),
            ),
            const SizedBox(height: 16),
            if (_isBusy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: CircularProgressIndicator(),
                ),
              ),
            const Spacer(),
            const Text(
              'Uwaga: import danych nadpisze aktualny dziennik, ulubione, '
              'zakładki, postęp wyzwania i preferencje czytnika.',
              style: TextStyle(fontSize: 12, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}
