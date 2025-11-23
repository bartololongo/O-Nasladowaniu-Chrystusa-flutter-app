import 'package:flutter/material.dart';
import '../../shared/models/book_models.dart';
import '../../shared/services/book_repository.dart';
import '../../shared/services/preferences_service.dart';
import '../../shared/services/bookmarks_service.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final BookRepository _bookRepository = BookRepository();
  final PreferencesService _prefs = PreferencesService();
  final BookmarksService _bookmarksService = BookmarksService();

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

  void _loadChapterByReference(String reference, {bool saveAsLast = true}) {
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

  /// Sprawdza, czy z zewnątrz nie ustawiono nowego jumpChapterRef
  /// (losowy cytat / zakładka / ulubione) i jeśli tak – ładuje odpowiedni rozdział
  /// bez nadpisywania lastChapterRef.
  void _maybeHandleExternalJump() {
    if (_isCheckingJump) return;
    _isCheckingJump = true;

    Future.microtask(() async {
      try {
        final jumpRef = await _prefs.getJumpChapterRef();
        if (jumpRef != null &&
            jumpRef.isNotEmpty &&
            jumpRef != _currentChapterRef) {
          await _prefs.clearJumpChapterRef();
          _loadChapterByReference(jumpRef, saveAsLast: false);
        }
      } finally {
        _isCheckingJump = false;
      }
    });
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
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final paragraph in chapter.paragraphs) ...[
              SelectableText(
                paragraph.text,
                textAlign:
                    _isJustified ? TextAlign.justify : TextAlign.left,
                style: TextStyle(
                  fontSize: _fontSize,
                  height: _lineHeight,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
