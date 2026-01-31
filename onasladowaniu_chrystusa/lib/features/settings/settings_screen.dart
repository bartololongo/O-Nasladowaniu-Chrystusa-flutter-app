import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/services/reading_challenge_service.dart';
import '../../shared/services/preferences_service.dart';
import '../../shared/services/book_repository.dart';
import 'backup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const String _projectUrl =
      'https://bartololongo.pl/blog/o-nasladowaniu-chrystusa/';
  static const String _supportUrl =
      'https://www.buymeacoffee.com/bartololongo';

  Future<void> _resetChallenge(BuildContext context) async {
    final confirmed = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: false,
          builder: (sheetContext) {
            final colorScheme = Theme.of(sheetContext).colorScheme;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.flag,
                          size: 32,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Zresetować wyzwanie?',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Spowoduje to wyczyszczenie postępu „Czytaj całość” '
                      'i rozpoczęcie wyzwania od początku książki.\n\n'
                      'Twoje zakładki, ulubione i dziennik pozostaną bez zmian.',
                      style: TextStyle(fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(false),
                          child: const Text('Anuluj'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(true),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Resetuj'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    final challengeService = ReadingChallengeService();
    final prefs = PreferencesService();
    final bookRepository = BookRepository();

    try {
      final firstChapter = await bookRepository.getFirstChapter();
      final startRef = firstChapter.reference;

      await challengeService.resetChallenge();
      await challengeService.startChallenge();
      await challengeService.updateFurthestChapter(startRef);

      await prefs.saveLastChapterRef(startRef);
      await prefs.setJumpChapterRef(startRef);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Wyzwanie zresetowane. Zaczynasz od początku książki.'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nie udało się zresetować wyzwania: $e'),
        ),
      );
    }
  }

  Future<void> _launchUrl(
    BuildContext context,
    String url, {
    String? failMessage,
  }) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failMessage ?? 'Nie udało się otworzyć linku.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ustawienia'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // TODO: Przywrócić, gdy dodamy osobny ekran ustawień czytnika.
          // const ListTile(
          //   leading: Icon(Icons.text_fields),
          //   title: Text('Czcionka czytania'),
          //   subtitle: Text('Ustawienia rozmiaru i stylu czcionki'),
          // ),
          // const Divider(),

          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('Kopia danych (eksport/import)'),
            subtitle: const Text('Zapisz lub przywróć dane aplikacji'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const BackupScreen(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.flag),
            title: const Text('Wyzwanie: Czytaj całość'),
            subtitle: const Text('Zresetuj postęp i zacznij od początku'),
            onTap: () => _resetChallenge(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('O aplikacji'),
            subtitle: const Text('Informacje, autor, licencja'),
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: false,
                builder: (sheetContext) {
                  final colorScheme = Theme.of(sheetContext).colorScheme;

                  return SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.menu_book,
                                  size: 32,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'O naśladowaniu Chrystusa',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Wersja 1.0.0',
                              style: TextStyle(
                                fontSize: 13,
                                color:
                                    colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Aplikacja do czytania klasycznego dzieła '
                              '„O naśladowaniu Chrystusa” z możliwością '
                              'notowania, zapisywania ulubionych cytatów '
                              'i prowadzenia dziennika duchowego.',
                              style: TextStyle(fontSize: 14, height: 1.4),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Autor: Bartłomiej Kozak vel Bartolo Longo',
                              style: TextStyle(
                                fontSize: 13,
                                color:
                                    colorScheme.onSurface.withOpacity(0.8),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tekst książki: domena publiczna / zgodnie z prawami autorskimi zastosowanego '
                              'tłumaczenia.',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                color:
                                    colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Jeśli aplikacja jest dla Ciebie pomocna i chcesz wesprzeć '
                              'jej rozwój, możesz postawić mi „wirtualną kawę”. 😊',
                              style: TextStyle(fontSize: 13, height: 1.4),
                            ),
                            const SizedBox(height: 16),

                            // Dwa główne przyciski
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _launchUrl(
                                    context,
                                    _projectUrl,
                                    failMessage:
                                        'Nie udało się otworzyć strony projektu.',
                                  ),
                                  icon: const Icon(Icons.info_outline),
                                  label: const Text('O projekcie'),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () => _launchUrl(
                                    context,
                                    _supportUrl,
                                    failMessage:
                                        'Nie udało się otworzyć strony wsparcia.',
                                  ),
                                  icon: const Icon(Icons.coffee),
                                  label: const Text('Wesprzyj projekt'),
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            // Zamknij na samym dole
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                child: const Text('Zamknij'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
