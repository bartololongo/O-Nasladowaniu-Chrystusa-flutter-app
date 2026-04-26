import 'package:flutter/material.dart';

import '../../shared/models/formation_challenge_models.dart';
import '../../shared/services/formation_challenge_progress_service.dart';
import '../../shared/services/formation_challenge_service.dart';
import '../../shared/services/journal_service.dart';
import '../../shared/services/preferences_service.dart';
import 'formation_journal_helpers.dart';
import 'formation_meditation_screen.dart';

class FormationChallengeScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;

  const FormationChallengeScreen({
    super.key,
    this.onNavigateToTab,
  });

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

  late Future<_FormationChallengeViewState> _stateFuture;
  _FormationChallengeTab _selectedTab = _FormationChallengeTab.today;
  FormationChallengeDay? _activeDayOverride;

  @override
  void initState() {
    super.initState();
    _stateFuture = _loadState();
  }

  Future<_FormationChallengeViewState> _loadState() async {
    final isStarted = await _progressService.isStarted();
    if (!isStarted) {
      return _FormationChallengeViewState(
        isStarted: false,
      );
    }

    final startDate = await _progressService.getStartDate();
    if (startDate == null) {
      return _FormationChallengeViewState(
        isStarted: false,
      );
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

    return _FormationChallengeViewState(
      isStarted: true,
      day: day,
      totalDays: totalDays,
      days: days,
      completedDays: completedDays,
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
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _markDayCompleted(FormationChallengeDay day) async {
    await _progressService.markDayCompleted(day.dayNumber);
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Refleksja dodana do dziennika.')),
    );
  }

  Future<void> _openMeditation(
    FormationChallengeDay day,
    int totalDays,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/formation-meditation'),
        builder: (_) => FormationMeditationScreen(
          day: day,
          totalDays: totalDays,
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openDayInReader(FormationChallengeDay day) async {
    await _preferencesService.setJumpChapterRef(day.chapterReference);
    await _preferencesService.clearJumpParagraphNumber();

    if (!mounted) return;
    widget.onNavigateToTab?.call(1);

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Droga naśladowania'),
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
              'Codzienna medytacja z «O naśladowaniu Chrystusa»',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
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
                    onPressed: () =>
                        _addReflectionToJournal(activeDay, totalDays),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Dodaj refleksję do dziennika'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _openDayInReader(activeDay),
                    icon: const Icon(Icons.menu_book),
                    label: const Text('Zobacz w książce'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _openMeditation(activeDay, totalDays),
                    icon: const Icon(Icons.self_improvement),
                    label: const Text('Rozpocznij medytację'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: isActiveDayCompleted
                        ? null
                        : () => _markDayCompleted(activeDay),
                    icon: Icon(
                      isActiveDayCompleted
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                    ),
                    label: Text(
                      isActiveDayCompleted
                          ? 'Ten dzień jest ukończony'
                          : 'Oznacz dzień jako ukończony',
                    ),
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
    required bool isMakeUpDay,
    required bool isActiveDayCompleted,
  }) {
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
            isActiveDayCompleted
                ? 'Dzień nadrobiony'
                : 'Dzień do nadrobienia',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          day.text,
          style: const TextStyle(
            fontSize: 17,
            height: 1.55,
          ),
        ),
      ],
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
      return const Center(
        child: Text('Nie udało się wczytać listy dni.'),
      );
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
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
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                    ),
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
    final matchingEntries = entries
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
        return reflection;
      }
    }

    if (matchingEntries.isEmpty) return null;
    return _extractReflection(matchingEntries.first.content);
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.25),
        ),
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
          _buildSummaryRow(
            context,
            'Do nadrobienia',
            '$catchUpDays',
          ),
          const SizedBox(height: 6),
          _buildSummaryRow(
            context,
            'Aktualny dzień',
            '$currentDayNumber',
          ),
          const SizedBox(height: 6),
          _buildSummaryRow(
            context,
            'Postęp',
            '$progressPercent%',
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

  Widget _buildSummaryRow(
    BuildContext context,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(
                    alpha: 0.75,
                  ),
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
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
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
              ),
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
  final List<FormationChallengeDay> days;
  final Set<int> completedDays;
  final int lastCompletedDay;
  final bool isTodayCompleted;

  const _FormationChallengeViewState({
    required this.isStarted,
    this.days = const [],
    this.completedDays = const {},
    this.lastCompletedDay = 0,
    this.isTodayCompleted = false,
    this.day,
    this.totalDays,
  });
}

enum _FormationChallengeTab {
  today,
  days,
  stats,
}
