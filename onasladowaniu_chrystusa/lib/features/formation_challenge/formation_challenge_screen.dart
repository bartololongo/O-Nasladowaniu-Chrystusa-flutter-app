import 'package:flutter/material.dart';

import '../../shared/models/formation_challenge_models.dart';
import '../../shared/services/formation_challenge_progress_service.dart';
import '../../shared/services/formation_challenge_service.dart';
import '../../shared/services/formation_notification_service.dart';
import 'formation_journal_helpers.dart';
import 'formation_meditation_screen.dart';

class FormationChallengeScreen extends StatefulWidget {
  const FormationChallengeScreen({super.key});

  @override
  State<FormationChallengeScreen> createState() =>
      _FormationChallengeScreenState();
}

class _FormationChallengeScreenState extends State<FormationChallengeScreen> {
  final FormationChallengeService _challengeService =
      FormationChallengeService();
  final FormationChallengeProgressService _progressService =
      FormationChallengeProgressService();
  final FormationNotificationService _notificationService =
      FormationNotificationService.instance;

  late Future<_FormationChallengeViewState> _stateFuture;

  @override
  void initState() {
    super.initState();
    _stateFuture = _loadState();
  }

  Future<_FormationChallengeViewState> _loadState() async {
    final reminderEnabled = await _notificationService.isReminderEnabled();
    final reminderTime = await _notificationService.getReminderTime();

    final isStarted = await _progressService.isStarted();
    if (!isStarted) {
      return _FormationChallengeViewState(
        isStarted: false,
        reminderEnabled: reminderEnabled,
        reminderTime: reminderTime,
      );
    }

    final startDate = await _progressService.getStartDate();
    if (startDate == null) {
      return _FormationChallengeViewState(
        isStarted: false,
        reminderEnabled: reminderEnabled,
        reminderTime: reminderTime,
      );
    }

    final day = await _challengeService.getDayForDate(
      startDate,
      DateTime.now(),
    );
    final totalDays = await _challengeService.getTotalDays();

    return _FormationChallengeViewState(
      isStarted: true,
      day: day,
      totalDays: totalDays,
      reminderEnabled: reminderEnabled,
      reminderTime: reminderTime,
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

  Future<void> _resetChallenge() async {
    await _progressService.resetChallenge();
    if (!mounted) return;
    await _refresh();
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
  }

  Future<void> _setReminderEnabled(bool enabled) async {
    await _notificationService.setReminderEnabled(enabled);
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _changeReminderTime(FormationReminderTime currentTime) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: currentTime.toTimeOfDay(),
    );
    if (selected == null) return;

    await _notificationService.setReminderTime(
      hour: selected.hour,
      minute: selected.minute,
    );
    if (!mounted) return;
    await _refresh();
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

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Text(
                'Dzień ${day.dayNumber} z $totalDays',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                day.bookTitle,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                day.chapterTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              if (day.chapterReference.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  day.chapterReference,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 20),
              _buildReminderSection(context, state),
              const SizedBox(height: 20),
              Text(
                day.text,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _addReflectionToJournal(day, totalDays),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Dodaj refleksję do dziennika'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _openMeditation(day, totalDays),
                  icon: const Icon(Icons.self_improvement),
                  label: const Text('Rozpocznij medytację'),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _resetChallenge,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Zacznij od nowa'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReminderSection(
    BuildContext context,
    _FormationChallengeViewState state,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final reminderTime = state.reminderTime;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: state.reminderEnabled,
            onChanged: _setReminderEnabled,
            title: const Text('Przypomnienie o Drodze naśladowania'),
            subtitle: Text(reminderTime.formatted),
            secondary: const Icon(Icons.notifications_outlined),
          ),
          ListTile(
            enabled: state.reminderEnabled,
            leading: const Icon(Icons.schedule),
            title: const Text('Godzina przypomnienia'),
            subtitle: Text(reminderTime.formatted),
            onTap: state.reminderEnabled
                ? () => _changeReminderTime(reminderTime)
                : null,
          ),
        ],
      ),
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
  final bool reminderEnabled;
  final FormationReminderTime reminderTime;

  const _FormationChallengeViewState({
    required this.isStarted,
    required this.reminderEnabled,
    required this.reminderTime,
    this.day,
    this.totalDays,
  });
}
