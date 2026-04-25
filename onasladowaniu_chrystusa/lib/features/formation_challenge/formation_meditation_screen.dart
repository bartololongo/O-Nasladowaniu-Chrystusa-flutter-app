import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/models/formation_challenge_models.dart';
import '../../shared/services/formation_meditation_settings_service.dart';
import 'formation_journal_helpers.dart';

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

  Timer? _timer;
  Duration? _remaining;
  int? _durationMinutes;
  bool _isLoadingSettings = true;
  bool _isRunning = false;
  bool _isFinished = false;

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
        _finish();
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

  void _finish() {
    _timer?.cancel();
    _timer = null;

    if (!mounted) return;
    setState(() {
      _isRunning = false;
      _isFinished = true;
      _remaining = Duration.zero;
    });
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

  String get _timerText {
    final remaining = _remaining ?? Duration.zero;
    final minutes = remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medytacja'),
      ),
      body: _isLoadingSettings
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text(
              'Dzień ${widget.day.dayNumber} z ${widget.totalDays}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              widget.day.chapterTitle,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isRunning || _isFinished ? null : _chooseDuration,
                icon: const Icon(Icons.timer_outlined),
                label: Text('Czas medytacji: $_durationMinutes min'),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.25),
                ),
              ),
              constraints: const BoxConstraints(maxHeight: 220),
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
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                _timerText,
                style: const TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _isFinished
                    ? 'Medytacja zakończona'
                    : _isRunning
                        ? 'Medytacja trwa'
                        : 'Gotowe do rozpoczęcia',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _isFinished ? null : _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start'),
                ),
                OutlinedButton.icon(
                  onPressed: _isRunning ? _pause : null,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pauza'),
                ),
                TextButton.icon(
                  onPressed: _isFinished ? null : _finish,
                  icon: const Icon(Icons.stop),
                  label: const Text('Zakończ'),
                ),
              ],
            ),
            if (_isFinished) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _addReflectionToJournal,
                icon: const Icon(Icons.edit_note),
                label: const Text('Dodaj refleksję do dziennika'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
