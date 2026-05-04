import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/data/audio_catalog.dart';
import '../audio/data/audio_track.dart';
import '../audio/ui/inline_audio_player_card.dart';
import '../settings/settings_screen.dart';
import '../../shared/models/formation_challenge_models.dart';
import '../../shared/navigation/app_page_route.dart';
import '../../shared/services/formation_challenge_progress_service.dart';
import '../../shared/services/formation_meditation_settings_service.dart';
import '../../shared/services/formation_widget_snapshot_service.dart';
import '../../shared/widgets/section_header.dart';
import 'formation_journal_helpers.dart';

enum _MeditationContentMode { read, listen }

const double _meditationContentHeight = 312;

class FormationMeditationScreen extends StatefulWidget {
  final FormationChallengeDay day;
  final int totalDays;

  const FormationMeditationScreen({
    super.key,
    required this.day,
    required this.totalDays,
  });

  @override
  State<FormationMeditationScreen> createState() =>
      _FormationMeditationScreenState();
}

class _FormationMeditationScreenState extends State<FormationMeditationScreen> {
  final FormationMeditationSettingsService _settingsService =
      FormationMeditationSettingsService();
  final FormationChallengeProgressService _progressService =
      FormationChallengeProgressService();
  final FormationWidgetSnapshotService _widgetSnapshotService =
      FormationWidgetSnapshotService();

  Timer? _timer;
  Duration? _remaining;
  int? _durationMinutes;
  bool _isLoadingSettings = true;
  bool _isRunning = false;
  bool _isFinished = false;
  bool _completionSaved = false;
  _MeditationContentMode _contentMode = _MeditationContentMode.read;

  @override
  void initState() {
    super.initState();
    _loadDuration();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadDuration() async {
    final minutes = await _settingsService.getDurationMinutes();
    if (!mounted) return;

    setState(() {
      _durationMinutes = minutes;
      _remaining = Duration(minutes: minutes);
      _isLoadingSettings = false;
    });
  }

  void _start() {
    if (_isRunning || _isFinished) return;

    setState(() {
      _isRunning = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      final remaining = _remaining;
      if (remaining == null) return;

      if (remaining.inSeconds <= 1) {
        unawaited(_finish());
        return;
      }

      setState(() {
        _remaining = remaining - const Duration(seconds: 1);
      });
    });
  }

  void _pause() {
    if (!_isRunning) return;

    _timer?.cancel();
    _timer = null;

    setState(() {
      _isRunning = false;
    });
  }

  void _toggleTimer() {
    if (_isRunning) {
      _pause();
    } else {
      _start();
    }
  }

  void _stop() {
    final durationMinutes = _durationMinutes;
    if (durationMinutes == null) return;

    _timer?.cancel();
    _timer = null;

    setState(() {
      _isRunning = false;
      _remaining = Duration(minutes: durationMinutes);
    });
  }

  Future<void> _finish() async {
    if (_isFinished) return;

    _timer?.cancel();
    _timer = null;

    if (!mounted) return;
    setState(() {
      _isRunning = false;
      _isFinished = true;
      _remaining = Duration.zero;
    });

    if (_completionSaved) return;

    final wasAlreadyCompleted = await _progressService.isDayCompleted(
      widget.day.dayNumber,
    );
    if (wasAlreadyCompleted) {
      _completionSaved = true;
      return;
    }

    await _progressService.markDayCompleted(widget.day.dayNumber);
    await _widgetSnapshotService.refresh();
    _completionSaved = true;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dzień oznaczony jako ukończony.')),
    );
  }

  Future<void> _chooseDuration() async {
    if (_isRunning || _isFinished || _durationMinutes == null) return;

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
                      minutes == _durationMinutes
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

    await _settingsService.setDurationMinutes(selected);
    if (!mounted) return;

    setState(() {
      _durationMinutes = selected;
      _remaining = Duration(minutes: selected);
    });
  }

  Future<void> _addReflectionToJournal() async {
    final saved = await openFormationReflectionComposer(
      context: context,
      day: widget.day,
      totalDays: widget.totalDays,
    );

    if (!mounted || !saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Refleksja dodana do dziennika.')),
    );
  }

  void _returnToChallenge() {
    Navigator.of(context).pop();
  }

  void _openSettings() {
    Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/settings'),
        builder: (_) => const SettingsScreen(),
      ),
    );
  }

  String get _timerText {
    final remaining = _remaining ?? Duration.zero;
    final minutes = remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  bool get _hasTimerStarted {
    final durationMinutes = _durationMinutes;
    final remaining = _remaining;
    if (durationMinutes == null || remaining == null || _isFinished) {
      return false;
    }

    return remaining < Duration(minutes: durationMinutes);
  }

  String get _primaryTimerActionLabel {
    if (_isRunning) return 'Pauza';
    if (_hasTimerStarted) return 'Wznów';
    return 'Start';
  }

  IconData get _primaryTimerActionIcon {
    if (_isRunning) return Icons.pause;
    return Icons.play_arrow;
  }

  String get _timerStatusText {
    if (_isRunning) return 'Medytacja trwa';
    if (_hasTimerStarted) return 'Medytacja wstrzymana';
    return 'Gotowe do rozpoczęcia';
  }

  @override
  Widget build(BuildContext context) {
    final audioTrack = _audioTrackForDay(widget.day);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Medytacja',
              subtitle: 'Dzień ${widget.day.dayNumber} z ${widget.totalDays}',
              icon: Icons.self_improvement,
              showBackButton: true,
              onBack: _returnToChallenge,
              trailing: IconButton(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings),
                tooltip: 'Ustawienia',
              ),
            ),
            Expanded(
              child: _isLoadingSettings
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                      children: [
                        Text(
                          widget.day.chapterTitle,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _isRunning || _isFinished
                                ? null
                                : _chooseDuration,
                            icon: const Icon(Icons.timer_outlined),
                            label: Text(
                              'Czas medytacji: $_durationMinutes min',
                            ),
                          ),
                        ),
                        if (_isFinished) ...[
                          const SizedBox(height: 14),
                          _buildFinishedSection(context),
                        ] else ...[
                          const SizedBox(height: 10),
                          _buildContentModeSelector(context, audioTrack),
                          const SizedBox(height: 12),
                          _buildContentSection(context, audioTrack),
                          const SizedBox(height: 24),
                          _buildTimerSection(context),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentModeSelector(
    BuildContext context,
    AudioTrack? audioTrack,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildContentModeButton(
            context: context,
            mode: _MeditationContentMode.read,
            icon: Icons.menu_book_rounded,
            label: 'Czytaj',
          ),
        ),
        if (audioTrack != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _buildContentModeButton(
              context: context,
              mode: _MeditationContentMode.listen,
              icon: Icons.headphones_rounded,
              label: 'Słuchaj',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildContentModeButton({
    required BuildContext context,
    required _MeditationContentMode mode,
    required IconData icon,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _contentMode == mode;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        setState(() {
          _contentMode = mode;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.16)
              : colorScheme.surface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.58)
                : colorScheme.onSurface.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.64),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentSection(BuildContext context, AudioTrack? audioTrack) {
    return SizedBox(
      height: _meditationContentHeight,
      child: _contentMode == _MeditationContentMode.listen && audioTrack != null
          ? InlineAudioPlayerCard(track: audioTrack)
          : _buildReadingSection(context),
    );
  }

  Widget _buildReadingSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Przewiń fragment',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                widget.day.text,
                style: const TextStyle(fontSize: 15, height: 1.45),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Center(
          child: Text(
            _timerText,
            style: const TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            _timerStatusText,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: _toggleTimer,
              icon: Icon(_primaryTimerActionIcon),
              label: Text(_primaryTimerActionLabel),
            ),
            if (_hasTimerStarted || _isRunning)
              TextButton.icon(
                onPressed: _stop,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildFinishedSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.check_circle, size: 42, color: colorScheme.primary),
          const SizedBox(height: 14),
          const Text(
            'Medytacja zakończona',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          const Text(
            'Dzisiejszy dzień został oznaczony jako ukończony.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Zapisz jedną myśl, która zostaje z Tobą po tej medytacji.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.78),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _addReflectionToJournal,
            icon: const Icon(Icons.edit_note),
            label: const Text('Dodaj refleksję do dziennika'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _returnToChallenge,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Wróć do Drogi'),
          ),
        ],
      ),
    );
  }

  AudioTrack? _audioTrackForDay(FormationChallengeDay day) {
    return AudioCatalog.trackForChapter(
      chapterReference: day.chapterReference,
      title: day.chapterTitle,
      subtitle: day.bookTitle,
    );
  }
}
