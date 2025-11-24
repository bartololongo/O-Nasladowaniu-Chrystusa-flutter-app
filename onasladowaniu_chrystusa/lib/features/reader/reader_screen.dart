import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/models/book_models.dart';
import '../../shared/services/book_repository.dart';
import '../../shared/services/preferences_service.dart';
import '../../shared/services/bookmarks_service.dart';
import '../../shared/services/favorites_service.dart';
import '../../shared/services/journal_service.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final BookRepository _bookRepository = BookRepository();
  final PreferencesService _prefs = PreferencesService();
  final BookmarksService _bookmarksService = BookmarksService();
  final FavoritesService _favoritesService = FavoritesService();
  final JournalService _journalService = JournalService();

  late final ScrollController _scrollController;

  double _fontSize = 18.0;
  double _lineHeight = 1.5;
  bool _isJustified = true;

  late Future<BookChapter> _chapterFuture;
  String _currentChapterRef = 'I-1'; // fallback

  double? _pendingScrollOffset;
  bool _isCurrentBookmarked = false;

  // flaga, żeby nie odpalać wielu równoległych sprawdzeń jumpa
  bool _isCheckingJump = false;

  // aktualnie zaznaczony tekst (własne zaznaczenie w readerze)
  String? _selectedText;

  // tekst, który mamy podświetlić po "Zobacz w książce"
  String? _highlightSearchText;

  @override
  void initState() {
    super.initState();

    _scrollController = ScrollController();
    _scrollController.addListener(_onScrollChanged);

    // Jedno źródło prawdy dla startowego rozdziału:
    // 1) jumpChapterRef (Zobacz w książce / zakładki / ulubione)
    // 2) lastChapterRef (główny postęp)
    // 3) pierwszy rozdział
    _chapterFuture = _initInitialChapter();

    // Wczytanie rozmiaru czcionki
    _loadReaderFontSize();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    _prefs.saveScrollOffset(_currentChapterRef, offset);
  }

  Future<void> _loadReaderFontSize() async {
    final stored = await _prefs.getReaderFontSize();
    if (!mounted) return;
    if (stored != null) {
      setState(() {
        _fontSize = stored;
      });
    }
  }

  /// Wyznacza startowy rozdział:
  /// - jeśli jest jumpChapterRef → użyj go (jednorazowo),
  /// - w przeciwnym razie lastChapterRef,
  /// - jeśli brak → pierwszy rozdział.
  Future<BookChapter> _initInitialChapter() async {
    // 1. Najpierw spróbuj tymczasowego skoku
    final jumpRef = await _prefs.getJumpChapterRef();
    final highlight = await _prefs.getHighlightSearchText();

    String? refToLoad;

    if (jumpRef != null && jumpRef.isNotEmpty) {
      refToLoad = jumpRef;
      await _prefs.clearJumpChapterRef();
    } else {
      // 2. Jeśli brak jump – użyj ostatnio czytanego
      final savedRef = await _prefs.getLastChapterRef();
      if (savedRef != null && savedRef.isNotEmpty) {
        refToLoad = savedRef;
      }
    }

    BookChapter? chapter;

    if (refToLoad != null) {
      chapter = await _bookRepository.getChapterByReference(refToLoad);
    }

    // 3. Jeśli nic nie ma / nie udało się wczytać – startuj od pierwszego
    if (chapter == null) {
      chapter = await _bookRepository.getFirstChapter();

      // jeśli to pierwsze uruchomienie i nie mamy last, ustaw go na pierwszy rozdział
      final currentLast = await _prefs.getLastChapterRef();
      if (currentLast == null || currentLast.isEmpty) {
        await _prefs.saveLastChapterRef(chapter.reference);
      }
    }

    if (!mounted) {
      return chapter!;
    }

    _currentChapterRef = chapter!.reference;

    // przejmij ewentualny tekst do podświetlenia (z ulubionych / dziennika)
    final trimmedHighlight = highlight?.trim();
    if (trimmedHighlight != null && trimmedHighlight.isNotEmpty) {
      setState(() {
        _highlightSearchText = trimmedHighlight;
        _selectedText = null; // highlight nie jest "systemowym" zaznaczeniem
      });
      await _prefs.clearHighlightSearchText();
    }

    // przygotuj scroll i status zakładki dla bieżącego rozdziału
    await _loadScrollOffsetForChapter(_currentChapterRef);
    await _refreshBookmarkStatus();

    return chapter;
  }

  Future<void> _loadScrollOffsetForChapter(String reference) async {
    final offset = await _prefs.getScrollOffset(reference);
    if (!mounted) return;
    setState(() {
      _pendingScrollOffset = offset;
    });
  }

  Future<void> _refreshBookmarkStatus() async {
    final isBookmarked =
        await _bookmarksService.isChapterBookmarked(_currentChapterRef);
    if (!mounted) return;
    setState(() {
      _isCurrentBookmarked = isBookmarked;
    });
  }

  void _loadChapterByReference(
    String reference, {
    bool saveAsLast = true,
    bool keepHighlight = false,
  }) {
    setState(() {
      _currentChapterRef = reference;
      _chapterFuture =
          _bookRepository.getChapterByReference(reference).then((chapter) {
        if (chapter == null) {
          throw Exception('Nie znaleziono rozdziału $reference');
        }
        return chapter;
      });
      _pendingScrollOffset = null;
      _selectedText = null;
      if (!keepHighlight) {
        _highlightSearchText = null;
      }
    });

    if (saveAsLast) {
      _prefs.saveLastChapterRef(reference);
    }

    _loadScrollOffsetForChapter(reference);
    _refreshBookmarkStatus();
  }

  void _showChapterPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: FutureBuilder<BookCollection>(
            future: _bookRepository.getCollection(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return SizedBox(
                  height: 200,
                  child: Center(
                    child: Text(
                      'Błąd wczytywania listy rozdziałów:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 200,
                  child: Center(
                    child: Text('Brak danych książki'),
                  ),
                );
              }

              final collection = snapshot.data!;
              final books = collection.books;
              final colorScheme = Theme.of(context).colorScheme;

              if (books.isEmpty) {
                return const SizedBox(
                  height: 200,
                  child: Center(
                    child: Text('Brak ksiąg w kolekcji'),
                  ),
                );
              }

              // domyślnie wybierz księgę zawierającą bieżący rozdział
              int initialSelectedIndex = 0;
              for (int i = 0; i < books.length; i++) {
                final book = books[i];
                final hasCurrent = book.chapters.any(
                  (ch) => ch.reference == _currentChapterRef,
                );
                if (hasCurrent) {
                  initialSelectedIndex = i;
                  break;
                }
              }

              int selectedBookIndex = initialSelectedIndex;

              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.7,
                minChildSize: 0.4,
                maxChildSize: 0.9,
                builder: (context, scrollController) {
                  return StatefulBuilder(
                    builder: (context, setModalState) {
                      final selectedBook = books[selectedBookIndex];

                      return Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: colorScheme.onSurface.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Wybierz księgę i rozdział',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Pasek wyboru księgi (I, II, III, IV...)
                            SizedBox(
                              height: 48,
                              child: ListView.separated(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                scrollDirection: Axis.horizontal,
                                itemCount: books.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final book = books[index];
                                  final isSelected =
                                      index == selectedBookIndex;

                                  return ChoiceChip(
                                    label: Text(
                                      'Księga ${book.code}',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    selected: isSelected,
                                    onSelected: (_) {
                                      setModalState(() {
                                        selectedBookIndex = index;
                                      });
                                    },
                                  );
                                },
                              ),
                            ),

                            const SizedBox(height: 8),

                            // Lista rozdziałów tylko z wybranej księgi
                            Expanded(
                              child: ListView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                    16, 0, 16, 16),
                                itemCount: selectedBook.chapters.length,
                                itemBuilder: (context, index) {
                                  final chapter =
                                      selectedBook.chapters[index];

                                  return ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 0,
                                      vertical: 0,
                                    ),
                                    title: Text(chapter.title),
                                    subtitle: Text(
                                      'Rozdział ${chapter.number} • ${chapter.reference}',
                                    ),
                                    trailing:
                                        _currentChapterRef ==
                                                chapter.reference
                                            ? Icon(
                                                Icons.check,
                                                color: colorScheme.primary,
                                              )
                                            : null,
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      _loadChapterByReference(
                                        chapter.reference,
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _goToNextChapter() async {
    try {
      final next =
          await _bookRepository.getNextChapter(_currentChapterRef);
      if (!mounted) return;
      if (next == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('To jest ostatni rozdział.'),
          ),
        );
        return;
      }
      _loadChapterByReference(next.reference);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Nie udało się przejść do następnego rozdziału: $e'),
        ),
      );
    }
  }

  Future<void> _goToPreviousChapter() async {
    try {
      final previous =
          await _bookRepository.getPreviousChapter(_currentChapterRef);
      if (!mounted) return;
      if (previous == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('To jest pierwszy rozdział.'),
          ),
        );
        return;
      }
      _loadChapterByReference(previous.reference);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Nie udało się przejść do poprzedniego rozdziału: $e'),
        ),
      );
    }
  }

  Future<void> _toggleBookmarkForCurrentChapter() async {
    try {
      if (_isCurrentBookmarked) {
        await _bookmarksService
            .removeBookmarkForChapterRef(_currentChapterRef);
        if (!mounted) return;
        setState(() {
          _isCurrentBookmarked = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zakładka usunięta.')),
        );
      } else {
        await _bookmarksService
            .addBookmarkForChapterRef(_currentChapterRef);
        if (!mounted) return;
        setState(() {
          _isCurrentBookmarked = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zakładka dodana.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nie udało się zaktualizować zakładki: $e'),
        ),
      );
    }
  }

  /// Zakładka z paska zaznaczenia – zawsze "dodaj", bez usuwania.
  Future<void> _addSelectionBookmark() async {
    if (_isCurrentBookmarked) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Zakładka dla tego rozdziału już istnieje.'),
        ),
      );
      return;
    }

    try {
      await _bookmarksService.addBookmarkForChapterRef(_currentChapterRef);
      if (!mounted) return;
      setState(() {
        _isCurrentBookmarked = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dodano zakładkę dla bieżącego rozdziału.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nie udało się dodać zakładki: $e'),
        ),
      );
    }
  }

  /// Kopiowanie aktualnie zaznaczonego tekstu (_selectedText) do schowka.
  Future<void> _copySelectionToClipboard() async {
    final text = _selectedText?.trim();
    if (text == null || text.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Skopiowano zaznaczony tekst.')),
    );
  }

  /// Kopiowanie tekstu z highlightu (_highlightSearchText).
  Future<void> _copyHighlightToClipboard() async {
    final text = _highlightSearchText?.trim();
    if (text == null || text.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Skopiowano fragment.')),
    );
  }

  /// Sprawdza, czy z zewnątrz nie ustawiono nowego jumpChapterRef
  /// (losowy cytat / zakładka / ulubione) i jeśli tak – ładuje odpowiedni rozdział
  /// bez nadpisywania lastChapterRef.
  void _maybeHandleExternalJump() {
    if (_isCheckingJump) return;
    _isCheckingJump = true;

    Future.microtask(() async {
      try {
        final jumpRef = await _prefs.getJumpChapterRef();
        final highlight = await _prefs.getHighlightSearchText();

        final trimmedHighlight = highlight?.trim();
        if (trimmedHighlight != null && trimmedHighlight.isNotEmpty) {
          if (mounted) {
            setState(() {
              _highlightSearchText = trimmedHighlight;
              _selectedText = null;
            });
          }
          await _prefs.clearHighlightSearchText();
        }

        if (jumpRef != null &&
            jumpRef.isNotEmpty &&
            jumpRef != _currentChapterRef) {
          await _prefs.clearJumpChapterRef();
          _loadChapterByReference(
            jumpRef,
            saveAsLast: false,
            keepHighlight: true,
          );
        }
      } finally {
        _isCheckingJump = false;
      }
    });
  }

  /// Publiczne API dla zewnętrznego świata (RootScreen).
  /// Wołane np. po "Zobacz w książce", żeby natychmiast
  /// obsłużyć ewentualny jump / highlight zapisany w PreferencesService.
  void handleExternalJump() {
    _maybeHandleExternalJump();
  }

  @override
  Widget build(BuildContext context) {
    // Przy każdym buildzie sprawdzamy, czy nie ma nowego "skoku" z zewnątrz
    _maybeHandleExternalJump();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Czytanie'),
        actions: [
          IconButton(
            icon: Icon(
              _isCurrentBookmarked
                  ? Icons.bookmark
                  : Icons.bookmark_border,
            ),
            tooltip:
                _isCurrentBookmarked ? 'Usuń zakładkę' : 'Dodaj zakładkę',
            onPressed: _toggleBookmarkForCurrentChapter,
          ),
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: 'Wybierz księgę i rozdział',
            onPressed: _showChapterPicker,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildControls(),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<BookChapter>(
              future: _chapterFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Błąd wczytywania rozdziału:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: Text('Brak danych rozdziału'),
                  );
                }

                final chapter = snapshot.data!;

                if (_pendingScrollOffset != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!_scrollController.hasClients) return;
                    final max =
                        _scrollController.position.maxScrollExtent;
                    final target = _pendingScrollOffset!.clamp(
                      0.0,
                      max > 0 ? max : double.infinity,
                    );
                    _scrollController.jumpTo(target);
                    _pendingScrollOffset = null;
                  });
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTitle(chapter),
                    _buildChapterNavigation(chapter),
                    const SizedBox(height: 8),
                    _buildReader(chapter),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                _fontSize = (_fontSize - 2).clamp(12.0, 30.0);
              });
              _prefs.saveReaderFontSize(_fontSize);
            },
            icon: const Icon(Icons.remove),
            tooltip: 'Mniejsza czcionka',
          ),
          Expanded(
            child: Slider(
              value: _fontSize,
              min: 12,
              max: 30,
              label: _fontSize.toStringAsFixed(0),
              onChanged: (value) {
                setState(() {
                  _fontSize = value;
                });
                _prefs.saveReaderFontSize(_fontSize);
              },
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _fontSize = (_fontSize + 2).clamp(12.0, 30.0);
              });
              _prefs.saveReaderFontSize(_fontSize);
            },
            icon: const Icon(Icons.add),
            tooltip: 'Większa czcionka',
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              setState(() {
                _isJustified = !_isJustified;
              });
            },
            icon: Icon(
              _isJustified
                  ? Icons.format_align_justify
                  : Icons.format_align_left,
            ),
            tooltip:
                _isJustified ? 'Wyrównaj do lewej' : 'Wyjustuj tekst',
          ),
        ],
      ),
    );
  }

  Widget _buildTitle(BookChapter chapter) {
    final colorScheme = Theme.of(context).colorScheme;

    String subtitle;
    final parts = chapter.reference.split('-');
    if (parts.length == 2) {
      final bookCode = parts[0];
      final chapterNumber = parts[1];
      subtitle = 'Księga $bookCode, rozdział $chapterNumber';
    } else {
      subtitle = 'Rozdział ${chapter.reference}';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chapter.title,
            style: TextStyle(
              fontSize: _fontSize + 2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChapterNavigation(BookChapter chapter) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: _goToPreviousChapter,
            icon: const Icon(Icons.chevron_left),
            label: const Text('Poprzedni'),
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.primary,
            ),
          ),
          TextButton.icon(
            onPressed: _goToNextChapter,
            icon: const Icon(Icons.chevron_right),
            label: const Text('Następny'),
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReader(BookChapter chapter) {
    return Expanded(
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final paragraph in chapter.paragraphs) ...[
                  _buildParagraphText(paragraph.text),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          if (_selectedText != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildSelectionToolbar(chapter),
            )
          else if (_highlightSearchText != null &&
              _highlightSearchText!.trim().isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildHighlightToolbar(chapter),
            ),
        ],
      ),
    );
  }

  /// Rysuje akapit, a jeśli jest _highlightSearchText – podświetla w nim fragment.
  /// Używamy SelectableText / SelectableText.rich zamiast SelectionArea.
  Widget _buildParagraphText(String text) {
    final query = _highlightSearchText?.trim();
    final colorScheme = Theme.of(context).colorScheme;

    void handleSelection(TextSelection selection, SelectionChangedCause? cause) {
      final start = selection.start;
      final end = selection.end;

      // Brak realnego zaznaczenia
      if (start == -1 || end == -1 || start == end) {
        setState(() {
          _selectedText = null;
        });
        return;
      }

      final lo = math.min(start, end);
      final hi = math.max(start, end);

      if (lo < 0 || hi > text.length) {
        setState(() {
          _selectedText = null;
        });
        return;
      }

      final selected = text.substring(lo, hi).trim();
      setState(() {
        _selectedText = selected.isNotEmpty ? selected : null;
        if (_selectedText != null) {
          // w momencie własnego zaznaczenia wyłącz highlight z "Zobacz w książce"
          _highlightSearchText = null;
        }
      });
    }

    // Bez highlightu – zwykły SelectableText
    if (query == null || query.isEmpty) {
      return SelectableText(
        text,
        textAlign: _isJustified ? TextAlign.justify : TextAlign.left,
        style: TextStyle(
          fontSize: _fontSize,
          height: _lineHeight,
        ),
        onSelectionChanged: handleSelection,
      );
    }

    // Z highlightem – szukamy fragmentu w akapicie
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final startIndex = lowerText.indexOf(lowerQuery);

    // akapit nie zawiera szukanego fragmentu – zwykły SelectableText
    if (startIndex < 0) {
      return SelectableText(
        text,
        textAlign: _isJustified ? TextAlign.justify : TextAlign.left,
        style: TextStyle(
          fontSize: _fontSize,
          height: _lineHeight,
        ),
        onSelectionChanged: handleSelection,
      );
    }

    final endIndex = startIndex + query.length;
    final before = text.substring(0, startIndex);
    final match = text.substring(startIndex, endIndex);
    final after = text.substring(endIndex);

    return SelectableText.rich(
      TextSpan(
        style: TextStyle(
          fontSize: _fontSize,
          height: _lineHeight,
          color: colorScheme.onSurface,
        ),
        children: [
          if (before.isNotEmpty) TextSpan(text: before),
          TextSpan(
            text: match,
            style: TextStyle(
              backgroundColor: colorScheme.primary.withOpacity(0.35),
            ),
          ),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
      textAlign: _isJustified ? TextAlign.justify : TextAlign.left,
      onSelectionChanged: handleSelection,
    );
  }

  Widget _buildSelectionToolbar(BookChapter chapter) {
    final colorScheme = Theme.of(context).colorScheme;
    final preview = _selectedText ?? '';

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              blurRadius: 8,
              offset: const Offset(0, -2),
              color: Colors.black.withOpacity(0.4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Kopiuj',
              icon: const Icon(Icons.copy),
              onPressed: _copySelectionToClipboard,
            ),
            IconButton(
              tooltip: 'Do ulubionych',
              icon: const Icon(Icons.favorite_border),
              onPressed: () => _addSelectionToFavorites(chapter),
            ),
            IconButton(
              tooltip: 'Do dziennika',
              icon: const Icon(Icons.edit_note),
              onPressed: () => _addSelectionToJournal(chapter),
            ),
            IconButton(
              tooltip: 'Zakładka (rozdział)',
              icon: const Icon(Icons.bookmark_add_outlined),
              onPressed: _addSelectionBookmark,
            ),
            IconButton(
              tooltip: 'Zamknij',
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _selectedText = null;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightToolbar(BookChapter chapter) {
    final colorScheme = Theme.of(context).colorScheme;
    final preview = _highlightSearchText ?? '';

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              blurRadius: 8,
              offset: const Offset(0, -2),
              color: Colors.black.withOpacity(0.4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Kopiuj',
              icon: const Icon(Icons.copy),
              onPressed: _copyHighlightToClipboard,
            ),
            IconButton(
              tooltip: 'Do ulubionych',
              icon: const Icon(Icons.favorite_border),
              onPressed: () => _addHighlightToFavorites(chapter),
            ),
            IconButton(
              tooltip: 'Do dziennika',
              icon: const Icon(Icons.edit_note),
              onPressed: () => _addHighlightToJournal(chapter),
            ),
            IconButton(
              tooltip: 'Zamknij',
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _highlightSearchText = null;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addSelectionToFavorites(BookChapter chapter) async {
    final text = _selectedText?.trim();
    if (text == null || text.isEmpty) return;

    try {
      final paragraph = BookParagraph(
        index: 0, // sztuczny indeks dla zaznaczenia
        reference: '${chapter.reference}-sel',
        text: text,
      );

      await _favoritesService.addOrUpdateFavoriteForParagraph(
        paragraph,
        note: null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dodano zaznaczony fragment do ulubionych.'),
        ),
      );
      setState(() {
        _selectedText = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nie udało się dodać do ulubionych: $e'),
        ),
      );
    }
  }

  Future<void> _addHighlightToFavorites(BookChapter chapter) async {
    final text = _highlightSearchText?.trim();
    if (text == null || text.isEmpty) return;

    try {
      final paragraph = BookParagraph(
        index: 0,
        reference: '${chapter.reference}-hl',
        text: text,
      );

      await _favoritesService.addOrUpdateFavoriteForParagraph(
        paragraph,
        note: null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dodano fragment do ulubionych.'),
        ),
      );
      setState(() {
        _highlightSearchText = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nie udało się dodać do ulubionych: $e'),
        ),
      );
    }
  }

  Future<void> _addSelectionToJournal(BookChapter chapter) async {
    final text = _selectedText?.trim();
    if (text == null || text.isEmpty) return;

    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Dodaj do dziennika'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Twoja notatka:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Co mówi do Ciebie ten fragment? '
                        'Jak chcesz na niego odpowiedzieć?',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Anuluj'),
            ),
            TextButton(
              onPressed: () async {
                final note = controller.text.trim();

                await _journalService.addEntry(
                  content: note.isEmpty ? text : note,
                  quoteText: text,
                  quoteRef: '${chapter.reference}-sel',
                );

                if (!mounted) return;
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Dodano wpis do dziennika.'),
                  ),
                );
              },
              child: const Text('Zapisz'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    setState(() {
      _selectedText = null;
    });
  }

  Future<void> _addHighlightToJournal(BookChapter chapter) async {
    final text = _highlightSearchText?.trim();
    if (text == null || text.isEmpty) return;

    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Dodaj do dziennika'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Twoja notatka:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Co mówi do Ciebie ten fragment? '
                        'Jak chcesz na niego odpowiedzieć?',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Anuluj'),
            ),
            TextButton(
              onPressed: () async {
                final note = controller.text.trim();

                await _journalService.addEntry(
                  content: note.isEmpty ? text : note,
                  quoteText: text,
                  quoteRef: '${chapter.reference}-hl',
                );

                if (!mounted) return;
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Dodano wpis do dziennika.'),
                  ),
                );
              },
              child: const Text('Zapisz'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    setState(() {
      _highlightSearchText = null;
    });
  }
}
