import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/models/formation_challenge_models.dart';
import '../../shared/services/formation_challenge_progress_service.dart';
import '../../shared/services/formation_challenge_service.dart';
import '../../shared/services/journal_service.dart';
import '../../shared/services/preferences_service.dart';
import '../../shared/services/formation_widget_snapshot_service.dart';
import '../../shared/navigation/app_page_route.dart';
import '../../shared/navigation/main_tabs.dart';
import '../audio/data/audio_catalog.dart';
import '../audio/data/audio_track.dart';
import '../audio/ui/audio_player_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import 'formation_journal_helpers.dart';
import 'formation_meditation_screen.dart';

class FormationChallengeScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;

  const FormationChallengeScreen({super.key, this.onNavigateToTab});

  @override
  State<FormationChallengeScreen> createState() =>
      _FormationChallengeScreenState();
}

class _FormationChallengeScreenState extends State<FormationChallengeScreen> {
  final FormationChallengeService _challengeService =
      FormationChallengeService();
  final FormationChallengeProgressService _progressService =
      FormationChallengeProgressService();
  final JournalService _journalService = JournalService();
  final PreferencesService _preferencesService = PreferencesService();
  final FormationWidgetSnapshotService _widgetSnapshotService =
      FormationWidgetSnapshotService();
  late final TextEditingController _reflectionEditorController;

  late Future<_FormationChallengeViewState> _stateFuture;
  _FormationChallengeTab _selectedTab = _FormationChallengeTab.today;
  FormationChallengeDay? _activeDayOverride;

  @override
  void initState() {
    super.initState();
    _reflectionEditorController = TextEditingController();
    _stateFuture = _loadState();
    unawaited(_widgetSnapshotService.refresh());
  }

  @override
  void dispose() {
    _reflectionEditorController.dispose();
    super.dispose();
  }

  Future<_FormationChallengeViewState> _loadState() async {
    final isStarted = await _progressService.isStarted();
    if (!isStarted) {
      return _FormationChallengeViewState(isStarted: false);
    }

    final startDate = await _progressService.getStartDate();
    if (startDate == null) {
      return _FormationChallengeViewState(isStarted: false);
    }

    final day = await _challengeService.getDayForDate(
      startDate,
      DateTime.now(),
    );
    final totalDays = await _challengeService.getTotalDays();
    final days = await _challengeService.getDays();
    final lastCompletedDay = await _progressService.getLastCompletedDay();
    final completedDays = await _progressService.getCompletedDays();
    final isTodayCompleted = completedDays.contains(day.dayNumber);
    final journalEntries = await _journalService.getEntries();
    final reflectionsByChapterRef = _buildFormationReflectionsByChapterRef(
      days,
      journalEntries,
    );

    return _FormationChallengeViewState(
      isStarted: true,
      day: day,
      totalDays: totalDays,
      startDate: startDate,
      days: days,
      completedDays: completedDays,
      reflectionsByChapterRef: reflectionsByChapterRef,
      lastCompletedDay: lastCompletedDay,
      isTodayCompleted: isTodayCompleted,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _stateFuture = _loadState();
    });
  }

  Future<void> _startChallenge() async {
    await _progressService.startChallenge();
    await _widgetSnapshotService.refresh();
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _markDayCompleted(FormationChallengeDay day) async {
    await _progressService.markDayCompleted(day.dayNumber);
    await _widgetSnapshotService.refresh();
    if (!mounted) return;

    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dzień oznaczony jako ukończony.')),
    );
  }

  Future<void> _addReflectionToJournal(
    FormationChallengeDay day,
    int totalDays,
  ) async {
    final saved = await openFormationReflectionComposer(
      context: context,
      day: day,
      totalDays: totalDays,
    );

    if (!mounted || !saved) return;
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Refleksja dodana do dziennika.')),
    );
  }

  Future<void> _editFormationReflection(_FormationReflection reflection) async {
    const marker = 'Moja refleksja:';
    final entry = reflection.entry;
    final markerIndex = entry.content.indexOf(marker);
    if (markerIndex == -1) return;

    final contentPrefix = entry.content
        .substring(0, markerIndex + marker.length)
        .trim();
    _reflectionEditorController
      ..text = reflection.text
      ..selection = TextSelection.collapsed(offset: reflection.text.length);

    final updatedText = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edytuj refleksję'),
          content: TextField(
            controller: _reflectionEditorController,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'Wpisz swoją refleksję...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Anuluj'),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _reflectionEditorController,
              builder: (context, value, child) {
                final canSave = value.text.trim().isNotEmpty;

                return ElevatedButton(
                  onPressed: canSave
                      ? () => Navigator.of(
                          dialogContext,
                        ).pop(_reflectionEditorController.text.trim())
                      : null,
                  child: child,
                );
              },
              child: const Text('Zapisz'),
            ),
          ],
        );
      },
    );

    if (!mounted || updatedText == null) return;

    final updatedContent = '$contentPrefix\n$updatedText';
    if (updatedContent == entry.content) return;

    await _journalService.updateEntryContent(
      id: entry.id,
      content: updatedContent,
    );
    if (!mounted) return;

    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Refleksja zaktualizowana.')));
  }

  Future<void> _openMeditation(FormationChallengeDay day, int totalDays) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/formation-meditation'),
        builder: (_) =>
            FormationMeditationScreen(day: day, totalDays: totalDays),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openDayInReader(FormationChallengeDay day) async {
    await _preferencesService.setJumpChapterRef(day.chapterReference);
    await _preferencesService.clearJumpParagraphNumber();

    if (!mounted) return;
    widget.onNavigateToTab?.call(MainTabs.read);

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openAudioPlayer(AudioTrack track) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/audio-player'),
        builder: (_) => AudioPlayerScreen(track: track),
      ),
    );
  }

  void _openSearch() {
    Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/search'),
        builder: (_) => SearchScreen(onNavigateToTab: widget.onNavigateToTab),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/settings'),
        builder: (_) => const SettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Droga naśladowania'),
        actions: [
          IconButton(
            onPressed: _openSearch,
            icon: const Icon(Icons.search),
            tooltip: 'Szukaj',
          ),
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
            tooltip: 'Ustawienia',
          ),
        ],
      ),
      body: FutureBuilder<_FormationChallengeViewState>(
        future: _stateFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _buildErrorBody(context, snapshot.error);
          }

          final state = snapshot.data;
          if (state == null || !state.isStarted) {
            return _buildNotStartedBody(context);
          }

          return _buildStartedBody(context, state);
        },
      ),
    );
  }

  Widget _buildNotStartedBody(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 56,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 20),
            const Text(
              'Codzienna medytacja\nz «O naśladowaniu Chrystusa»',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              'Każdy dzień prowadzi przez jeden rozdział książki.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _startChallenge,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Rozpocznij Drogę'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartedBody(
    BuildContext context,
    _FormationChallengeViewState state,
  ) {
    final day = state.day;
    final totalDays = state.totalDays;

    if (day == null || totalDays == null) {
      return _buildErrorBody(
        context,
        'Nie udało się wczytać dzisiejszego dnia.',
      );
    }

    final activeDay = _activeDayOverride ?? day;
    final isActiveDayCompleted = state.completedDays.contains(
      activeDay.dayNumber,
    );
    final isMakeUpDay = activeDay.dayNumber < day.dayNumber;
    final activeReflection =
        state.reflectionsByChapterRef[activeDay.chapterReference];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Dziś'),
                selected: _selectedTab == _FormationChallengeTab.today,
                onSelected: (selected) {
                  if (!selected) return;
                  setState(() {
                    _selectedTab = _FormationChallengeTab.today;
                    _activeDayOverride = null;
                  });
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Dni'),
                selected: _selectedTab == _FormationChallengeTab.days,
                onSelected: (selected) {
                  if (!selected) return;
                  setState(() {
                    _selectedTab = _FormationChallengeTab.days;
                  });
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Statystyki'),
                selected: _selectedTab == _FormationChallengeTab.stats,
                onSelected: (selected) {
                  if (!selected) return;
                  setState(() {
                    _selectedTab = _FormationChallengeTab.stats;
                  });
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_selectedTab) {
            _FormationChallengeTab.today => _buildTodayView(
              context,
              activeDay,
              totalDays,
              reflection: activeReflection,
              isMakeUpDay: isMakeUpDay,
              isActiveDayCompleted: isActiveDayCompleted,
            ),
            _FormationChallengeTab.days => _buildDaysView(context, state),
            _FormationChallengeTab.stats => _buildStatsView(context, state),
          },
        ),
        if (_selectedTab == _FormationChallengeTab.today)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: activeReflection == null
                        ? () => _addReflectionToJournal(activeDay, totalDays)
                        : () => _editFormationReflection(activeReflection),
                    icon: const Icon(Icons.edit_note),
                    label: Text(
                      activeReflection == null
                          ? 'Dodaj refleksję do dziennika'
                          : 'Edytuj refleksję',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _showDayActionsSheet(
                      activeDay,
                      totalDays,
                      isActiveDayCompleted: isActiveDayCompleted,
                    ),
                    icon: const Icon(Icons.more_horiz),
                    label: const Text('Więcej opcji'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTodayView(
    BuildContext context,
    FormationChallengeDay day,
    int totalDays, {
    required _FormationReflection? reflection,
    required bool isMakeUpDay,
    required bool isActiveDayCompleted,
  }) {
    final audioTrack = _audioTrackForDay(day);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(
          'Dzień ${day.dayNumber} z $totalDays',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          _formatChapterReference(day.chapterReference),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Text(
          day.chapterTitle,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        if (isMakeUpDay) ...[
          const SizedBox(height: 10),
          Text(
            isActiveDayCompleted ? 'Dzień nadrobiony' : 'Dzień do nadrobienia',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (isActiveDayCompleted) ...[
          const SizedBox(height: 10),
          Text(
            'Ten dzień jest ukończony.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (audioTrack != null) ...[
          _buildAudioSection(context, audioTrack),
          const SizedBox(height: 22),
        ],
        Text(day.text, style: const TextStyle(fontSize: 17, height: 1.55)),
        if (reflection != null) ...[
          const SizedBox(height: 24),
          Text(
            'Moja refleksja',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(reflection.text, style: const TextStyle(height: 1.45)),
        ],
      ],
    );
  }

  Widget _buildAudioSection(BuildContext context, AudioTrack track) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primary.withValues(alpha: 0.14),
            ),
            child: Icon(Icons.headphones_rounded, color: colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nagranie lektorskie',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Księga ${track.bookNumber} · Rozdział ${track.chapterNumber}',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_openAudioPlayer(track)),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Posłuchaj rozdziału'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDayActionsSheet(
    FormationChallengeDay day,
    int totalDays, {
    required bool isActiveDayCompleted,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
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
                      Icons.more_horiz,
                      color: Theme.of(sheetContext).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Akcje dnia',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.menu_book),
                  title: const Text('Zobacz w książce'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _openDayInReader(day);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.self_improvement),
                  title: const Text('Rozpocznij medytację'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _openMeditation(day, totalDays);
                  },
                ),
                ListTile(
                  enabled: !isActiveDayCompleted,
                  leading: Icon(
                    isActiveDayCompleted
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                  ),
                  title: Text(
                    isActiveDayCompleted
                        ? 'Ten dzień jest ukończony'
                        : 'Oznacz dzień jako ukończony',
                  ),
                  onTap: isActiveDayCompleted
                      ? null
                      : () async {
                          Navigator.of(sheetContext).pop();
                          await _markDayCompleted(day);
                        },
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
        );
      },
    );
  }

  Widget _buildStatsView(
    BuildContext context,
    _FormationChallengeViewState state,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _buildProgressSection(
          context,
          state,
          activeDayStatusText: _activeDayStatusText(
            isMakeUpDay: false,
            isActiveDayCompleted: state.isTodayCompleted,
          ),
        ),
      ],
    );
  }

  Widget _buildDaysView(
    BuildContext context,
    _FormationChallengeViewState state,
  ) {
    final days = state.days;
    final today = state.day;
    final totalDays = state.totalDays ?? days.length;

    if (today == null || days.isEmpty) {
      return const Center(child: Text('Nie udało się wczytać listy dni.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: days.length,
      separatorBuilder: (context, index) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final item = days[index];
        final isFuture = item.dayNumber > today.dayNumber;
        final isPast = item.dayNumber < today.dayNumber;
        final isCompleted = state.completedDays.contains(item.dayNumber);
        final isToday = item.dayNumber == today.dayNumber;
        final isUnlocked = !isFuture;
        final status = _dayStatusLabel(
          isToday: isToday,
          isPast: isPast,
          isCompleted: isCompleted,
        );
        final icon = isCompleted
            ? Icons.check_circle
            : isToday
            ? Icons.radio_button_checked
            : isFuture
            ? Icons.lock_outline
            : Icons.history;
        final colorScheme = Theme.of(context).colorScheme;
        final iconColor = isUnlocked
            ? colorScheme.primary
            : colorScheme.onSurface.withValues(alpha: 0.45);

        return ListTile(
          leading: Icon(icon, color: iconColor),
          title: Text('Dzień ${item.dayNumber}'),
          subtitle: Text(
            '${item.chapterTitle}\n${_formatChapterReference(item.chapterReference)}',
          ),
          isThreeLine: true,
          trailing: Text(
            status,
            style: TextStyle(
              color: isUnlocked
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          onTap: () => _openDayPreview(
            item,
            totalDays,
            isUnlocked: isUnlocked,
            isCompleted: isCompleted,
            isToday: isToday,
            isCurrentDayCompleted: state.isTodayCompleted,
          ),
        );
      },
    );
  }

  String _activeDayStatusText({
    required bool isMakeUpDay,
    required bool isActiveDayCompleted,
  }) {
    if (isMakeUpDay && isActiveDayCompleted) {
      return 'Ten dzień jest ukończony.';
    }
    if (isMakeUpDay) {
      return 'Ten dzień jest do nadrobienia.';
    }
    if (isActiveDayCompleted) {
      return 'Dzisiejszy dzień jest ukończony.';
    }
    return 'Dzisiejszy dzień nie jest jeszcze ukończony.';
  }

  String _dayStatusLabel({
    required bool isToday,
    required bool isPast,
    required bool isCompleted,
  }) {
    if (isToday && isCompleted) return 'Dziś · Ukończony';
    if (isToday) return 'Dziś';
    if (isPast && isCompleted) return 'Ukończony';
    if (isPast) return 'Do nadrobienia';
    return 'Przed Tobą';
  }

  String _formatChapterReference(String reference) {
    final parts = reference.split('-');
    if (parts.length != 2) return reference;

    final bookCode = parts[0];
    final chapterNumber = int.tryParse(parts[1]);
    if (bookCode.isEmpty || chapterNumber == null) return reference;

    return 'Księga $bookCode, rozdział $chapterNumber';
  }

  AudioTrack? _audioTrackForDay(FormationChallengeDay day) {
    return AudioCatalog.trackForChapter(
      chapterReference: day.chapterReference,
      title: day.chapterTitle,
      subtitle: day.bookTitle,
    );
  }

  Future<void> _openDayPreview(
    FormationChallengeDay day,
    int totalDays, {
    required bool isUnlocked,
    required bool isCompleted,
    required bool isToday,
    required bool isCurrentDayCompleted,
  }) async {
    if (!isUnlocked) {
      final message = isCurrentDayCompleted
          ? 'Ten dzień jest jeszcze przed Tobą. Wróć jutro, aby kontynuować Drogę.'
          : 'Ten dzień jest jeszcze przed Tobą. Ukończ dzisiejszy dzień, aby kontynuować Drogę.';

      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
      return;
    }

    if (!isCompleted || isToday) {
      setState(() {
        _activeDayOverride = isToday ? null : day;
        _selectedTab = _FormationChallengeTab.today;
      });
      return;
    }

    final reflection = await _findFormationReflection(day);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Dzień ${day.dayNumber} z $totalDays',
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatChapterReference(day.chapterReference),
                    style: Theme.of(sheetContext).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    day.chapterTitle,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    day.text,
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Moja refleksja',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    reflection ?? 'Brak zapisanej refleksji dla tego dnia.',
                    style: TextStyle(
                      height: 1.45,
                      color: reflection == null
                          ? colorScheme.onSurface.withValues(alpha: 0.7)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Zamknij'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          await _openDayInReader(day);
                        },
                        icon: const Icon(Icons.menu_book),
                        label: const Text('Zobacz w książce'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<String?> _findFormationReflection(FormationChallengeDay day) async {
    final entries = await _journalService.getEntries();
    return _findLatestFormationReflection(day, entries)?.text;
  }

  Map<String, _FormationReflection> _buildFormationReflectionsByChapterRef(
    List<FormationChallengeDay> days,
    List<JournalEntry> entries,
  ) {
    final reflections = <String, _FormationReflection>{};

    for (final day in days) {
      final reflection = _findLatestFormationReflection(day, entries);
      if (reflection != null) {
        reflections[day.chapterReference] = reflection;
      }
    }

    return reflections;
  }

  _FormationReflection? _findLatestFormationReflection(
    FormationChallengeDay day,
    List<JournalEntry> entries,
  ) {
    final matchingEntries =
        entries
            .where(
              (entry) =>
                  entry.quoteRef == day.chapterReference &&
                  entry.content.contains('Droga naśladowania'),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    for (final entry in matchingEntries) {
      final reflection = _extractReflection(entry.content);
      if (reflection != null && reflection.isNotEmpty) {
        return _FormationReflection(entry: entry, text: reflection);
      }
    }

    return null;
  }

  String? _extractReflection(String content) {
    const marker = 'Moja refleksja:';
    final markerIndex = content.indexOf(marker);
    if (markerIndex == -1) return content.trim();

    final reflection = content.substring(markerIndex + marker.length).trim();
    return reflection.isEmpty ? null : reflection;
  }

  Widget _buildProgressSection(
    BuildContext context,
    _FormationChallengeViewState state, {
    required String activeDayStatusText,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalDays = state.totalDays ?? 0;
    final currentDayNumber = state.day?.dayNumber ?? 0;
    final completedDays = state.completedDays
        .where((dayNumber) => dayNumber > 0 && dayNumber <= totalDays)
        .length;
    final catchUpDays = state.days
        .where(
          (day) =>
              day.dayNumber < currentDayNumber &&
              !state.completedDays.contains(day.dayNumber),
        )
        .length;
    final progress = totalDays == 0 ? 0.0 : completedDays / totalDays;
    final progressPercent = (progress * 100).round();
    final startDate = state.startDate;
    final plannedEndDate = startDate == null || totalDays == 0
        ? null
        : startDate.add(Duration(days: totalDays - 1));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Podsumowanie Drogi',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 12),
          _buildSummaryRow(
            context,
            'Ukończono',
            '$completedDays z $totalDays dni',
          ),
          const SizedBox(height: 6),
          _buildSummaryRow(context, 'Do nadrobienia', '$catchUpDays'),
          const SizedBox(height: 6),
          _buildSummaryRow(context, 'Aktualny dzień', '$currentDayNumber'),
          const SizedBox(height: 6),
          _buildSummaryRow(context, 'Postęp', '$progressPercent%'),
          const SizedBox(height: 6),
          _buildSummaryRow(
            context,
            'Rozpoczęto',
            startDate == null ? '—' : _formatDate(startDate),
          ),
          const SizedBox(height: 6),
          _buildSummaryRow(
            context,
            'Planowane zakończenie',
            plannedEndDate == null ? '—' : _formatDate(plannedEndDate),
          ),
          const SizedBox(height: 12),
          Text(
            activeDayStatusText,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Widget _buildSummaryRow(BuildContext context, String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildErrorBody(BuildContext context, Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Nie udało się wczytać Drogi naśladowania.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text('$error', textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Spróbuj ponownie'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormationChallengeViewState {
  final bool isStarted;
  final FormationChallengeDay? day;
  final int? totalDays;
  final DateTime? startDate;
  final List<FormationChallengeDay> days;
  final Set<int> completedDays;
  final Map<String, _FormationReflection> reflectionsByChapterRef;
  final int lastCompletedDay;
  final bool isTodayCompleted;

  const _FormationChallengeViewState({
    required this.isStarted,
    this.days = const [],
    this.completedDays = const {},
    this.reflectionsByChapterRef = const {},
    this.lastCompletedDay = 0,
    this.isTodayCompleted = false,
    this.day,
    this.totalDays,
    this.startDate,
  });
}

class _FormationReflection {
  final JournalEntry entry;
  final String text;

  const _FormationReflection({required this.entry, required this.text});
}

enum _FormationChallengeTab { today, days, stats }
