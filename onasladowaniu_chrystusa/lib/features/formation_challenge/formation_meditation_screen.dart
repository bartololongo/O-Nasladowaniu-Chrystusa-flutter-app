import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/models/formation_challenge_models.dart';
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
  static const Duration _initialDuration = Duration(minutes: 15);

  Timer? _timer;
  Duration _remaining = _initialDuration;
  bool _isRunning = false;
  bool _isFinished = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    if (_isRunning || _isFinished) return;

    setState(() {
      _isRunning = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      if (_remaining.inSeconds <= 1) {
        _finish();
        return;
      }

      setState(() {
        _remaining = _remaining - const Duration(seconds: 1);
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
    final minutes = _remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get _previewText {
    const maxLength = 360;
    final text = widget.day.text.trim();
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength).trimRight()}...';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medytacja'),
      ),
      body: SafeArea(
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
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                _previewText,
                style: const TextStyle(fontSize: 15, height: 1.45),
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
