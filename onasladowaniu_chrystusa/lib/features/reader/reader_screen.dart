import 'package:flutter/material.dart';
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

  // aktualnie zaznaczony tekst (SelectionArea)
  String? _selectedText;

  // --- NOWE: obsługa skoku do konkretnego akapitu ---
  // numer akapitu (1-based) przekazany z zewnątrz
  int? _jumpParagraphNumber;
  // czy po zrenderowaniu rozdziału mamy przewinąć do tego akapitu
  bool _pendingJumpToParagraph = false;
  // GlobalKey na każdy akapit w bieżącym rozdziale
  final Map<int, GlobalKey> _paragraphKeys = {};

  @override
  void initState() {
    super.initState();

    _scrollController = ScrollController();
    _scrollController.addListener(_onScrollChanged);

    // Jedno źródło prawdy dla startowego rozdziału:
    // 1) jumpChapterRef (Zobacz w książce / zakładki / ulubione / losowy cytat)
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
  ///
  /// Jeśli jest też jumpParagraphNumber – przewiniemy do tego akapitu,
  /// ustawiając go na górze ekranu.
  Future<BookChapter> _initInitialChapter() async {
    // 1. Najpierw spróbuj tymczasowego skoku
    final jumpRef = await _prefs.getJumpChapterRef();
    final jumpParagraph = await _prefs.getJumpParagraphNumber();

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
    _paragraphKeys.clear();
    _selectedText = null;

    // Jeśli mamy jumpParagraph i dotyczy właśnie ładowanego rozdziału –
    // nie ładujemy offsetu scrolla, tylko planujemy skok do akapitu.
    if (jumpParagraph != null && refToLoad == _currentChapterRef) {
      _jumpParagraphNumber = jumpParagraph;
      _pendingJumpToParagraph = true;
      _pendingScrollOffset = null;
      await _prefs.clearJumpParagraphNumber();
    } else {
      _jumpParagraphNumber = null;
      _pendingJumpToParagraph = false;
      await _prefs.clearJumpParagraphNumber();
      await _loadScrollOffsetForChapter(_currentChapterRef);
    }

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

  /// Ładowanie rozdziału – opcjonalnie bez przywracania offsetu scrolla
  /// (gdy wskakujemy w środek rozdziału do konkretnego akapitu).
  void _loadChapterByReference(
    String reference, {
    bool saveAsLast = true,
    bool skipScrollOffset = false,
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
      _paragraphKeys.clear();
      // _jumpParagraphNumber / _pendingJumpToParagraph ustawiamy
      // z zewnątrz, np. w _maybeHandleExternalJump
    });

    if (saveAsLast) {
      _prefs.saveLastChapterRef(reference);
    }

    if (!skipScrollOffset) {
      _loadScrollOffsetForChapter(reference);
    }
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
                                      _jumpParagraphNumber = null;
                                      _pendingJumpToParagraph = false;
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
      _jumpParagraphNumber = null;
      _pendingJumpToParagraph = false;
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
      _jumpParagraphNumber = null;
      _pendingJumpToParagraph = false;
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

  /// Sprawdza, czy z zewnątrz nie ustawiono nowego jumpChapterRef / jumpParagraphNumber
  /// (losowy cytat / zakładka / ulubione / dziennik) i jeśli tak – ładuje odpowiedni rozdział
  /// lub przewija w bieżącym, bez nadpisywania lastChapterRef.
  void _maybeHandleExternalJump() {
    if (_isCheckingJump) return;
    _isCheckingJump = true;

    Future.microtask(() async {
      try {
        final jumpRef = await _prefs.getJumpChapterRef();
        final jumpParagraph = await _prefs.getJumpParagraphNumber();

        if ((jumpRef == null || jumpRef.isEmpty) &&
            jumpParagraph == null) {
          return;
        }

        // Jeśli podano rozdział i różni się od bieżącego – przeładuj rozdział.
        if (jumpRef != null &&
            jumpRef.isNotEmpty &&
            jumpRef != _currentChapterRef) {
          await _prefs.clearJumpChapterRef();
          if (jumpParagraph != null) {
            _jumpParagraphNumber = jumpParagraph;
            _pendingJumpToParagraph = true;
            await _prefs.clearJumpParagraphNumber();
          } else {
            _jumpParagraphNumber = null;
            _pendingJumpToParagraph = false;
          }
          _loadChapterByReference(
            jumpRef,
            saveAsLast: false,
            skipScrollOffset: jumpParagraph != null,
          );
        } else {
          // Ten sam rozdział, ale np. inny akapit
          if (jumpParagraph != null) {
            _jumpParagraphNumber = jumpParagraph;
            _pendingJumpToParagraph = true;
            await _prefs.clearJumpParagraphNumber();
            if (mounted) {
              setState(() {});
            }
          }
          if (jumpRef != null && jumpRef.isNotEmpty) {
            await _prefs.clearJumpChapterRef();
          }
        }
      } finally {
        _isCheckingJump = false;
      }
    });
  }

  /// Po złożeniu drzewa widgetów przewija (jeśli trzeba)
  /// - albo do zapisanego offsetu,
  /// - albo do konkretnego akapitu (ustawionego na górze ekranu).
  void _handlePostFrameScroll(BookChapter chapter) {
    // 1) Przywrócenie offsetu scrolla z prefs – tylko gdy NIE planujemy skoku do akapitu
    if (_pendingScrollOffset != null && !_pendingJumpToParagraph) {
      if (_scrollController.hasClients) {
        final max = _scrollController.position.maxScrollExtent;
        final target = _pendingScrollOffset!.clamp(
          0.0,
          max > 0 ? max : double.infinity,
        );
        _scrollController.jumpTo(target);
        _pendingScrollOffset = null;
      }
    }

    // 2) Skok do konkretnego akapitu – akapit ma być na górze ekranu
    if (_pendingJumpToParagraph && _jumpParagraphNumber != null) {
      final targetIndex =
          (_jumpParagraphNumber! - 1).clamp(0, chapter.paragraphs.length - 1);
      final key = _paragraphKeys[targetIndex];
      final ctx = key?.currentContext;
      if (ctx != null) {
        _pendingJumpToParagraph = false;
        _jumpParagraphNumber = null;
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.0, // 0.0 = górna krawędź widoku
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
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

                // Po złożeniu drzewa spróbuj przywrócić scroll / skoczyć do akapitu
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _handlePostFrameScroll(chapter);
                });

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
          SelectionArea(
            onSelectionChanged: (selected) {
              final text = selected?.plainText;
              if (!mounted) return;
              setState(() {
                final trimmed = text?.trim();
                _selectedText =
                    (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
              });
            },
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < chapter.paragraphs.length; i++) ...[
                    _buildParagraphText(chapter.paragraphs[i].text, i),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          if (_selectedText != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildSelectionToolbar(chapter),
            ),
        ],
      ),
    );
  }

  /// Pojedynczy akapit, opakowany w GlobalKey, żeby móc przewijać
  /// dokładnie do jego pozycji (na górę ekranu).
  Widget _buildParagraphText(String text, int index) {
    final key = _paragraphKeys.putIfAbsent(index, () => GlobalKey());

    return KeyedSubtree(
      key: key,
      child: Text(
        text,
        textAlign: _isJustified ? TextAlign.justify : TextAlign.left,
        style: TextStyle(
          fontSize: _fontSize,
          height: _lineHeight,
        ),
      ),
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

  Future<void> _addSelectionToFavorites(BookChapter chapter) async {
    final text = _selectedText?.trim();
    if (text == null || text.isEmpty) return;

    try {
      final paragraph = BookParagraph(
        index: 0, // wymagany parametr – sztuczny indeks dla zaznaczenia
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
}
