import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/services/formation_challenge_progress_service.dart';
import '../../shared/services/formation_meditation_settings_service.dart';
import '../../shared/services/formation_notification_service.dart';
import '../../shared/widgets/section_header.dart';
import 'backup_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _projectUrl =
      'https://bartololongo.pl/blog/o-nasladowaniu-chrystusa/';
  static const String _supportUrl =
      'https://www.buymeacoffee.com/bartololongo';

  final FormationMeditationSettingsService _meditationSettingsService =
      FormationMeditationSettingsService();
  final FormationNotificationService _formationNotificationService =
      FormationNotificationService.instance;
  final FormationChallengeProgressService _formationProgressService =
      FormationChallengeProgressService();

  late Future<_FormationSettingsState> _formationSettingsFuture;

  @override
  void initState() {
    super.initState();
    _formationSettingsFuture = _loadFormationSettings();
  }

  Future<_FormationSettingsState> _loadFormationSettings() async {
    final durationMinutes =
        await _meditationSettingsService.getDurationMinutes();
    final reminderEnabled =
        await _formationNotificationService.isReminderEnabled();
    final reminderTime = await _formationNotificationService.getReminderTime();

    return _FormationSettingsState(
      durationMinutes: durationMinutes,
      reminderEnabled: reminderEnabled,
      reminderTime: reminderTime,
    );
  }

  Future<void> _refreshFormationSettings() async {
    setState(() {
      _formationSettingsFuture = _loadFormationSettings();
    });
  }

  Future<void> _changeMeditationDuration(int currentMinutes) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: FormationMeditationSettingsService.allowedDurationMinutes
                .map(
                  (minutes) => ListTile(
                    leading: Icon(
                      minutes == currentMinutes
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text('$minutes min'),
                    onTap: () => Navigator.of(sheetContext).pop(minutes),
                  ),
                )
                .toList(),
          ),
        );
      },
    );

    if (selected == null) return;

    await _meditationSettingsService.setDurationMinutes(selected);
    if (!mounted) return;
    await _refreshFormationSettings();
  }

  Future<void> _setFormationReminderEnabled(bool enabled) async {
    await _formationNotificationService.setReminderEnabled(enabled);
    if (!mounted) return;
    await _refreshFormationSettings();
  }

  Future<void> _changeFormationReminderTime(
    FormationReminderTime currentTime,
  ) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: currentTime.toTimeOfDay(),
    );
    if (selected == null) return;

    await _formationNotificationService.setReminderTime(
      hour: selected.hour,
      minute: selected.minute,
    );
    if (!mounted) return;
    await _refreshFormationSettings();
  }

  Future<void> _resetFormationChallenge() async {
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
                          Icons.self_improvement,
                          size: 32,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Resetować Drogę naśladowania?',
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
                      'Usunie to datę rozpoczęcia i postęp Drogi '
                      'naśladowania. Dziennik, zakładki i ulubione '
                      'pozostaną bez zmian.',
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

    await _formationProgressService.resetChallenge();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Droga naśladowania została zresetowana.')),
    );
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

  void _showWhatsNewSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
                        Icons.new_releases_outlined,
                        size: 32,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Co nowego',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Wersja 1.0.0',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.65,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _WhatsNewItem(
                    title: 'Droga naśladowania',
                    description:
                        'Codzienna ścieżka formacyjna z fragmentem dnia, medytacją, postępem i dziennikiem refleksji.',
                  ),
                  const _WhatsNewItem(
                    title: 'Medytacja',
                    description:
                        'Dodano timer medytacji z możliwością ustawienia czasu.',
                  ),
                  const _WhatsNewItem(
                    title: 'Przypomnienia',
                    description:
                        'Możesz ustawić codzienne przypomnienie o Drodze naśladowania.',
                  ),
                  const _WhatsNewItem(
                    title: 'Wyszukiwanie',
                    description:
                        'Dodano globalne wyszukiwanie w książce, zakładkach, ulubionych cytatach i dzienniku.',
                  ),
                  const _WhatsNewItem(
                    title: 'Kopie zapasowe',
                    description:
                        'Kopie zapasowe obejmują teraz także dane Drogi naśladowania.',
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
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
  }

  Widget _buildFormationSettingsSection(BuildContext context) {
    return FutureBuilder<_FormationSettingsState>(
      future: _formationSettingsFuture,
      builder: (context, snapshot) {
        final state = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting &&
            state == null) {
          return const ListTile(
            leading: Icon(Icons.self_improvement),
            title: Text('Droga naśladowania'),
            subtitle: Text('Ładowanie ustawień...'),
          );
        }

        if (snapshot.hasError || state == null) {
          return ListTile(
            leading: const Icon(Icons.self_improvement),
            title: const Text('Droga naśladowania'),
            subtitle: const Text('Nie udało się wczytać ustawień'),
            trailing: IconButton(
              onPressed: _refreshFormationSettings,
              icon: const Icon(Icons.refresh),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Droga naśladowania',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Czas medytacji'),
              subtitle: Text('${state.durationMinutes} min'),
              onTap: () => _changeMeditationDuration(state.durationMinutes),
            ),
            SwitchListTile(
              value: state.reminderEnabled,
              onChanged: _setFormationReminderEnabled,
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Przypomnienie o Drodze'),
              subtitle: Text(state.reminderTime.formatted),
            ),
            ListTile(
              enabled: state.reminderEnabled,
              leading: const Icon(Icons.schedule),
              title: const Text('Godzina przypomnienia'),
              subtitle: Text(state.reminderTime.formatted),
              onTap: state.reminderEnabled
                  ? () => _changeFormationReminderTime(state.reminderTime)
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Resetuj Drogę naśladowania'),
              subtitle: const Text('Usuń postęp i rozpocznij od nowa'),
              onTap: _resetFormationChallenge,
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const SectionHeader(
              title: 'Ustawienia',
              subtitle: 'Dostosuj aplikację do swojego sposobu korzystania.',
              icon: Icons.settings,
              showBackButton: true,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
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
                  _buildFormationSettingsSection(context),
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
                          final colorScheme =
                              Theme.of(sheetContext).colorScheme;

                          return SafeArea(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 24),
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
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
                                        color: colorScheme.onSurface
                                            .withOpacity(0.7),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Przejdź przez „O\u00A0naśladowaniu Chrystusa” dzień po dniu '
                                      'w\u00A0Drodze naśladowania. Otrzymasz fragment dnia, medytację, '
                                      'miejsce na refleksję, postęp i\u00A0przypomnienia. Aplikacja zawiera '
                                      'też czytnik, zakładki, ulubione cytaty oraz wyszukiwanie.',
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Autor: Bartłomiej Kozak vel Bartolo Longo',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colorScheme.onSurface
                                            .withOpacity(0.8),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Tekst książki: domena publiczna / zgodnie z prawami autorskimi zastosowanego '
                                      'tłumaczenia.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        height: 1.3,
                                        color: colorScheme.onSurface
                                            .withOpacity(0.6),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Jeśli aplikacja jest dla Ciebie pomocna i chcesz wesprzeć '
                                      'jej rozwój, możesz postawić mi „wirtualną kawę”. 😊',
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
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
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              _showWhatsNewSheet(context),
                                          icon: const Icon(
                                            Icons.new_releases_outlined,
                                          ),
                                          label: const Text('Co nowego'),
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
            ),
          ],
        ),
      ),
    );
  }
}

class _FormationSettingsState {
  final int durationMinutes;
  final bool reminderEnabled;
  final FormationReminderTime reminderTime;

  const _FormationSettingsState({
    required this.durationMinutes,
    required this.reminderEnabled,
    required this.reminderTime,
  });
}

class _WhatsNewItem extends StatelessWidget {
  final String title;
  final String description;

  const _WhatsNewItem({
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
