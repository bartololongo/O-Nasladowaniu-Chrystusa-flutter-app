import 'package:flutter/material.dart';

import '../../shared/models/formation_challenge_models.dart';
import '../../shared/navigation/app_page_route.dart';
import '../../shared/services/journal_service.dart';
import '../journal/journal_screen.dart';

String buildFormationJournalPrefill(FormationChallengeDay day, int totalDays) {
  final buffer = StringBuffer()
    ..writeln('Droga naśladowania')
    ..writeln('Dzień ${day.dayNumber} z $totalDays')
    ..writeln(day.bookTitle)
    ..writeln('${day.chapterTitle} (${day.chapterReference})')
    ..writeln()
    ..writeln('Moja refleksja:')
    ..writeln();

  return buffer.toString();
}

Future<bool> openFormationReflectionComposer({
  required BuildContext context,
  required FormationChallengeDay day,
  required int totalDays,
}) async {
  final existingEntry = await _findExistingFormationJournalEntry(
    day: day,
    totalDays: totalDays,
  );
  final existingReflection = existingEntry == null
      ? null
      : _extractFormationReflection(existingEntry.content);

  if (!context.mounted) return false;

  final saved = await Navigator.of(context).push<bool>(
    AppPageRoute.fade(
      settings: const RouteSettings(name: '/journal/from-formation'),
      builder: (_) => JournalScreen(
        openInitialComposer: true,
        closeAfterInitialComposer: true,
        initialContent: existingReflection,
        initialContentPrefix: buildFormationJournalPrefill(day, totalDays),
        initialQuoteText: day.text,
        initialQuoteRef: day.chapterReference,
        initialComposerTitle: 'Refleksja z Drogi naśladowania',
        initialComposerHint: 'Wpisz swoją refleksję...',
        initialEntryIdToUpdate: existingEntry?.id,
      ),
    ),
  );

  return saved == true;
}

Future<JournalEntry?> _findExistingFormationJournalEntry({
  required FormationChallengeDay day,
  required int totalDays,
}) async {
  final entries = await JournalService().getEntries();
  final dayMarker = 'Dzień ${day.dayNumber} z $totalDays';
  final fallbackDayMarker = 'Dzień ${day.dayNumber} z';

  final matchingEntries = entries.where((entry) {
    final content = entry.content;
    final isFormationEntry = content.contains('Droga naśladowania');
    if (!isFormationEntry) return false;

    final isSameDay =
        content.contains(dayMarker) || content.contains(fallbackDayMarker);
    final isSameReference =
        entry.quoteRef == day.chapterReference ||
        content.contains(day.chapterReference);

    return isSameDay && isSameReference;
  }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  return matchingEntries.isEmpty ? null : matchingEntries.first;
}

String? _extractFormationReflection(String content) {
  const marker = 'Moja refleksja:';
  final markerIndex = content.indexOf(marker);
  if (markerIndex == -1) return content.trim();

  final reflection = content.substring(markerIndex + marker.length).trim();
  return reflection.isEmpty ? null : reflection;
}
