enum GlobalSearchResultType { bookParagraph, bookmark, favorite, journalEntry }

class GlobalSearchResult {
  final String id;
  final GlobalSearchResultType type;
  final String title;
  final String subtitle;
  final String snippet;
  final String? chapterRef;
  final String? paragraphRef;
  final String? journalEntryId;

  const GlobalSearchResult({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.snippet,
    this.chapterRef,
    this.paragraphRef,
    this.journalEntryId,
  });

  String get sourceLabel {
    switch (type) {
      case GlobalSearchResultType.bookParagraph:
        return 'Książka';
      case GlobalSearchResultType.bookmark:
        return 'Zakładki';
      case GlobalSearchResultType.favorite:
        return 'Ulubione';
      case GlobalSearchResultType.journalEntry:
        return 'Dziennik';
    }
  }
}
