import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/services/formation_challenge_progress_service.dart';
import '../../shared/services/formation_meditation_settings_service.dart';
import '../../shared/services/formation_notification_service.dart';
import '../../shared/services/formation_widget_snapshot_service.dart';
import '../../shared/services/content_update_service.dart';
import '../../shared/navigation/app_page_route.dart';
import '../../shared/widgets/section_header.dart';
import '../audio/services/app_audio_player_service.dart';
import '../audio/ui/offline_audio_screen.dart';
import 'backup_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _projectUrl =
      'https://bartololongo.pl/blog/o-nasladowaniu-chrystusa/';
  static const String _supportUrl = 'https://www.buymeacoffee.com/bartololongo';

  final FormationMeditationSettingsService _meditationSettingsService =
      FormationMeditationSettingsService();
  final FormationNotificationService _formationNotificationService =
      FormationNotificationService.instance;
  final FormationChallengeProgressService _formationProgressService =
      FormationChallengeProgressService();
  final FormationWidgetSnapshotService _formationWidgetSnapshotService =
      FormationWidgetSnapshotService();
  final AppAudioPlayerService _audioPlayerService =
      AppAudioPlayerService.instance;
  final ContentUpdateService _contentUpdateService = ContentUpdateService();

  late Future<_FormationSettingsState> _formationSettingsFuture;
  late Future<_ContentSettingsState> _contentSettingsFuture;
  late Future<bool> _keepScreenOnInPlayerFuture;
  bool _isCheckingContentUpdate = false;
  bool _isRestoringBundledContent = false;

  @override
  void initState() {
    super.initState();
    _formationSettingsFuture = _loadFormationSettings();
    _contentSettingsFuture = _loadContentSettings();
    _keepScreenOnInPlayerFuture = _audioPlayerService.getKeepScreenOnInPlayer();
  }

  Future<_FormationSettingsState> _loadFormationSettings() async {
    final durationMinutes = await _meditationSettingsService
        .getDurationMinutes();
    final reminderEnabled = await _formationNotificationService
        .isReminderEnabled();
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

  Future<_ContentSettingsState> _loadContentSettings() async {
    final localVersion = await _contentUpdateService.getLocalContentVersion();
    final hasLocalOverride = await _contentUpdateService.hasLocalOverride();

    return _ContentSettingsState(
      localVersion: localVersion,
      hasLocalOverride: hasLocalOverride,
    );
  }

  Future<void> _refreshContentSettings() async {
    setState(() {
      _contentSettingsFuture = _loadContentSettings();
    });
  }

  Future<void> _checkContentUpdate() async {
    if (_isCheckingContentUpdate) return;

    setState(() {
      _isCheckingContentUpdate = true;
    });

    String message;
    try {
      final result = await _contentUpdateService.checkAndDownloadLatest();
      message = _contentUpdateMessage(result);
    } catch (_) {
      message = 'Wystąpił nieznany błąd.';
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingContentUpdate = false;
          _contentSettingsFuture = _loadContentSettings();
        });
      }
    }

    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _restoreBundledContent() async {
    if (_isRestoringBundledContent) return;

    final confirmed =
        await showModalBottomSheet<bool>(
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
                          Icons.menu_book_outlined,
                          size: 32,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Przywrócić tekst wbudowany?',
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
                      'Usunie to pobraną wersję tekstu książki. Aplikacja '
                      'wróci do tekstu dołączonego do tej wersji aplikacji.',
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
                          onPressed: () => Navigator.of(sheetContext).pop(true),
                          icon: const Icon(Icons.restore),
                          label: const Text('Przywróć'),
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

    setState(() {
      _isRestoringBundledContent = true;
    });

    try {
      await _contentUpdateService.restoreBundledContent();
      if (!mounted) return;
      setState(() {
        _isRestoringBundledContent = false;
        _contentSettingsFuture = _loadContentSettings();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Przywrócono tekst wbudowany. Zmiany będą widoczne po ponownym '
            'otwarciu czytnika lub ponownym uruchomieniu aplikacji.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isRestoringBundledContent = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie udało się przywrócić tekstu.')),
      );
    }
  }

  String _contentUpdateMessage(ContentUpdateResult result) {
    final suffix = result.status == ContentUpdateStatus.updated
        ? ' Zmiany będą widoczne po ponownym otwarciu czytnika lub ponownym uruchomieniu aplikacji.'
        : '';

    final message = switch (result.status) {
      ContentUpdateStatus.updated => 'Pobrano najnowszą wersję tekstu.',
      ContentUpdateStatus.upToDate => 'Masz już najnowszą wersję tekstu.',
      ContentUpdateStatus.skippedIncompatibleAppVersion =>
        'Ta wersja tekstu wymaga nowszej wersji aplikacji.',
      ContentUpdateStatus.manifestUnavailable =>
        'Nie udało się sprawdzić aktualizacji tekstu.',
      ContentUpdateStatus.downloadFailed => 'Nie udało się pobrać tekstu.',
      ContentUpdateStatus.invalidHash =>
        'Pobrany plik nie przeszedł weryfikacji.',
      ContentUpdateStatus.invalidJson =>
        'Pobrany tekst ma nieprawidłowy format.',
      ContentUpdateStatus.unknownError => 'Wystąpił nieznany błąd.',
    };

    return '$message$suffix';
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
    final confirmed =
        await showModalBottomSheet<bool>(
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
                          onPressed: () => Navigator.of(sheetContext).pop(true),
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
    await _formationWidgetSnapshotService.refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Droga naśladowania została zresetowana.')),
    );
  }

  Future<void> _clearAudioPlaybackProgress() async {
    final confirmed =
        await showModalBottomSheet<bool>(
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
                          Icons.headphones_rounded,
                          size: 32,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Wyczyścić postęp słuchania?',
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
                      'Usunie to zapamiętane miejsca odtwarzania rozdziałów '
                      'audio. Nagrania będą uruchamiać się od początku.',
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
                          onPressed: () => Navigator.of(sheetContext).pop(true),
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('Wyczyść'),
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

    await _audioPlayerService.clearSavedPlaybackProgress();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Postęp słuchania został wyczyszczony.')),
    );
  }

  Future<void> _setKeepScreenOnInPlayer(bool enabled) async {
    await _audioPlayerService.setKeepScreenOnInPlayer(enabled);
    if (!mounted) return;

    setState(() {
      _keepScreenOnInPlayerFuture = Future.value(enabled);
    });
  }

  Future<void> _launchUrl(
    BuildContext context,
    String url, {
    String? failMessage,
  }) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failMessage ?? 'Nie udało się otworzyć linku.')),
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
                              'Wersja 2.0.0',
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
                  const Text(
                    'Z przyjemnością oddaję w Państwa ręce wiele nowości',
                    style: TextStyle(fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  const _WhatsNewItem(
                    title: 'Najważniejsze zmiany',
                    description:
                        '• Nowy dolny pasek: Start, Droga, Książka i Dziennik\n'
                        '• Odtwarzacz audio ze słuchaniem w tle i obsługą ekranu blokady\n'
                        '• Audiobook czytany przez Marcina Nowakowskiego\n'
                        '• Pobieranie nagrań do słuchania offline oraz zarządzanie nimi\n'
                        '• Aktualizacje tekstu książki bez konieczności instalowania nowej wersji aplikacji\n'
                        '• Przydatne skróty na ekranie głównym\n'
                        '• Liczne usprawnienia wyglądu i działania aplikacji',
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
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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

  Widget _buildContentSettingsSection(BuildContext context) {
    return FutureBuilder<_ContentSettingsState>(
      future: _contentSettingsFuture,
      builder: (context, snapshot) {
        final state = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting &&
            state == null) {
          return const ListTile(
            leading: Icon(Icons.menu_book_outlined),
            title: Text('Tekst książki'),
            subtitle: Text('Ładowanie informacji...'),
          );
        }

        if (snapshot.hasError || state == null) {
          return ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Tekst książki'),
            subtitle: const Text('Nie udało się wczytać informacji'),
            trailing: IconButton(
              onPressed: _refreshContentSettings,
              icon: const Icon(Icons.refresh),
            ),
          );
        }

        final versionLabel = state.localVersion == null
            ? 'Wersja wbudowana'
            : 'Pobrana wersja ${state.localVersion}';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Tekst książki',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Wersja tekstu'),
              subtitle: Text(versionLabel),
            ),
            ListTile(
              enabled: !_isCheckingContentUpdate,
              leading: const Icon(Icons.system_update_alt),
              title: const Text('Sprawdź aktualizacje tekstu'),
              subtitle: const Text(
                'Sprawdź i pobierz poprawki tekstu bez aktualizacji aplikacji.',
              ),
              trailing: _isCheckingContentUpdate
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: _isCheckingContentUpdate ? null : _checkContentUpdate,
            ),
            if (state.hasLocalOverride)
              ListTile(
                enabled: !_isRestoringBundledContent,
                leading: const Icon(Icons.restore),
                title: const Text('Przywróć tekst wbudowany'),
                subtitle: const Text('Usuń pobraną wersję tekstu książki.'),
                trailing: _isRestoringBundledContent
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _isRestoringBundledContent
                    ? null
                    : _restoreBundledContent,
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
                        AppPageRoute.fade(
                          settings: const RouteSettings(name: '/backup'),
                          builder: (_) => const BackupScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.headphones_rounded),
                    title: const Text('Wyczyść postęp słuchania'),
                    subtitle: const Text(
                      'Rozdziały audio będą odtwarzane od początku.',
                    ),
                    onTap: _clearAudioPlaybackProgress,
                  ),
                  ListTile(
                    leading: const Icon(Icons.download_done_rounded),
                    title: const Text('Nagrania offline'),
                    subtitle: const Text(
                      'Zarządzaj pobranymi rozdziałami audio.',
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        AppPageRoute.fade(
                          settings: const RouteSettings(name: '/offline-audio'),
                          builder: (_) => const OfflineAudioScreen(),
                        ),
                      );
                    },
                  ),
                  FutureBuilder<bool>(
                    future: _keepScreenOnInPlayerFuture,
                    builder: (context, snapshot) {
                      final enabled = snapshot.data ?? false;

                      return SwitchListTile(
                        value: enabled,
                        onChanged: _setKeepScreenOnInPlayer,
                        secondary: const Icon(Icons.screen_lock_portrait),
                        title: const Text('Ekran stale włączony w odtwarzaczu'),
                        subtitle: const Text(
                          'Zapobiega wygaszaniu ekranu podczas korzystania '
                          'z pełnego odtwarzacza audio.',
                        ),
                      );
                    },
                  ),
                  const Divider(),
                  _buildContentSettingsSection(context),
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
                          final colorScheme = Theme.of(
                            sheetContext,
                          ).colorScheme;

                          return SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                24,
                              ),
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
                                      'Wersja 2.0',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Przejdź przez „O\u00A0naśladowaniu Chrystusa” dzień po dniu '
                                      'w\u00A0Drodze naśladowania. Otrzymasz fragment dnia, medytację, '
                                      'miejsce na refleksję, postęp i\u00A0przypomnienia. Aplikacja zawiera '
                                      'też audiobook, czytnik, zakładki, ulubione cytaty oraz wyszukiwanie.',
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
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.8,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Nagrania audio czyta: Marcin Nowakowski',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.8,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Tekst książki: domena publiczna / zgodnie z prawami autorskimi zastosowanego '
                                      'tłumaczenia.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        height: 1.3,
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.6,
                                        ),
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

class _ContentSettingsState {
  final String? localVersion;
  final bool hasLocalOverride;

  const _ContentSettingsState({
    required this.localVersion,
    required this.hasLocalOverride,
  });
}

class _WhatsNewItem extends StatelessWidget {
  final String title;
  final String description;

  const _WhatsNewItem({required this.title, required this.description});

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
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
