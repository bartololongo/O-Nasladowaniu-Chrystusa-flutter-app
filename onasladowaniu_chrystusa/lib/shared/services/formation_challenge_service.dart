import '../models/formation_challenge_models.dart';
import 'book_repository.dart';

class FormationChallengeService {
  final BookRepository _bookRepository;

  FormationChallengeService({
    BookRepository? bookRepository,
  }) : _bookRepository = bookRepository ?? BookRepository();

  Future<List<FormationChallengeDay>> getDays() async {
    final collection = await _bookRepository.getCollection();
    final days = <FormationChallengeDay>[];

    var dayNumber = 1;
    for (final book in collection.books) {
      for (final chapter in book.chapters) {
        days.add(
          FormationChallengeDay(
            id: 'day-$dayNumber',
            dayNumber: dayNumber,
            bookTitle: book.title,
            chapterTitle: chapter.title,
            chapterReference: chapter.reference,
            text: chapter.paragraphs.map((p) => p.text).join('\n\n'),
          ),
        );
        dayNumber++;
      }
    }

    return days;
  }

  Future<FormationChallengeDay> getDayForDate(
    DateTime startDate,
    DateTime now,
  ) async {
    final days = await getDays();
    if (days.isEmpty) {
      throw StateError('Formation challenge has no days.');
    }

    final localStartDate = startDate.toLocal();
    final localNow = now.toLocal();

    final startDay = DateTime(
      localStartDate.year,
      localStartDate.month,
      localStartDate.day,
    );
    final currentDay = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
    );

    final dayNumber = currentDay.difference(startDay).inDays + 1;
    final clampedDayNumber = dayNumber.clamp(1, days.length);

    return days[clampedDayNumber - 1];
  }

  Future<FormationChallengeDay?> getDayByNumber(int dayNumber) async {
    if (dayNumber < 1) return null;

    final days = await getDays();
    if (dayNumber > days.length) return null;

    return days[dayNumber - 1];
  }

  Future<int> getTotalDays() async {
    final days = await getDays();
    return days.length;
  }
}
