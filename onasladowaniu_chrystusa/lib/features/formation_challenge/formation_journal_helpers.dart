import 'package:flutter/material.dart';

import '../../shared/models/formation_challenge_models.dart';
import '../journal/journal_screen.dart';

String buildFormationJournalPrefill(
  FormationChallengeDay day,
  int totalDays,
) {
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
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      settings: const RouteSettings(name: '/journal/from-formation'),
      builder: (_) => JournalScreen(
        openInitialComposer: true,
        closeAfterInitialComposer: true,
        initialContentPrefix: buildFormationJournalPrefill(day, totalDays),
        initialQuoteText: day.text,
        initialQuoteRef: day.chapterReference,
        initialComposerTitle: 'Refleksja z Drogi naśladowania',
        initialComposerHint: 'Wpisz swoją refleksję...',
      ),
    ),
  );

  return saved == true;
}
